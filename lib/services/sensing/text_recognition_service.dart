import 'dart:async';

import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

import '../../core/utils/logger.dart';

/// Live camera → ML Kit text recognition → [reads] stream.
///
/// The building's own signage is this app's positioning system, so this is the
/// sensor that says *where the user is*. It reports what it saw and nothing
/// more; deciding which landmark a read denotes belongs to `LandmarkMatcher`,
/// which is pure and therefore testable without a camera.
///
/// Unlike [DetectionService] this does **not** own the camera. Running two
/// image streams off one camera is not supported on Android, and running both
/// analysers on every frame starves each other on budget hardware — the device
/// this project targets. DetectionService owns the stream and hands frames
/// here on alternate ticks; see its `_onFrame`.
///
/// Idle unless [start] has been called, so screens that only need obstacle
/// detection pay nothing.
class TextRecognitionService {
  TextRecognizer? _recognizer;
  bool _active = false;

  final _readsController = StreamController<List<String>>.broadcast();

  /// Text lines seen in one frame, in ML Kit's reading order. Empty means a
  /// frame was analysed and held no text — distinct from no frame at all.
  ///
  /// Lines rather than blocks: a door plate is one line, and a directory board
  /// is many, each of which may name a different landmark. Blocks would glue
  /// a whole board into one string that matches nothing.
  Stream<List<String>> get reads => _readsController.stream;

  /// Whether frames should be routed here. Read by [DetectionService].
  bool get isActive => _active;

  /// Begins accepting frames. Cheap and synchronous — the recogniser is a
  /// local model, so there is no permission or download to await. The camera
  /// is already up, owned by [DetectionService].
  void start() {
    if (_active) return;
    _recognizer = TextRecognizer(script: TextRecognitionScript.latin);
    _active = true;
  }

  Future<void> stop() async {
    _active = false;
    await _recognizer?.close();
    _recognizer = null;
  }

  /// Analyses one frame. Called by [DetectionService] on the frames it yields;
  /// a no-op while stopped so a late frame after [stop] cannot resurrect it.
  Future<void> analyze(InputImage input) async {
    final recognizer = _recognizer;
    if (!_active || recognizer == null) return;
    try {
      final recognised = await recognizer.processImage(input);
      if (!_active) return;

      final lines = [
        for (final block in recognised.blocks)
          for (final line in block.lines)
            if (line.text.trim().isNotEmpty) line.text.trim(),
      ];

      // Evidence log for §10's read-range envelope: one line per analysed
      // frame. Grep for OCR-FRAME.
      AppLogger.info(
        'OCR-FRAME lines=${lines.length}'
        '${lines.isEmpty ? '' : ' :: ${lines.join(' | ')}'}',
      );

      _readsController.add(lines);
    } catch (e, stack) {
      AppLogger.error('Text recognition failed: $e', e, stack);
    }
  }

  Future<void> dispose() async {
    await stop();
    await _readsController.close();
  }
}
