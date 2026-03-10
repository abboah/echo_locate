# Floor Plan & Export Implementation

## Overview

The EchoLocate app includes comprehensive floor plan creation and PDF export functionality. This allows users to create spatial maps of their environment using acoustic measurements and export professional reports for documentation and sharing.

## Floor Plan Architecture

### Domain Models

#### FloorPlan Class

Represents a complete floor plan with metadata and measurement points:

```dart
class FloorPlan extends Equatable {
  final String id;
  final String name;
  final String? description;
  final List<FloorPlanPoint> points;
  final DateTime createdAt, updatedAt;
  final FloorPlanMetadata metadata;
}
```

**Key Features:**
- **Factory constructor**: `FloorPlan.fromMeasurements()` creates floor plans from measurement collections
- **Point management**: Add points, update metadata automatically
- **Area estimation**: Simple bounding box calculation for space estimation

#### FloorPlanPoint Class

Individual points within a floor plan:

```dart
class FloorPlanPoint extends Equatable {
  final String id;
  final double x, y;  // Cartesian coordinates
  final double? distance, angle;  // Polar measurements
  final double? signalStrength;
  final DateTime measuredAt;
  final PointType type;  // measurement, reference, wall, obstacle
}
```

**Point Types:**
- `measurement`: Standard acoustic distance measurements
- `reference`: Known reference points (corners, doors, landmarks)
- `wall`: Structural boundary points
- `obstacle`: Furniture or other obstacles

#### FloorPlanMetadata Class

Additional floor plan information:

```dart
class FloorPlanMetadata extends Equatable {
  final int totalPoints;
  final double areaEstimate;
  final DateTime measurementDate;
  final Duration? scanDuration;
  final String? deviceInfo;
}
```

### Database Schema

#### Floor Plans Table

```sql
CREATE TABLE floor_plans (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  description TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  total_points INTEGER NOT NULL DEFAULT 0,
  area_estimate REAL NOT NULL DEFAULT 0.0,
  measurement_date INTEGER NOT NULL,
  scan_duration INTEGER,  -- milliseconds
  device_info TEXT
) STRICT;
```

#### Floor Plan Points Table

```sql
CREATE TABLE floor_plan_points (
  id TEXT PRIMARY KEY,
  floor_plan_id TEXT NOT NULL,
  x REAL NOT NULL, y REAL NOT NULL,
  distance REAL, angle REAL,  -- NULL for reference points
  signal_strength REAL,
  measured_at INTEGER NOT NULL,
  point_type TEXT NOT NULL DEFAULT 'measurement',
  FOREIGN KEY (floor_plan_id) REFERENCES floor_plans(id) ON DELETE CASCADE
) STRICT;
```

**Design Decisions:**
- **Cascading deletes**: Removing a floor plan automatically cleans up its points
- **Flexible schema**: Reference points don't require distance/angle data
- **Type safety**: STRICT mode prevents data corruption
- **Indexing**: Optimized queries for floor plan loading and date filtering

## Repository Implementation

### FloorPlanRepository

**Core Operations:**
- `saveFloorPlan()` - Persist complete floor plan with all points
- `getAllFloorPlans()` - Load all floor plans with points
- `getFloorPlanById()` - Retrieve specific floor plan
- `deleteFloorPlan()` - Remove floor plan and cascade to points
- `updateFloorPlan()` - Modify existing floor plan
- `getFloorPlansByDateRange()` - Filter by creation date

**Transaction Safety:**
- All operations use database transactions
- Error handling with comprehensive logging
- Foreign key constraints maintain data integrity

## Controller Logic

### FloorPlanController

**Scanning Workflow:**
1. `startScanning(name, description)` - Initialize new floor plan
2. `addMeasurementPoint()` - Perform acoustic measurement and add point
3. `addReferencePoint(x, y, type)` - Add manual reference points
4. `stopScanning()` - Finalize and save floor plan

**State Management:**
```dart
class FloorPlanState {
  final bool isScanning;
  final FloorPlan? currentFloorPlan;
  final FloorPlan? selectedFloorPlan;
  final List<FloorPlan> floorPlans;
  final String? errorMessage;
}
```

**Key Features:**
- **Real-time updates**: State reflects current scanning progress
- **Error handling**: Comprehensive error states and recovery
- **Persistence integration**: Automatic saving/loading
- **Coordinate conversion**: Polar to Cartesian transformation

## PDF Export System

### PDFExportService

**Export Capabilities:**
- **Measurement reports**: Tabular data with statistics
- **Floor plan documents**: Complete floor plan with metadata
- **Multiple output options**: Print, save to file, share

**Document Structure:**
```
┌─ Header (Title, Generation Info)
├─ Content Section
│  ├─ Metadata Table
│  ├─ Data Visualization
│  └─ Detailed Tables
└─ Footer (Timestamps, App Info)
```

### Measurement PDF Features

- **Data table**: Time, distance, angle, coordinates, signal strength
- **Statistics**: Min/max/average distances, date ranges
- **Professional formatting**: Headers, borders, consistent styling

### Floor Plan PDF Features

- **Plan metadata**: Name, description, creation date, area estimate
- **Point visualization**: Coordinate-based point listings
- **Type differentiation**: Separate sections for measurement vs reference points
- **Complete data table**: All point details in tabular format

## Integration Points

### Measurement Integration

**Automatic Floor Plan Creation:**
```dart
// From measurement controller
final floorPlan = FloorPlan.fromMeasurements(
  name: 'Living Room Scan',
  measurements: measurementHistory,
);
await floorPlanRepository.saveFloorPlan(floorPlan);
```

### Export Integration

**PDF Generation:**
```dart
// Export measurements
final pdfData = await pdfExportService.exportMeasurementsToPDF(
  title: 'Measurement Report',
  measurements: measurementPoints,
);

// Export floor plan
final pdfData = await pdfExportService.exportFloorPlanToPDF(
  floorPlan: selectedFloorPlan,
);
```

## Usage Examples

### Creating a Floor Plan

```dart
// Start scanning
await floorPlanController.startScanning('Office Layout');

// Add measurement points
for (int i = 0; i < 10; i++) {
  await floorPlanController.addMeasurementPoint();
  // User moves to next position
}

// Add reference points
floorPlanController.addReferencePoint(0, 0, PointType.reference); // Corner
floorPlanController.addReferencePoint(5, 0, PointType.wall); // Wall endpoint

// Save floor plan
await floorPlanController.stopScanning();
```

### Exporting Data

```dart
// Export current measurements
final pdfBytes = await pdfExportService.exportMeasurementsToPDF(
  title: 'Distance Measurements',
  measurements: measurementController.state.history,
);

// Save to file
final filePath = await pdfExportService.savePDFToFile(
  pdfBytes,
  'measurements_${DateTime.now().toIso8601String()}.pdf',
);

// Or print directly
await pdfExportService.printPDF(pdfBytes, jobName: 'EchoLocate Report');
```

## Performance Considerations

### Database Optimization

- **Batch operations**: Single transactions for multi-point saves
- **Indexing strategy**: Optimized for common query patterns
- **Lazy loading**: Points loaded only when floor plan is accessed

### PDF Generation

- **Memory efficient**: Stream-based PDF building
- **Scalable tables**: Handles large measurement datasets
- **Async processing**: Non-blocking PDF generation

## Error Handling

### Database Errors

- **Transaction rollback**: Failed operations don't corrupt data
- **Constraint validation**: Prevents invalid floor plan states
- **Recovery strategies**: Graceful degradation with error messages

### Export Errors

- **File system issues**: Fallback to alternative save locations
- **Printing failures**: User notification with retry options
- **Memory constraints**: Chunked processing for large datasets

## Future Enhancements

### Advanced Features

1. **Visual Floor Plans**: SVG/PNG diagram generation
2. **Room Detection**: Automatic room boundary identification
3. **Path Finding**: Navigation assistance within floor plans
4. **Cloud Sync**: Multi-device floor plan sharing
5. **3D Visualization**: Height/depth mapping capabilities

### Export Improvements

1. **Custom Templates**: User-configurable PDF layouts
2. **Image Integration**: Photo attachments to floor plans
3. **Multi-format Export**: CSV, JSON, DXF output options
4. **Batch Processing**: Multiple floor plan exports

## Dependencies

```yaml
dependencies:
  pdf: ^3.11.1          # PDF generation
  printing: ^5.13.1     # Print/share functionality
  path_provider: ^2.1.4 # File system access
```

## File Structure

```
lib/
├── features/floorplan/
│   ├── domain/
│   │   └── floorplan_model.dart        # Domain models
│   ├── data/
│   │   └── floorplan_repository.dart   # Database operations
│   └── presentation/
│       └── floorplan_controller.dart   # State management
├── services/export/
│   └── pdf_export_service.dart         # PDF generation
└── core/database/
    ├── database.drift                  # Schema (floor plans)
    └── database.dart                   # Tables & queries
```

This implementation provides a solid foundation for spatial mapping and professional documentation in the EchoLocate application.