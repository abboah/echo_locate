import 'package:echo_locate/core/database/database.dart';
import 'package:echo_locate/shared/models/measurement_point.dart';
import 'package:echo_locate/core/utils/logger.dart';

/// Repository for managing measurement data persistence using Drift
class MeasurementRepository {
  final AppDatabase _database;

  MeasurementRepository(this._database);

  /// Save a measurement to the database
  Future<int> saveMeasurement(MeasurementPoint measurement) async {
    try {
      final id = await _database.insertMeasurement(measurement);
      AppLogger.info('Measurement saved with ID: $id');
      return id;
    } catch (e) {
      AppLogger.error('Failed to save measurement: $e');
      rethrow;
    }
  }

  /// Get all measurements ordered by timestamp (newest first)
  Future<List<MeasurementPoint>> getAllMeasurements() async {
    try {
      final measurements = await _database.getAllMeasurements();
      AppLogger.info('Retrieved ${measurements.length} measurements');
      return measurements;
    } catch (e) {
      AppLogger.error('Failed to get measurements: $e');
      rethrow;
    }
  }

  /// Get measurements within a date range
  Future<List<MeasurementPoint>> getMeasurementsByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    try {
      final measurements = await _database.getMeasurementsByDateRange(
        start,
        end,
      );
      AppLogger.info(
        'Retrieved ${measurements.length} measurements between ${start.toIso8601String()} and ${end.toIso8601String()}',
      );
      return measurements;
    } catch (e) {
      AppLogger.error('Failed to get measurements by date range: $e');
      rethrow;
    }
  }

  /// Delete a measurement by ID
  Future<bool> deleteMeasurement(int id) async {
    try {
      final rowsDeleted = await _database.deleteMeasurement(id);
      final success = rowsDeleted > 0;
      if (success) {
        AppLogger.info('Measurement deleted: ID $id');
      } else {
        AppLogger.warn('No measurement found with ID: $id');
      }
      return success;
    } catch (e) {
      AppLogger.error('Failed to delete measurement: $e');
      rethrow;
    }
  }

  /// Delete all measurements
  Future<int> deleteAllMeasurements() async {
    try {
      final count = await _database.deleteAllMeasurements();
      AppLogger.info('Deleted all measurements: $count items');
      return count;
    } catch (e) {
      AppLogger.error('Failed to delete all measurements: $e');
      rethrow;
    }
  }

  /// Get the total count of measurements
  Future<int> getMeasurementCount() async {
    try {
      final count = await _database.getMeasurementCount();
      AppLogger.info('Total measurements: $count');
      return count;
    } catch (e) {
      AppLogger.error('Failed to get measurement count: $e');
      rethrow;
    }
  }

  /// Get measurements from the last N days
  Future<List<MeasurementPoint>> getRecentMeasurements(int days) async {
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));
    return getMeasurementsByDateRange(start, end);
  }
}
