import 'dart:async';
import 'dart:math' as math;

import 'package:sensors_plus/sensors_plus.dart';

/// Service for accessing device sensors for orientation tracking
class SensorService {
  // Sensor subscription management
  StreamSubscription<MagnetometerEvent>? _magnetometerSub;
  StreamSubscription<AccelerometerEvent>? _accelerometerSub;

  // Orientation data (in degrees)
  double _azimuth = 0.0; // Compass heading (0-360 degrees)
  double _pitch = 0.0; // Tilt forward/backward
  double _roll = 0.0; // Tilt left/right

  // Stream controllers for real-time UI updates
  final _azimuthController = StreamController<double>.broadcast();
  final _pitchController = StreamController<double>.broadcast();
  final _rollController = StreamController<double>.broadcast();

  // Most recent sensor values
  double _magnetometerX = 0.0;
  double _magnetometerY = 0.0;
  double _accelerometerX = 0.0;
  double _accelerometerY = 0.0;
  double _accelerometerZ = 0.0;

  /// Start listening to magnetometer and accelerometer sensors
  ///
  /// Updates azimuth, pitch, roll on each event.
  /// For azimuth: use atan2(magnetometer.y, magnetometer.x) converted to degrees
  void startListening() {
    // Subscribe to magnetometer event stream
    // The magnetometer provides raw compass heading data
    _magnetometerSub = magnetometerEventStream().listen((
      MagnetometerEvent event,
    ) {
      _magnetometerX = event.x;
      _magnetometerY = event.y;

      // Calculate azimuth from magnetometer data
      // azimuth = atan2(magnetometer.y, magnetometer.x) converted to degrees
      // atan2 returns angle in radians from -π to π
      final azimuthRad = math.atan2(_magnetometerY, _magnetometerX);

      // Convert from radians to degrees and normalize to 0-360
      _azimuth = (azimuthRad * 180 / math.pi + 360) % 360;

      // Emit azimuth update
      _azimuthController.add(_azimuth);
    });

    // Subscribe to accelerometer event stream
    // The accelerometer provides device tilt information
    _accelerometerSub = accelerometerEventStream().listen((
      AccelerometerEvent event,
    ) {
      _accelerometerX = event.x;
      _accelerometerY = event.y;
      _accelerometerZ = event.z;

      // Calculate pitch from accelerometer
      // pitch = atan2(-x, sqrt(y² + z²)) converted to degrees
      // This represents tilt forward/backward
      final pitchRad = math.atan2(
        -_accelerometerX,
        math.sqrt(
          _accelerometerY * _accelerometerY + _accelerometerZ * _accelerometerZ,
        ),
      );
      _pitch = pitchRad * 180 / math.pi;

      // Calculate roll from accelerometer
      // roll = atan2(y, z) converted to degrees
      // This represents tilt left/right
      final rollRad = math.atan2(_accelerometerY, _accelerometerZ);
      _roll = rollRad * 180 / math.pi;

      // Emit pitch and roll updates
      _pitchController.add(_pitch);
      _rollController.add(_roll);
    });
  }

  /// Stop listening to sensor streams
  void stopListening() {
    _magnetometerSub?.cancel();
    _magnetometerSub = null;
    _accelerometerSub?.cancel();
    _accelerometerSub = null;
  }

  /// Get current azimuth normalized to 0-360 degrees
  ///
  /// Returns compass heading where:
  /// - 0° = North
  /// - 90° = East
  /// - 180° = South
  /// - 270° = West
  double getCurrentAzimuth() {
    // Normalize to 0-360 range
    final normalized = (_azimuth % 360 + 360) % 360;
    return normalized;
  }

  /// Get current pitch (tilt forward/backward)
  double getCurrentPitch() {
    return _pitch;
  }

  /// Get current roll (tilt left/right)
  double getCurrentRoll() {
    return _roll;
  }

  /// Stream for real-time azimuth updates
  /// Emits new azimuth values whenever compass heading changes
  Stream<double> get azimuthStream => _azimuthController.stream;

  /// Stream for real-time pitch updates
  /// Emits new pitch values whenever device tilt changes
  Stream<double> get pitchStream => _pitchController.stream;

  /// Stream for real-time roll updates
  /// Emits new roll values whenever device tilt changes
  Stream<double> get rollStream => _rollController.stream;

  /// Dispose all resources
  void dispose() {
    stopListening();
    _azimuthController.close();
    _pitchController.close();
    _rollController.close();
  }
}
