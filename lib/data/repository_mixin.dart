import 'package:hive_ce_flutter/hive_ce_flutter.dart';

/// Box backing [RepositoryMixin.runPersistedQuery]. Opened once at startup in
/// `configureDependencies()`.
const String repoCacheBoxName = 'repo_cache';

/// Typed, human-readable failure raised by repository operations.
///
/// UI layers (Blocs) surface [message] directly and never see raw
/// exceptions/stack traces.
class OperationFailure implements Exception {
  const OperationFailure(this.message, [this.cause]);

  final String message;
  final Object? cause;

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

  /// Wipe the session cache (e.g. on sign-out).
  static void clearEphemeralCache() => _ephemeral.clear();

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
    final value = await fetch();
    if (encode != null) await box.put(key, encode(value));
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
      await box.put(key, encode(value));
      return value;
    } catch (_) {
      final cached = box.get(key);
      if (cached != null) {
        try {
          return decode(cached);
        } catch (_) {
          // Stale/incompatible cache — surface the original failure instead.
        }
      }
      rethrow;
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
    final value = await fetch();
    _ephemeral[key] = value;
    return value;
  }

  Future<T> runOperation<T>(String name, Future<T> Function() op) async {
    try {
      return await op();
    } on OperationFailure {
      rethrow;
    } catch (e) {
      throw OperationFailure('Something went wrong. Please try again.', e);
    }
  }
}
