import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:echo_locate/core/utils/logger.dart';
import 'package:echo_locate/core/database/database_providers.dart';
import 'package:echo_locate/features/floorplan/data/floorplan_repository.dart';
import 'package:echo_locate/features/floorplan/domain/floorplan_model.dart';
import 'package:echo_locate/features/measurement/presentation/measurement_controller.dart'; // For audioServiceProvider
import 'package:echo_locate/services/sensor/sensor_service.dart';
import 'package:echo_locate/shared/models/measurement_point.dart';
import '../../../services/audio/audio_service.dart';

/// Controller for managing floor plan state using Riverpod
class FloorPlanController extends StateNotifier<FloorPlanState> {
  final AudioService _audioService;
  final SensorService _sensorService;
  final FloorPlanRepository _repository;

  FloorPlanController(this._audioService, this._sensorService, this._repository)
    : super(const FloorPlanState()) {
    _loadFloorPlans();
  }

  /// Load all floor plans from database
  Future<void> _loadFloorPlans() async {
    try {
      final floorPlans = await _repository.getAllFloorPlans();
      state = state.copyWith(floorPlans: floorPlans);
      AppLogger.info('Loaded ${floorPlans.length} floor plans');
    } catch (e) {
      AppLogger.error('Failed to load floor plans: $e');
      state = state.copyWith(errorMessage: 'Failed to load floor plans');
    }
  }

  /// Start scanning for a new floor plan
  Future<void> startScanning(
    String floorPlanName, {
    String? description,
  }) async {
    try {
      AppLogger.info('Starting floor plan scan: $floorPlanName');

      // Create new floor plan
      final floorPlan = FloorPlan(
        id: _generateId(),
        name: floorPlanName,
        description: description,
        points: const [],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        metadata: FloorPlanMetadata(
          totalPoints: 0,
          areaEstimate: 0.0,
          measurementDate: DateTime.now(),
        ),
      );

      state = state.copyWith(
        isScanning: true,
        currentFloorPlan: floorPlan,
        errorMessage: null,
      );

      AppLogger.info('Floor plan scan started');
    } catch (e) {
      AppLogger.error('Failed to start scanning: $e');
      state = state.copyWith(errorMessage: 'Failed to start scanning');
    }
  }

  /// Stop scanning and save the floor plan
  Future<void> stopScanning() async {
    try {
      if (state.currentFloorPlan == null) {
        AppLogger.warn('No active floor plan to stop');
        return;
      }

      AppLogger.info('Stopping floor plan scan');

      final floorPlan = state.currentFloorPlan!;
      final scanDuration = DateTime.now().difference(
        floorPlan.metadata.measurementDate,
      );

      // Update metadata
      final updatedFloorPlan = floorPlan.copyWith(
        updatedAt: DateTime.now(),
        metadata: floorPlan.metadata.copyWith(scanDuration: scanDuration),
      );

      // Save to database
      await _repository.saveFloorPlan(updatedFloorPlan);

      // Update state
      final updatedFloorPlans = [updatedFloorPlan, ...state.floorPlans];
      state = state.copyWith(
        isScanning: false,
        currentFloorPlan: null,
        floorPlans: updatedFloorPlans,
      );

      AppLogger.info(
        'Floor plan saved: ${floorPlan.name} (${floorPlan.points.length} points)',
      );
    } catch (e) {
      AppLogger.error('Failed to stop scanning: $e');
      state = state.copyWith(
        isScanning: false,
        errorMessage: 'Failed to save floor plan',
      );
    }
  }

  /// Add a measurement point to the current floor plan
  Future<void> addMeasurementPoint() async {
    try {
      if (!state.isScanning || state.currentFloorPlan == null) {
        AppLogger.warn('Cannot add point: not currently scanning');
        return;
      }

      // Get current azimuth
      final azimuth = _sensorService.getCurrentAzimuth();

      // Perform distance measurement
      final distance = await _audioService.measureDistance();

      if (distance < 0) {
        AppLogger.warn('Measurement failed, skipping point');
        return;
      }

      // Convert to Cartesian coordinates (azimuth in degrees)
      final radians = math.pi * azimuth / 180.0;
      final x = distance * math.cos(radians);
      final y = distance * math.sin(radians);

      // Create measurement point
      final measurementPoint = MeasurementPoint(
        x: x,
        y: y,
        distance: distance,
        angle: azimuth,
        signalStrength: 0.8, // TODO: Calculate from correlation peak
        timestamp: DateTime.now(),
      );

      // Create floor plan point
      final floorPlanPoint = FloorPlanPoint.fromMeasurement(measurementPoint);

      // Add to current floor plan
      final updatedFloorPlan = state.currentFloorPlan!.addPoint(floorPlanPoint);

      state = state.copyWith(currentFloorPlan: updatedFloorPlan);

      AppLogger.info(
        'Added measurement point: (${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})',
      );
    } catch (e) {
      AppLogger.error('Failed to add measurement point: $e');
      state = state.copyWith(errorMessage: 'Failed to add measurement point');
    }
  }

  /// Add a reference point (corner, door, etc.) to the current floor plan
  void addReferencePoint(double x, double y, PointType type) {
    try {
      if (!state.isScanning || state.currentFloorPlan == null) {
        AppLogger.warn('Cannot add reference point: not currently scanning');
        return;
      }

      final referencePoint = FloorPlanPoint.reference(x: x, y: y, type: type);

      final updatedFloorPlan = state.currentFloorPlan!.addPoint(referencePoint);
      state = state.copyWith(currentFloorPlan: updatedFloorPlan);

      AppLogger.info(
        'Added reference point: ${type.name} at (${x.toStringAsFixed(2)}, ${y.toStringAsFixed(2)})',
      );
    } catch (e) {
      AppLogger.error('Failed to add reference point: $e');
      state = state.copyWith(errorMessage: 'Failed to add reference point');
    }
  }

  /// Delete a floor plan
  Future<void> deleteFloorPlan(String id) async {
    try {
      final success = await _repository.deleteFloorPlan(id);
      if (success) {
        final updatedFloorPlans = state.floorPlans
            .where((fp) => fp.id != id)
            .toList();
        state = state.copyWith(floorPlans: updatedFloorPlans);
        AppLogger.info('Floor plan deleted: $id');
      }
    } catch (e) {
      AppLogger.error('Failed to delete floor plan: $e');
      state = state.copyWith(errorMessage: 'Failed to delete floor plan');
    }
  }

  /// Load a specific floor plan for viewing/editing
  Future<void> loadFloorPlan(String id) async {
    try {
      final floorPlan = await _repository.getFloorPlanById(id);
      if (floorPlan != null) {
        state = state.copyWith(selectedFloorPlan: floorPlan);
        AppLogger.info('Floor plan loaded: ${floorPlan.name}');
      }
    } catch (e) {
      AppLogger.error('Failed to load floor plan: $e');
      state = state.copyWith(errorMessage: 'Failed to load floor plan');
    }
  }

  /// Clear the selected floor plan
  void clearSelectedFloorPlan() {
    state = state.copyWith(selectedFloorPlan: null);
  }

  /// Cancel current scan without saving
  void cancelScan() {
    state = state.copyWith(
      isScanning: false,
      currentFloorPlan: null,
      errorMessage: null,
    );
    AppLogger.info('Floor plan scan cancelled');
  }

  /// Clear any error message
  void clearError() {
    state = state.copyWith(errorMessage: null);
  }

  String _generateId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}

/// State class for floor plan management
class FloorPlanState {
  final bool isScanning;
  final FloorPlan? currentFloorPlan;
  final FloorPlan? selectedFloorPlan;
  final List<FloorPlan> floorPlans;
  final String? errorMessage;

  const FloorPlanState({
    this.isScanning = false,
    this.currentFloorPlan,
    this.selectedFloorPlan,
    this.floorPlans = const [],
    this.errorMessage,
  });

  FloorPlanState copyWith({
    bool? isScanning,
    FloorPlan? currentFloorPlan,
    FloorPlan? selectedFloorPlan,
    List<FloorPlan>? floorPlans,
    String? errorMessage,
  }) {
    return FloorPlanState(
      isScanning: isScanning ?? this.isScanning,
      currentFloorPlan: currentFloorPlan ?? this.currentFloorPlan,
      selectedFloorPlan: selectedFloorPlan ?? this.selectedFloorPlan,
      floorPlans: floorPlans ?? this.floorPlans,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

// ============================================================================
// RIVERPOD PROVIDERS
// ============================================================================

/// Provider for FloorPlanRepository
final floorPlanRepositoryProvider = Provider<FloorPlanRepository>((ref) {
  final database = ref.watch(databaseProvider);
  return FloorPlanRepository(database);
});

/// Provider for FloorPlanController
final floorPlanControllerProvider =
    StateNotifierProvider<FloorPlanController, FloorPlanState>((ref) {
      final audioService = ref.watch(audioServiceProvider);
      final sensorService = ref.watch(sensorServiceProvider);
      final repository = ref.watch(floorPlanRepositoryProvider);
      return FloorPlanController(audioService, sensorService, repository);
    });
