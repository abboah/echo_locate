import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';
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
  ///
  /// The still is moved out of the camera's own directory before being
  /// returned. `takePicture` writes into the **cache**, which Android is free
  /// to delete whenever it wants space back — so a plan re-opened later came
  /// up on a blank grid, its landmarks floating over nothing. One photo per
  /// building and floor, overwritten by a re-shoot.
  Future<String?> capture(String buildingId, String floorId) async {
    if (!isReady) return null;
    try {
      final shot = await _controller!.takePicture();
      final destination = await _pathFor(buildingId, floorId);
      await Directory(destination).parent.create(recursive: true);
      await File(shot.path).copy(destination);
      // Best-effort: a cache file left behind costs space, not correctness.
      try {
        await File(shot.path).delete();
      } catch (_) {}
      return destination;
    } catch (e) {
      AppLogger.warn('Plan capture failed: $e');
      return null;
    }
  }

  /// Every floor of [buildingId] that already has a photo, floor id → path.
  ///
  /// Read on start so re-opening a part-traced building shows the plan the
  /// existing landmarks were placed on, rather than asking for it again.
  Future<Map<String, String>> storedPhotos(String buildingId) async {
    try {
      final directory = Directory(await _directoryFor(buildingId));
      if (!directory.existsSync()) return const {};
      return {
        for (final entity in directory.listSync())
          if (entity is File && entity.path.endsWith('.jpg'))
            entity.uri.pathSegments.last.replaceAll('.jpg', ''): entity.path,
      };
    } catch (e) {
      AppLogger.warn('Stored plan photos unavailable: $e');
      return const {};
    }
  }

  /// Forgets one floor's photo, so a re-shoot does not leave the old one to be
  /// restored next time.
  Future<void> discard(String buildingId, String floorId) async {
    try {
      final file = File(await _pathFor(buildingId, floorId));
      if (file.existsSync()) await file.delete();
    } catch (e) {
      AppLogger.warn('Could not discard plan photo: $e');
    }
  }

  Future<String> _directoryFor(String buildingId) async {
    final root = await getApplicationDocumentsDirectory();
    return '${root.path}/plan_photos/${_safe(buildingId)}';
  }

  Future<String> _pathFor(String buildingId, String floorId) async =>
      '${await _directoryFor(buildingId)}/${_safe(floorId)}.jpg';

  /// Building ids are slugs and floor ids are uuids, but neither is ours to
  /// trust as a path segment.
  static String _safe(String id) =>
      id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');

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
