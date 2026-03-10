import 'package:drift/drift.dart';
import 'package:echo_locate/core/database/database.dart' as db;
import 'package:echo_locate/features/floorplan/domain/floorplan_model.dart';
import 'package:echo_locate/core/utils/logger.dart';

/// Repository for managing floor plan data persistence using Drift
class FloorPlanRepository {
  final db.AppDatabase _database;

  FloorPlanRepository(this._database);

  /// Save a floor plan to the database
  Future<String> saveFloorPlan(FloorPlan floorPlan) async {
    try {
      await _database
          .into(_database.floorPlans)
          .insert(
            db.FloorPlansCompanion.insert(
              id: floorPlan.id,
              name: floorPlan.name,
              description: Value(floorPlan.description),
              createdAt: floorPlan.createdAt.millisecondsSinceEpoch,
              updatedAt: floorPlan.updatedAt.millisecondsSinceEpoch,
              totalPoints: floorPlan.metadata.totalPoints,
              areaEstimate: floorPlan.metadata.areaEstimate,
              measurementDate:
                  floorPlan.metadata.measurementDate.millisecondsSinceEpoch,
              scanDuration: Value(
                floorPlan.metadata.scanDuration?.inMilliseconds,
              ),
              deviceInfo: Value(floorPlan.metadata.deviceInfo),
            ),
          );

      // Save all points
      for (final point in floorPlan.points) {
        await _database
            .into(_database.floorPlanPoints)
            .insert(
              db.FloorPlanPointsCompanion.insert(
                id: point.id,
                floorPlanId: floorPlan.id,
                x: point.x,
                y: point.y,
                distance: point.distance != null
                    ? Value(point.distance!)
                    : const Value.absent(),
                angle: point.angle != null
                    ? Value(point.angle!)
                    : const Value.absent(),
                signalStrength: point.signalStrength != null
                    ? Value(point.signalStrength!)
                    : const Value.absent(),
                measuredAt: point.measuredAt.millisecondsSinceEpoch,
                pointType: point.type.name,
              ),
            );
      }

      AppLogger.info(
        'Floor plan saved: ${floorPlan.name} (${floorPlan.points.length} points)',
      );
      return floorPlan.id;
    } catch (e) {
      AppLogger.error('Failed to save floor plan: $e');
      rethrow;
    }
  }

  /// Get all floor plans ordered by creation date (newest first)
  Future<List<FloorPlan>> getAllFloorPlans() async {
    try {
      final floorPlanRows = await (_database.select(
        _database.floorPlans,
      )..orderBy([(t) => OrderingTerm.desc(t.createdAt)])).get();

      final floorPlans = <FloorPlan>[];
      for (final row in floorPlanRows) {
        final points = await _getPointsForFloorPlan(row.id);
        final floorPlan = await _floorPlanFromRow(row, points);
        floorPlans.add(floorPlan);
      }

      AppLogger.info('Retrieved ${floorPlans.length} floor plans');
      return floorPlans;
    } catch (e) {
      AppLogger.error('Failed to get floor plans: $e');
      rethrow;
    }
  }

  /// Get a specific floor plan by ID
  Future<FloorPlan?> getFloorPlanById(String id) async {
    try {
      final floorPlanRow = await (_database.select(
        _database.floorPlans,
      )..where((t) => t.id.equals(id))).getSingleOrNull();

      if (floorPlanRow == null) {
        AppLogger.warn('Floor plan not found: $id');
        return null;
      }

      final points = await _getPointsForFloorPlan(id);
      return await _floorPlanFromRow(floorPlanRow, points);
    } catch (e) {
      AppLogger.error('Failed to get floor plan by ID: $e');
      rethrow;
    }
  }

  /// Delete a floor plan and all its points
  Future<bool> deleteFloorPlan(String id) async {
    try {
      // Points will be deleted automatically due to CASCADE constraint
      final rowsDeleted = await (_database.delete(
        _database.floorPlans,
      )..where((t) => t.id.equals(id))).go();

      final success = rowsDeleted > 0;
      if (success) {
        AppLogger.info('Floor plan deleted: $id');
      } else {
        AppLogger.warn('No floor plan found with ID: $id');
      }
      return success;
    } catch (e) {
      AppLogger.error('Failed to delete floor plan: $e');
      rethrow;
    }
  }

  /// Update an existing floor plan
  Future<void> updateFloorPlan(FloorPlan floorPlan) async {
    try {
      await (_database.update(
        _database.floorPlans,
      )..where((t) => t.id.equals(floorPlan.id))).write(
        db.FloorPlansCompanion(
          name: Value(floorPlan.name),
          description: Value(floorPlan.description),
          updatedAt: Value(floorPlan.updatedAt.millisecondsSinceEpoch),
          totalPoints: Value(floorPlan.metadata.totalPoints),
          areaEstimate: Value(floorPlan.metadata.areaEstimate),
          scanDuration: Value(floorPlan.metadata.scanDuration?.inMilliseconds),
        ),
      );

      // Delete existing points and re-insert
      await (_database.delete(
        _database.floorPlanPoints,
      )..where((t) => t.floorPlanId.equals(floorPlan.id))).go();

      // Re-insert all points
      for (final point in floorPlan.points) {
        await _database
            .into(_database.floorPlanPoints)
            .insert(
              db.FloorPlanPointsCompanion.insert(
                id: point.id,
                floorPlanId: floorPlan.id,
                x: point.x,
                y: point.y,
                distance: point.distance != null
                    ? Value(point.distance!)
                    : const Value.absent(),
                angle: point.angle != null
                    ? Value(point.angle!)
                    : const Value.absent(),
                signalStrength: point.signalStrength != null
                    ? Value(point.signalStrength!)
                    : const Value.absent(),
                measuredAt: point.measuredAt.millisecondsSinceEpoch,
                pointType: point.type.name,
              ),
            );
      }

      AppLogger.info('Floor plan updated: ${floorPlan.name}');
    } catch (e) {
      AppLogger.error('Failed to update floor plan: $e');
      rethrow;
    }
  }

  /// Get floor plans created within a date range
  Future<List<FloorPlan>> getFloorPlansByDateRange(
    DateTime start,
    DateTime end,
  ) async {
    try {
      final floorPlanRows =
          await (_database.select(_database.floorPlans)
                ..where(
                  (t) => t.createdAt.isBetweenValues(
                    start.millisecondsSinceEpoch,
                    end.millisecondsSinceEpoch,
                  ),
                )
                ..orderBy([(t) => OrderingTerm.desc(t.createdAt)]))
              .get();

      final floorPlans = <FloorPlan>[];
      for (final row in floorPlanRows) {
        final points = await _getPointsForFloorPlan(row.id);
        final floorPlan = await _floorPlanFromRow(row, points);
        floorPlans.add(floorPlan);
      }

      AppLogger.info(
        'Retrieved ${floorPlans.length} floor plans between ${start.toIso8601String()} and ${end.toIso8601String()}',
      );
      return floorPlans;
    } catch (e) {
      AppLogger.error('Failed to get floor plans by date range: $e');
      rethrow;
    }
  }

  /// Get the total count of floor plans
  Future<int> getFloorPlanCount() async {
    try {
      final count = _database.floorPlans.id.count();
      final query = _database.selectOnly(_database.floorPlans)
        ..addColumns([count]);
      final result = await query.map((row) => row.read(count)!).getSingle();
      AppLogger.info('Total floor plans: $result');
      return result;
    } catch (e) {
      AppLogger.error('Failed to get floor plan count: $e');
      rethrow;
    }
  }

  /// Helper method to get all points for a floor plan
  Future<List<FloorPlanPoint>> _getPointsForFloorPlan(
    String floorPlanId,
  ) async {
    final pointRows =
        await (_database.select(_database.floorPlanPoints)
              ..where((t) => t.floorPlanId.equals(floorPlanId))
              ..orderBy([(t) => OrderingTerm.asc(t.measuredAt)]))
            .get();

    return pointRows.map<FloorPlanPoint>(_floorPlanPointFromRow).toList();
  }

  /// Convert database row to FloorPlan
  Future<FloorPlan> _floorPlanFromRow(
    db.FloorPlan row,
    List<FloorPlanPoint> points,
  ) async {
    return FloorPlan(
      id: row.id,
      name: row.name,
      description: row.description,
      points: points,
      createdAt: DateTime.fromMillisecondsSinceEpoch(row.createdAt),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(row.updatedAt),
      metadata: FloorPlanMetadata(
        totalPoints: row.totalPoints,
        areaEstimate: row.areaEstimate,
        measurementDate: DateTime.fromMillisecondsSinceEpoch(
          row.measurementDate,
        ),
        scanDuration: row.scanDuration != null
            ? Duration(milliseconds: row.scanDuration!)
            : null,
        deviceInfo: row.deviceInfo,
      ),
    );
  }

  /// Convert database row to FloorPlanPoint
  FloorPlanPoint _floorPlanPointFromRow(db.FloorPlanPoint row) {
    return FloorPlanPoint(
      id: row.id,
      x: row.x,
      y: row.y,
      distance: row.distance,
      angle: row.angle,
      signalStrength: row.signalStrength,
      measuredAt: DateTime.fromMillisecondsSinceEpoch(row.measuredAt),
      type: PointType.values.firstWhere(
        (type) => type.name == row.pointType,
        orElse: () => PointType.measurement,
      ),
    );
  }
}
