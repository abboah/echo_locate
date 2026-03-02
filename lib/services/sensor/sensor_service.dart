import 'dart:async';

/// Service for accessing device sensors (accelerometer, gyroscope)
class SensorService {
  // TODO: Implement sensor access using sensors_plus

  StreamSubscription<dynamic>? _accelerometerSubscription;
  StreamSubscription<dynamic>? _gyroscopeSubscription;

  final _accelerometerController =
      StreamController<Map<String, double>>.broadcast();
  final _gyroscopeController =
      StreamController<Map<String, double>>.broadcast();

  /// Start listening to accelerometer data
  void startAccelerometer() {
    // TODO: Implement accelerometer using sensors_plus
    // sensors_plus.accelerometerEvents.listen((event) {
    //   _accelerometerController.add({
    //     'x': event.x,
    //     'y': event.y,
    //     'z': event.z,
    //   });
    // });
  }

  /// Start listening to gyroscope data
  void startGyroscope() {
    // TODO: Implement gyroscope using sensors_plus
    // sensors_plus.gyroscopeEvents.listen((event) {
    //   _gyroscopeController.add({
    //     'x': event.x,
    //     'y': event.y,
    //     'z': event.z,
    //   });
    // });
  }

  /// Stop listening to accelerometer
  void stopAccelerometer() {
    _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
  }

  /// Stop listening to gyroscope
  void stopGyroscope() {
    _gyroscopeSubscription?.cancel();
    _gyroscopeSubscription = null;
  }

  /// Stream of accelerometer data
  Stream<Map<String, double>> get accelerometerStream =>
      _accelerometerController.stream;

  /// Stream of gyroscope data
  Stream<Map<String, double>> get gyroscopeStream =>
      _gyroscopeController.stream;

  /// Dispose all resources
  void dispose() {
    stopAccelerometer();
    stopGyroscope();
    _accelerometerController.close();
    _gyroscopeController.close();
  }
}
