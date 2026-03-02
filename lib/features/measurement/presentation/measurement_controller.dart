import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controller for managing measurement state using Riverpod
class MeasurementController extends StateNotifier<MeasurementState> {
  MeasurementController() : super(const MeasurementState());

  Future<void> startMeasurement() async {
    // TODO: Implement start measurement logic
    // - Initialize audio service
    // - Start chirp generation
    // - Start listening for echo
    // - Calculate distance using ToF
    state = state.copyWith(isMeasuring: true);
  }

  Future<void> stopMeasurement() async {
    // TODO: Implement stop measurement logic
    state = state.copyWith(isMeasuring: false);
  }

  void updateDistance(double distance) {
    state = state.copyWith(currentDistance: distance);
  }

  void updateSignalStrength(double strength) {
    state = state.copyWith(signalStrength: strength);
  }
}

/// StateNotifier provider for measurement
final measurementControllerProvider =
    StateNotifierProvider<MeasurementController, MeasurementState>((ref) {
      return MeasurementController();
    });

/// State class for measurement
class MeasurementState {
  final bool isMeasuring;
  final double currentDistance;
  final double signalStrength;
  final String? errorMessage;

  const MeasurementState({
    this.isMeasuring = false,
    this.currentDistance = 0.0,
    this.signalStrength = 0.0,
    this.errorMessage,
  });

  MeasurementState copyWith({
    bool? isMeasuring,
    double? currentDistance,
    double? signalStrength,
    String? errorMessage,
  }) {
    return MeasurementState(
      isMeasuring: isMeasuring ?? this.isMeasuring,
      currentDistance: currentDistance ?? this.currentDistance,
      signalStrength: signalStrength ?? this.signalStrength,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
