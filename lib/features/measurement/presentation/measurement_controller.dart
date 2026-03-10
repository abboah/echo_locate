import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:echo_locate/core/utils/logger.dart';
import 'package:echo_locate/core/database/database_providers.dart';
import 'package:echo_locate/services/audio/audio_service.dart';
import 'package:echo_locate/services/sensor/sensor_service.dart';
import 'package:echo_locate/features/measurement/data/measurement_repository.dart';
import 'package:echo_locate/shared/models/measurement_point.dart';

/// State class for measurement
///
/// Represents the current state of a distance measurement operation
class MeasurementState {
  final double?
  distance; // Measured distance in meters, or null if not measured
  final double? azimuth; // Device compass heading in degrees
  final bool isMeasuring; // true while measurement is in progress
  final String? errorMessage; // Error message if measurement failed
  final List<MeasurementPoint> history; // History of past measurements

  const MeasurementState({
    this.distance,
    this.azimuth,
    this.isMeasuring = false,
    this.errorMessage,
    this.history = const [],
  });

  /// Create a new MeasurementState with updated fields
  MeasurementState copyWith({
    double? distance,
    double? azimuth,
    bool? isMeasuring,
    String? errorMessage,
    List<MeasurementPoint>? history,
  }) {
    return MeasurementState(
      distance: distance ?? this.distance,
      azimuth: azimuth ?? this.azimuth,
      isMeasuring: isMeasuring ?? this.isMeasuring,
      errorMessage: errorMessage ?? this.errorMessage,
      history: history ?? this.history,
    );
  }
}

/// Controller for managing measurement state using Riverpod
///
/// Orchestrates the measurement pipeline:
/// 1. Triggers audio emission and recording
/// 2. Retrieves current sensor orientation
/// 3. Stores measurement results and history
/// 4. Handles errors and state updates
class MeasurementController extends StateNotifier<MeasurementState> {
  final AudioService _audioService;
  final SensorService _sensorService;
  final MeasurementRepository _repository;

  MeasurementController(
    this._audioService,
    this._sensorService,
    this._repository,
  ) : super(const MeasurementState()) {
    // Load existing measurements on initialization
    _loadMeasurements();
  }

  /// Load measurements from database on initialization
  Future<void> _loadMeasurements() async {
    try {
      final measurements = await _repository.getAllMeasurements();
      state = state.copyWith(history: measurements);
      AppLogger.info(
        'Loaded ${measurements.length} measurements from database',
      );
    } catch (e) {
      AppLogger.error('Failed to load measurements: $e');
    }
  }

  /// Perform a single distance measurement
  ///
  /// Steps:
  /// 1. Set isMeasuring = true
  /// 2. Get current azimuth from SensorService
  /// 3. Call AudioService.measureDistance()
  /// 4. Create a MeasurementPoint(distance, azimuth, timestamp: DateTime.now())
  /// 5. Update state with result and add to history
  /// 6. Set isMeasuring = false
  /// 7. Handle errors → set errorMessage in state
  Future<void> takeMeasurement() async {
    try {
      AppLogger.info('Starting measurement');

      // Set isMeasuring = true
      // Indicate that a measurement operation is in progress
      state = state.copyWith(isMeasuring: true, errorMessage: null);

      // Get current azimuth from SensorService
      // Retrieve the device's compass heading at measurement time
      final azimuth = _sensorService.getCurrentAzimuth();
      AppLogger.info('Current azimuth: ${azimuth.toStringAsFixed(1)}°');

      // Call AudioService.measureDistance()
      // This performs the core acoustic measurement: emit chirp and capture echo
      final distance = await _audioService.measureDistance();
      AppLogger.info('Measurement result: ${distance.toStringAsFixed(2)}m');

      // Check if measurement was successful
      if (distance < 0) {
        AppLogger.warn('Measurement failed: invalid distance');
        state = state.copyWith(
          isMeasuring: false,
          errorMessage: 'Failed to detect echo signal',
        );
        return;
      }

      // Create a MeasurementPoint(distance, azimuth, timestamp: DateTime.now())
      // This encapsulates the measurement with metadata
      final measurementPoint = MeasurementPoint.fromPolar(
        distance: distance,
        angle: azimuth,
        signalStrength: 0.8, // TODO: Calculate from correlation peak
      );

      // Update state with result and add to history
      // Store both the latest measurement and the history of all measurements
      final updatedHistory = [...state.history, measurementPoint];
      state = state.copyWith(
        distance: distance,
        azimuth: azimuth,
        isMeasuring: false,
        history: updatedHistory,
        errorMessage: null,
      );

      // Save measurement to database
      await _repository.saveMeasurement(measurementPoint);

      AppLogger.info(
        'Measurement saved to history (total: ${updatedHistory.length})',
      );
    } catch (e) {
      AppLogger.error('Error during measurement: $e');

      // Set isMeasuring = false and errorMessage in state
      state = state.copyWith(
        isMeasuring: false,
        errorMessage: 'Measurement error: $e',
      );
    }
  }

  /// Clear measurement history
  Future<void> clearHistory() async {
    try {
      await _repository.deleteAllMeasurements();
      state = state.copyWith(history: []);
      AppLogger.info('Measurement history cleared');
    } catch (e) {
      AppLogger.error('Failed to clear measurement history: $e');
    }
  }

  /// Reset current measurement
  void resetMeasurement() {
    state = state.copyWith(distance: null, azimuth: null, errorMessage: null);
    AppLogger.info('Current measurement reset');
  }
}

// ============================================================================
// RIVERPOD PROVIDERS
// ============================================================================

/// Provider for AudioService singleton
final audioServiceProvider = Provider<AudioService>((ref) {
  return AudioService();
});

/// Provider for SensorService singleton
final sensorServiceProvider = Provider<SensorService>((ref) {
  return SensorService();
});

/// Provider for MeasurementRepository
final measurementRepositoryProvider = Provider<MeasurementRepository>((ref) {
  final database = ref.watch(databaseProvider);
  return MeasurementRepository(database);
});

/// Provider for MeasurementController with Riverpod
/// Injects AudioService, SensorService, and MeasurementRepository via constructor
final measurementControllerProvider =
    StateNotifierProvider<MeasurementController, MeasurementState>((ref) {
      final audioService = ref.watch(audioServiceProvider);
      final sensorService = ref.watch(sensorServiceProvider);
      final repository = ref.watch(measurementRepositoryProvider);
      return MeasurementController(audioService, sensorService, repository);
    });
