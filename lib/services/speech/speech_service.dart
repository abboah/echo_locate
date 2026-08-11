import 'dart:async';

import 'package:flutter_tts/flutter_tts.dart';

import '../../core/utils/logger.dart';
import '../audio/audio_arbiter.dart';

/// App voice. Wraps flutter_tts so Blocs can speak without owning a plugin;
/// Phase 3's navigation directions and voice mode reuse this.
class SpeechService {
  SpeechService({AudioArbiter? arbiter}) : _arbiter = arbiter;

  /// Claims the speaker ahead of sonar. Null where nothing else contends for
  /// audio, in which case speech just talks.
  final AudioArbiter? _arbiter;

  final FlutterTts _tts = FlutterTts();
  bool _configured = false;

  /// Upper bound on how long one utterance may hold the speaker.
  ///
  /// Completion comes from the TTS engine, and an engine that never reports
  /// back would otherwise hold the audio lease forever — starving sonar for
  /// the rest of the session. Generous enough for a long navigation
  /// instruction.
  static const Duration _maxUtterance = Duration(seconds: 20);

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    try {
      await _tts.setSpeechRate(0.5);
      // Await completion so the audio lease is held for the actual duration of
      // the utterance rather than just the time it took to hand it to the
      // engine. Callers fire-and-forget, so nothing blocks on this.
      await _tts.awaitSpeakCompletion(true);
      _configured = true;
    } catch (e) {
      AppLogger.warn('TTS configuration failed: $e');
    }
  }

  /// Speaks [text]. When [interrupt] is true (urgent callouts), cuts off
  /// whatever is currently being said.
  ///
  /// Takes the speaker from sonar if a measurement is in flight — see
  /// [AudioUse.speech] for why speech outranks ranging.
  ///
  /// [use] names the priority explicitly, for callers with more than two
  /// tiers: guidance has four, and collapsing them onto a bool would let a
  /// progress update talk over the landmark confirmation that supersedes it.
  Future<void> speak(
    String text, {
    bool interrupt = false,
    AudioUse? use,
  }) async {
    final claim =
        use ?? (interrupt ? AudioUse.urgentSpeech : AudioUse.speech);
    final lease = await _arbiter?.acquire(claim);
    if (_arbiter != null && lease == null) {
      // A routine callout refused by another utterance: the running one is at
      // least as current as this text. An urgent one is never refused here —
      // it outranks anything but another urgent callout.
      AppLogger.debug('SPEECH skipped :: already speaking');
      return;
    }

    // Stop synthesising the moment something more urgent wants the speaker.
    // `stop` completes this call's pending `speak` future, so the lease is
    // released in the `finally` below within milliseconds rather than being
    // held until the pre-emption timeout expires.
    lease?.onCancelled(() => unawaited(stop()));

    try {
      await _ensureConfigured();
      if (interrupt) await _tts.stop();
      await _tts.speak(text).timeout(_maxUtterance, onTimeout: () {
        AppLogger.warn('TTS did not report completion within $_maxUtterance');
        return null;
      });
    } catch (e) {
      // No TTS engine (some emulators) — the visual callout still shows.
      AppLogger.warn('TTS unavailable: $e');
    } finally {
      lease?.release();
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
