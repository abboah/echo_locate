import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Controller for managing floor plan state using Riverpod
class FloorPlanController extends StateNotifier<FloorPlanState> {
  FloorPlanController() : super(const FloorPlanState());

  Future<void> startScanning() async {
    // TODO: Implement floor plan scanning logic
    // - Initialize motion sensors
    // - Start continuous distance measurement
    // - Track position using accelerometer/gyroscope
    state = state.copyWith(isScanning: true);
  }

  Future<void> stopScanning() async {
    // TODO: Implement stop scanning logic
    state = state.copyWith(isScanning: false);
  }

  void addPoint(double x, double y, double distance, double angle) {
    // TODO: Add measurement point to current floor plan
    state = state.copyWith(
      points: [
        ...state.points,
        {'x': x, 'y': y, 'distance': distance, 'angle': angle},
      ],
    );
  }

  void clearPoints() {
    state = state.copyWith(points: []);
  }
}

/// State class for floor plan
class FloorPlanState {
  final bool isScanning;
  final List<Map<String, double>> points;
  final String? errorMessage;

  const FloorPlanState({
    this.isScanning = false,
    this.points = const [],
    this.errorMessage,
  });

  FloorPlanState copyWith({
    bool? isScanning,
    List<Map<String, double>>? points,
    String? errorMessage,
  }) {
    return FloorPlanState(
      isScanning: isScanning ?? this.isScanning,
      points: points ?? this.points,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
