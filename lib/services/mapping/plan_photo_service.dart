import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/logger.dart';

/// Takes the one still photo the tracing screen draws on: the floor plan or
/// fire-escape map posted on the building's wall.
///
/// Deliberately a separate service from [DetectionService] rather than a mode
/// of it. That one holds a streaming controller tuned for ML Kit — medium
/// resolution, NV21, frames arriving continuously — and a floor plan needs the
/// opposite: one frame, as much detail as the sensor gives, since the
/// contributor is about to read room numbers off it.
///
/// A failure here is not fatal to tracing. The plan photo is a backdrop to tap
/// against; the graph is the taps. [start] returning false leaves the screen
/// usable on a blank grid, which is also how it stays testable on a device with
/// no camera.
class PlanPhotoService {
  CameraController? _controller;

  /// For the preview widget. Null until [start] succeeds.
  CameraController? get camera => _controller;

  bool get isReady => _controller?.value.isInitialized ?? false;

  Future<bool> start() async {
    if (isReady) return true;
    try {
      final permission = await Permission.camera.request();
      if (!permission.isGranted) {
        AppLogger.warn('Camera permission not granted — tracing on a blank grid');
        return false;
      }

      final cameras = await availableCameras();
      if (cameras.isEmpty) return false;
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      // High, not medium: the contributor reads room numbers off this photo
      // while tracing, and a plan shot at preview resolution is unreadable.
      _controller = CameraController(back, ResolutionPreset.high,
          enableAudio: false);
      await _controller!.initialize();
      return true;
    } catch (e) {
      AppLogger.warn('Plan camera unavailable: $e');
      await stop();
      return false;
    }
  }

  /// Path of the captured still, or null when the camera could not take one.
  Future<String?> capture() async {
    if (!isReady) return null;
    try {
      final file = await _controller!.takePicture();
      return file.path;
    } catch (e) {
      AppLogger.warn('Plan capture failed: $e');
      return null;
    }
  }

  Future<void> stop() async {
    final controller = _controller;
    _controller = null;
    try {
      await controller?.dispose();
    } catch (e) {
      AppLogger.warn('Plan camera dispose failed: $e');
    }
  }
}
