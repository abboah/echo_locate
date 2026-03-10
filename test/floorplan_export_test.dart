import 'package:flutter_test/flutter_test.dart';
import 'package:echo_locate/services/export/pdf_export_service.dart';
import 'package:echo_locate/shared/models/measurement_point.dart';
import 'package:echo_locate/features/floorplan/domain/floorplan_model.dart';

void main() {
  group('FloorPlan model', () {
    test('FloorPlanPoint.fromMeasurement maps values correctly', () {
      final measurement = MeasurementPoint(
        x: 1.0,
        y: 2.0,
        distance: 2.236,
        angle: 45.0,
        signalStrength: 0.9,
        timestamp: DateTime(2026, 3, 10),
      );

      final point = FloorPlanPoint.fromMeasurement(measurement);

      expect(point.x, equals(1.0));
      expect(point.y, equals(2.0));
      expect(point.distance, equals(2.236));
      expect(point.angle, equals(45.0));
      expect(point.signalStrength, equals(0.9));
      expect(point.measuredAt, equals(measurement.timestamp));
      expect(point.type, equals(PointType.measurement));
    });
  });

  group('PDFExportService', () {
    final exportService = PDFExportService();

    test('exportMeasurementsToPDF returns non-empty bytes', () async {
      final measurements = [
        MeasurementPoint(
          x: 1.0,
          y: 2.0,
          distance: 2.236,
          angle: 45.0,
          signalStrength: 0.9,
          timestamp: DateTime.now(),
        ),
      ];

      final bytes = await exportService.exportMeasurementsToPDF(
        title: 'Test Measurements',
        measurements: measurements,
      );

      expect(bytes, isNotEmpty);
    });

    test('exportFloorPlanToPDF returns non-empty bytes', () async {
      final floorPlan = FloorPlan(
        id: 'test-1',
        name: 'Test Plan',
        description: 'Unit test export',
        points: [
          FloorPlanPoint.fromMeasurement(
            MeasurementPoint(
              x: 0.0,
              y: 0.0,
              distance: 0.0,
              angle: 0.0,
              signalStrength: 1.0,
              timestamp: DateTime.now(),
            ),
          ),
        ],
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        metadata: FloorPlanMetadata(
          totalPoints: 1,
          areaEstimate: 0.0,
          measurementDate: DateTime.now(),
        ),
      );

      final bytes = await exportService.exportFloorPlanToPDF(
        floorPlan: floorPlan,
      );

      expect(bytes, isNotEmpty);
    });
  });
}
