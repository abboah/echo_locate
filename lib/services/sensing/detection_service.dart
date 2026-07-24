import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_object_detection/google_mlkit_object_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/logger.dart';
import 'detected_obstacle.dart';

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
  CameraController? _cameraController;
  ObjectDetector? _detector;
  bool _busy = false;
  bool _running = false;

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
    try {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        AppLogger.warn('Camera permission not granted — assist runs in demo mode');
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

      _detector = ObjectDetector(
        options: ObjectDetectorOptions(
          mode: DetectionMode.stream,
          classifyObjects: true,
          multipleObjects: true,
        ),
      );

      await _cameraController!.startImageStream(_onFrame);
      _running = true;
      return true;
    } catch (e) {
      AppLogger.warn('Camera/detector unavailable: $e');
      await stop();
      return false;
    }
  }

  Future<void> stop() async {
    _running = false;
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

  Future<void> _onFrame(CameraImage image) async {
    if (_busy || !_running || _detector == null) return;
    _busy = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final objects = await _detector!.processImage(input);
      if (!_running) return;

      // Frame dimensions in the rotated (upright) coordinate space that
      // ML Kit reports boxes in.
      final rotation = _currentRotation();
      final sideways = rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      final frameW = sideways ? image.height : image.width;
      final frameH = sideways ? image.width : image.height;

      final obstacles = objects.map((o) {
        final best = o.labels.isEmpty
            ? null
            : (o.labels..sort((a, b) => b.confidence.compareTo(a.confidence)))
                .first;
        final centerX = o.boundingBox.center.dx / frameW;
        return DetectedObstacle(
          label: _wordFor(best?.text),
          confidence: best?.confidence ?? 0,
          heightFraction:
              (o.boundingBox.height / frameH).clamp(0.0, 1.0).toDouble(),
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
        'ASSIST-FRAME ${image.width}x${image.height} '
        'rot=${rotation.rawValue} objects=${objects.length}'
        '${obstacles.isEmpty ? '' : ' :: ${obstacles.map((o) => '${o.label}'
            '/c${o.confidence.toStringAsFixed(2)}'
            '/h${o.heightFraction.toStringAsFixed(2)}'
            '/${o.position.name}').join(' | ')}'
            ' raw=${objects.map((o) => o.boundingBox).join(' ')}'}',
      );

      _obstaclesController.add(obstacles);
    } catch (e, stack) {
      AppLogger.error('Frame analysis failed: $e', e, stack);
    } finally {
      _busy = false;
    }
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
    final device =
        _deviceOrientations[controller.value.deviceOrientation] ?? 0;
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
