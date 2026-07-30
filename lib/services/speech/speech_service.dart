import 'package:flutter_tts/flutter_tts.dart';

import '../../core/utils/logger.dart';

/// App voice. Wraps flutter_tts so Blocs can speak without owning a plugin;
/// Phase 3's navigation directions and voice mode reuse this.
class SpeechService {
  final FlutterTts _tts = FlutterTts();
  bool _configured = false;

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    try {
      await _tts.setSpeechRate(0.5);
      await _tts.awaitSpeakCompletion(false);
      _configured = true;
    } catch (e) {
      AppLogger.warn('TTS configuration failed: $e');
    }
  }

  /// Speaks [text]. When [interrupt] is true (urgent callouts), cuts off
  /// whatever is currently being said.
  Future<void> speak(String text, {bool interrupt = false}) async {
    try {
      await _ensureConfigured();
      if (interrupt) await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      // No TTS engine (some emulators) — the visual callout still shows.
      AppLogger.warn('TTS unavailable: $e');
    }
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }
}
