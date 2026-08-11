import 'dart:async';
import 'dart:io';

import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import '../core/utils/logger.dart';

/// Box backing [RepositoryMixin.runPersistedQuery]. Opened once at startup in
/// `configureDependencies()`.
const String repoCacheBoxName = 'repo_cache';

/// Typed, human-readable failure raised by repository operations.
///
/// UI layers (Blocs) surface [message] directly and never see raw
/// exceptions/stack traces.
class OperationFailure implements Exception {
  const OperationFailure(this.message, [this.cause]);

  /// Turns anything thrown into something a user can read.
  ///
  /// The single place that decides what an unrecognised error says, so a Bloc
  /// can catch broadly — `catch (e) { … OperationFailure.from(e).message }` —
  /// and still never put a stack trace on screen. Catching narrowly is what
  /// left screens spinning; catching broadly without this would leak
  /// "PostgrestException(message: JWT expired…)" to a blind user's TalkBack.
  factory OperationFailure.from(Object error) => error is OperationFailure
      ? error
      : OperationFailure(
          _looksLikeConnectivity(error)
              ? 'Could not connect. Check your connection and try again.'
              : 'Something went wrong. Please try again.',
          error,
        );

  final String message;
  final Object? cause;

  /// Whether a failure is the network being unavailable rather than the app
  /// being wrong.
  ///
  /// Worth separating because the two need different things from the user, and
  /// indoors — the environment this app is built for — the first is normal.
  /// The string check is deliberate: Supabase wraps the real
  /// [SocketException] inside its own `ClientException`, so the type alone
  /// misses the common case.
  static bool _looksLikeConnectivity(Object error) {
    if (error is SocketException || error is TimeoutException) return true;
    final text = error.toString().toLowerCase();
    return text.contains('socketexception') ||
        text.contains('failed host lookup') ||
        text.contains('connection closed') ||
        text.contains('connection refused') ||
        text.contains('network is unreachable');
  }

  @override
  String toString() => message;
}

/// Achieve-style repository caching, adapted to hive_ce.
///
/// Three strategies (see CLAUDE.md):
/// - [runPersistedQuery] — Hive-backed cache that survives restarts. For data
///   that doesn't change every second (buildings, profiles).
/// - [runEphemeralQuery] — in-memory, session-scoped. Search results, lists.
/// - [runOperation] — no caching; wraps mutations so raw errors become
///   [OperationFailure]s.
///
/// The cache is a performance optimization, not correctness: if a cached
/// value fails to decode (schema drift after an update), we silently fall
/// through to a fresh fetch.
mixin RepositoryMixin {
  static final Map<String, Object?> _ephemeral = {};

  /// How long any single request may take before it is treated as a
  /// connection failure.
  ///
  /// Android's DNS resolver takes the better part of a minute to give up on a
  /// host it cannot resolve, and Supabase does not impose its own deadline. On
  /// a device with no route out, sign-in therefore sat spinning for ~40s
  /// before the error appeared — long enough that the app looked broken rather
  /// than offline. Long enough here for a slow campus connection to answer;
  /// short enough that a user learns something is wrong while still looking at
  /// the screen.
  static const Duration defaultTimeout = Duration(seconds: 15);

  /// Overridable so tests do not have to wait [defaultTimeout].
  static Duration requestTimeout = defaultTimeout;

  /// Wipe the session cache (e.g. on sign-out).
  static void clearEphemeralCache() => _ephemeral.clear();

  /// Runs a fetch and converts anything it throws into an [OperationFailure].
  ///
  /// The Blocs all catch `OperationFailure` and nothing else, because of the
  /// promise at the top of this file. It was not being kept: Supabase throws
  /// `PostgrestException` and `AuthException`, the socket throws
  /// `SocketException`, Hive throws `HiveError`, and every one of those sailed
  /// past the handler. A Bloc that never emits leaves its screen on a loading
  /// spinner **forever** — which is exactly how the app failed on a device.
  static Future<T> _guarded<T>(Future<T> Function() fetch) async {
    try {
      return await fetch().timeout(requestTimeout);
    } on OperationFailure {
      rethrow;
    } catch (error, stack) {
      AppLogger.error('Repository query failed: $error', error, stack);
      throw _translate(error);
    }
  }

  static OperationFailure _translate(Object error) =>
      OperationFailure.from(error);

  /// Writes to the cache without ever failing the query.
  ///
  /// The data is already in hand; losing it because the *cache* could not
  /// store it would be perverse. A real instance of this: models whose
  /// `toJson` left nested objects unencoded made Hive throw
  /// "Cannot write, unknown type: _Room", and the building screen — which had
  /// its floors — showed a spinner instead.
  static Future<void> _cache(String key, Object? value) async {
    try {
      await Hive.box(repoCacheBoxName).put(key, value);
    } catch (error, stack) {
      AppLogger.error('Cache write failed for "$key": $error', error, stack);
    }
  }

  Future<T> runPersistedQuery<T>(
    String key,
    Future<T> Function() fetch, {
    Object? Function(T value)? encode,
    T Function(Object? cached)? decode,
    bool remoteOnly = false,
  }) async {
    final box = Hive.box(repoCacheBoxName);
    if (!remoteOnly && decode != null) {
      final cached = box.get(key);
      if (cached != null) {
        try {
          return decode(cached);
        } catch (_) {
          // Stale/incompatible cache — fall through to a fresh fetch.
        }
      }
    }
    final value = await _guarded(fetch);
    if (encode != null) await _cache(key, encode(value));
    return value;
  }

  /// Network-first with a Hive fallback: fetches fresh data and caches it, but
  /// returns the last cached value when the fetch fails.
  ///
  /// This is what "works offline" means for the crowdsourced map — the index
  /// changes as people contribute, so a cache-first read ([runPersistedQuery])
  /// would pin the user to whatever they saw first. If there is no cache and
  /// the network is down, the original failure surfaces.
  Future<T> runOfflineFirstQuery<T>(
    String key,
    Future<T> Function() fetch, {
    required Object? Function(T value) encode,
    required T Function(Object? cached) decode,
  }) async {
    final box = Hive.box(repoCacheBoxName);
    try {
      final value = await fetch();
      await _cache(key, encode(value));
      return value;
    } catch (error, stack) {
      final cached = box.get(key);
      if (cached != null) {
        try {
          final value = decode(cached);
          AppLogger.warn('Serving "$key" from cache: $error');
          return value;
        } catch (_) {
          // Stale/incompatible cache — surface the original failure instead.
        }
      }
      if (error is OperationFailure) rethrow;
      AppLogger.error('Repository query failed: $error', error, stack);
      throw _translate(error);
    }
  }

  Future<T> runEphemeralQuery<T>(
    String key,
    Future<T> Function() fetch, {
    bool refresh = false,
  }) async {
    if (!refresh && _ephemeral.containsKey(key)) {
      return _ephemeral[key] as T;
    }
    final value = await _guarded(fetch);
    _ephemeral[key] = value;
    return value;
  }

  Future<T> runOperation<T>(String name, Future<T> Function() op) async {
    try {
      return await op().timeout(requestTimeout);
    } on OperationFailure {
      rethrow;
    } catch (error, stack) {
      AppLogger.error('Operation "$name" failed: $error', error, stack);
      throw OperationFailure.from(error);
    }
  }
}
