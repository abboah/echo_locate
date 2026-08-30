import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/logger.dart';
import 'analysis_frame.dart';
import 'detected_obstacle.dart';
import 'text_recognition_service.dart';

/// Live camera → ML Kit object detection → [obstacles] stream.
///
/// GetIt-registered stream source per CLAUDE.md's live-sensing pattern:
/// the AssistBloc subscribes to [obstacles] and emits UI states; this class
/// owns all hardware. One frame is processed at a time (the busy flag is the
/// throttle), so slow devices simply analyze fewer frames.
///
/// ML Kit's base model localizes objects and classifies them into coarse
/// categories. A custom TFLite classifier (Phase 3) upgrades label detail;
/// the API here doesn't change.
class DetectionService {
  DetectionService({
    TextRecognitionService? textRecognition,
    AnalysisFrameSource? arFrames,
  }) : _textRecognition = textRecognition,
       _arFrames = arFrames;

  /// Sign reading, when a screen has switched it on. This class owns the only
  /// camera stream, so OCR cannot open its own — it is handed alternate frames
  /// instead. Null in tests and on screens that never read signage.
  final TextRecognitionService? _textRecognition;

  /// An AR session's camera frames, when one is running.
  ///
  /// **This is what keeps a blind user's guidance working on the AR screen.**
  /// ARCore holds the camera exclusively, so `CameraController` cannot be
  /// opened while it runs — obstacle detection and sign reading would both stop
  /// dead. Preferring this source when it is streaming means the analysers, the
  /// alternation, the label wording and the callout policy below are all
  /// untouched: only where the pixels came from changes.
  final AnalysisFrameSource? _arFrames;

  CameraController? _cameraController;
  ObjectDetector? _detector;
  bool _busy = false;
  bool _running = false;

  /// Set while frames are arriving from an AR session rather than the camera
  /// plugin. Read by screens deciding whether to draw a `CameraPreview` — in
  /// this mode there is no controller to preview, the camera being on screen as
  /// a `Texture` the AR session draws into.
  bool _fromAr = false;

  bool get isUsingArFrames => _fromAr;

  StreamSubscription<AnalysisFrame>? _arSubscription;

  /// Counts analysed frames so object detection and OCR can take turns.
  int _frameIndex = 0;

  final _obstaclesController =
      StreamController<List<DetectedObstacle>>.broadcast();

  /// Per-frame detections. Empty list = clear path.
  Stream<List<DetectedObstacle>> get obstacles => _obstaclesController.stream;

  /// For the CameraPreview widget. Null until [start] succeeds.
  CameraController? get camera => _cameraController;

  /// Brings up the camera + detector. Returns false when unavailable
  /// (permission denied, emulator without camera, etc.) — callers fall back
  /// to demo mode.
  Future<bool> start() async {
    if (_running) return true;

    // An AR session already has the camera, and nothing else can have it. Its
    // frames are the same NV21 the plugin would have produced, so everything
    // below this point is identical either way.
    //
    // `holdsCamera` rather than `isStreaming`: a session that is up but has not
    // turned its frame feed on yet is still holding the camera, and racing it
    // for one would fail and drop this screen into demo mode permanently.
    // Subscribing early costs nothing — the frames arrive when they arrive.
    final ar = _arFrames;
    if (ar != null && (ar.isStreaming || ar.holdsCamera)) {
      _detector = _buildDetector();
      _arSubscription = ar.analysisFrames.listen(_onArFrame);
      _running = true;
      _fromAr = true;
      AppLogger.info(
        'Detection running on AR session frames'
        '${ar.isStreaming ? '' : ' (waiting for the feed to start)'}',
      );
      return true;
    }

    try {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        AppLogger.warn(
          'Camera permission not granted — assist runs in demo mode',
        );
        return false;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) return false;
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        back,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      await _cameraController!.initialize();

      _detector = _buildDetector();

      await _cameraController!.startImageStream(_onFrame);
      _running = true;
      return true;
    } catch (e) {
      AppLogger.warn('Camera/detector unavailable: $e');
      await stop();
      return false;
    }
  }

  static ObjectDetector _buildDetector() => ObjectDetector(
    options: ObjectDetectorOptions(
      mode: DetectionMode.stream,
      classifyObjects: true,
      multipleObjects: true,
    ),
  );

  Future<void> stop() async {
    _running = false;
    _fromAr = false;
    await _arSubscription?.cancel();
    _arSubscription = null;
    try {
      if (_cameraController?.value.isStreamingImages ?? false) {
        await _cameraController?.stopImageStream();
      }
    } catch (_) {}
    await _cameraController?.dispose();
    _cameraController = null;
    await _detector?.close();
    _detector = null;
  }

  /// One frame from an AR session.
  ///
  /// The session sends one at a time and waits to be told it has been analysed
  /// — see [AnalysisFrameSource.frameHandled] — so the rate is set by how fast
  /// this returns rather than by a number guessed in advance. The busy flag is
  /// still here for the case where that answer went missing and the session
  /// restarted the feed on its timeout: queueing frames behind a slow model is
  /// how an obstacle warning arrives after the obstacle.
  Future<void> _onArFrame(AnalysisFrame frame) async {
    if (_busy || !_running || _detector == null) return;
    _busy = true;
    try {
      final rotation =
          InputImageRotationValue.fromRawValue(frame.rotationDegrees) ??
          InputImageRotation.rotation0deg;
      final input = InputImage.fromBytes(
        bytes: frame.bytes,
        metadata: InputImageMetadata(
          size: Size(frame.width.toDouble(), frame.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: frame.width,
        ),
      );
      await _analyse(
        input,
        frameWidth: frame.uprightWidth,
        frameHeight: frame.uprightHeight,
        rotation: rotation,
        sourceWidth: frame.width,
        sourceHeight: frame.height,
      );
    } catch (e, stack) {
      AppLogger.error('AR frame analysis failed: $e', e, stack);
    } finally {
      _busy = false;
      // Asked for the next one even when this one threw: a single bad frame
      // must not be the end of obstacle detection for the walk.
      _arFrames?.frameHandled();
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || !_running || _detector == null) return;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;

      final rotation = _currentRotation();
      final sideways =
          rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      await _analyse(
        input,
        frameWidth: sideways ? image.height : image.width,
        frameHeight: sideways ? image.width : image.height,
        rotation: rotation,
        sourceWidth: image.width,
        sourceHeight: image.height,
      );
    } catch (e, stack) {
      AppLogger.error('Frame analysis failed: $e', e, stack);
    } finally {
      _busy = false;
    }
  }

  /// One frame, whatever produced it.
  ///
  /// [frameWidth] and [frameHeight] are the **upright** dimensions — the space
  /// ML Kit reports boxes in — while [sourceWidth] and [sourceHeight] are the
  /// image as it arrived, and are only for the evidence log. Passing the wrong
  /// pair swaps the axes of every obstacle's position and height, which reads
  /// as the detector being wrong rather than the caller.
  Future<void> _analyse(
    InputImage input, {
    required int frameWidth,
    required int frameHeight,
    required InputImageRotation rotation,
    required int sourceWidth,
    required int sourceHeight,
  }) async {
    // Alternate: objects on even frames, signage on odd. Both analysers on
    // every frame would halve the rate of each on the budget hardware this
    // targets, and an obstacle warning that arrives late is worse than one
    // that arrives at half the frame rate.
    final text = _textRecognition;
    final readsThisFrame = text != null && text.isActive && _frameIndex.isOdd;
    _frameIndex++;
    if (readsThisFrame) {
      await text.analyze(input);
      return;
    }

    final objects = await _detector!.processImage(input);
    if (!_running) return;

    final frameW = frameWidth;
    final frameH = frameHeight;

    final obstacles = objects.map((o) {
        final best = o.labels.isEmpty
            ? null
            : (o.labels..sort((a, b) => b.confidence.compareTo(a.confidence)))
                  .first;
        final centerX = o.boundingBox.center.dx / frameW;
        return DetectedObstacle(
          label: _wordFor(best?.text),
          confidence: best?.confidence ?? 0,
          heightFraction: (o.boundingBox.height / frameH)
              .clamp(0.0, 1.0)
              .toDouble(),
          position: centerX < 0.35
              ? ObstaclePosition.left
              : centerX > 0.65
              ? ObstaclePosition.right
              : ObstaclePosition.center,
        );
      }).toList();

    // Evidence log: one line per analyzed frame (raw ML Kit output +
    // what the callout policy will see). Grep for ASSIST-FRAME.
    AppLogger.info(
      'ASSIST-FRAME ${sourceWidth}x$sourceHeight '
      '${_fromAr ? 'ar ' : ''}'
      'rot=${rotation.rawValue} objects=${objects.length}'
      '${obstacles.isEmpty ? '' : ' :: ${obstacles.map((o) => '${o.label}'
                    '/c${o.confidence.toStringAsFixed(2)}'
                    '/h${o.heightFraction.toStringAsFixed(2)}'
                    '/${o.position.name}').join(' | ')}'
                ' raw=${objects.map((o) => o.boundingBox).join(' ')}'}',
    );

    _obstaclesController.add(obstacles);
  }

  static const _deviceOrientations = {
    DeviceOrientation.portraitUp: 0,
    DeviceOrientation.landscapeLeft: 90,
    DeviceOrientation.portraitDown: 180,
    DeviceOrientation.landscapeRight: 270,
  };

  InputImageRotation _currentRotation() {
    final controller = _cameraController;
    if (controller == null) return InputImageRotation.rotation0deg;
    final sensor = controller.description.sensorOrientation;
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(sensor) ??
          InputImageRotation.rotation0deg;
    }
    final device = _deviceOrientations[controller.value.deviceOrientation] ?? 0;
    final compensated =
        controller.description.lensDirection == CameraLensDirection.front
        ? (sensor + device) % 360
        : (sensor - device + 360) % 360;
    return InputImageRotationValue.fromRawValue(compensated) ??
        InputImageRotation.rotation0deg;
  }

  InputImage? _toInputImage(CameraImage image) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    // NV21 (Android) / BGRA8888 (iOS) arrive as a single usable plane.
    if (format == null || image.planes.isEmpty) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: plane.bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: _currentRotation(),
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  /// ML Kit base-model categories → words a person wants to hear.
  String _wordFor(String? category) => switch (category) {
    'Home good' => 'furniture',
    'Fashion good' => 'clothing item',
    'Food' => 'food item',
    'Plant' => 'plant',
    'Place' => 'doorway',
    _ => 'obstacle',
  };
}
