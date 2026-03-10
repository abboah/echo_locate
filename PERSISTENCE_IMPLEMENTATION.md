# Persistence Layer Implementation

## Overview

The EchoLocate app uses **Drift** (formerly Moor) as its persistence layer for storing measurement data locally on the device. This document details the database schema, repository implementation, and integration with the measurement controller.

## Database Schema

### Measurements Table

```sql
CREATE TABLE measurements (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  x REAL NOT NULL, -- X coordinate in meters
  y REAL NOT NULL, -- Y coordinate in meters
  distance REAL NOT NULL, -- Distance in meters
  angle REAL NOT NULL, -- Angle in degrees
  signal_strength REAL NOT NULL, -- Signal strength (0.0 to 1.0)
  timestamp INTEGER NOT NULL -- Timestamp as milliseconds since epoch
) STRICT;

CREATE INDEX idx_measurements_timestamp ON measurements(timestamp);
```

**Key Design Decisions:**

- **STRICT mode**: Ensures type safety and prevents accidental NULL insertions
- **Auto-incrementing ID**: Provides unique identifiers for each measurement
- **Timestamp indexing**: Optimizes date range queries for measurement history
- **Cartesian coordinates**: Stores computed x,y positions for floor plan visualization
- **Signal strength**: Preserves correlation quality metrics for future analysis

## Architecture

### Database Layer (`core/database/`)

1. **`database.drift`** - SQL schema definition
2. **`database.dart`** - AppDatabase class with query methods
3. **`database.g.dart`** - Auto-generated code (via build_runner)
4. **`database_providers.dart`** - Riverpod provider definitions

### Repository Layer (`features/measurement/data/`)

- **`MeasurementRepository`** - Business logic wrapper around database operations
- Abstracts raw SQL queries into domain-specific methods
- Handles error logging and data transformation

### Controller Integration (`features/measurement/presentation/`)

- **`MeasurementController`** - Loads measurements on initialization
- Automatically saves new measurements to database
- Synchronizes in-memory state with persistent storage

## Key Components

### AppDatabase Class

```dart
@DriftDatabase(tables: [Measurements])
class AppDatabase extends _$AppDatabase {
  // Auto-generated query methods
  Future<int> insertMeasurement(MeasurementPoint point);
  Future<List<MeasurementPoint>> getAllMeasurements();
  Future<List<MeasurementPoint>> getMeasurementsByDateRange(DateTime start, DateTime end);
  Future<int> deleteMeasurement(int id);
  Future<int> deleteAllMeasurements();
  Future<int> getMeasurementCount();
}
```

### MeasurementRepository

**Core Methods:**
- `saveMeasurement()` - Persists a new measurement
- `getAllMeasurements()` - Retrieves complete measurement history
- `getMeasurementsByDateRange()` - Filters measurements by date
- `deleteMeasurement()` - Removes specific measurement by ID
- `deleteAllMeasurements()` - Clears entire measurement history
- `getMeasurementCount()` - Returns total number of stored measurements

**Error Handling:**
- All methods include try/catch blocks
- Errors are logged via AppLogger
- Exceptions are re-thrown for controller-level handling

### Controller Integration

**Automatic Persistence:**
```dart
// In takeMeasurement()
final measurementPoint = MeasurementPoint.fromPolar(...);
await _repository.saveMeasurement(measurementPoint); // Auto-save
```

**Initialization Loading:**
```dart
MeasurementController(...) {
  _loadMeasurements(); // Load from DB on startup
}
```

**History Management:**
```dart
Future<void> clearHistory() async {
  await _repository.deleteAllMeasurements(); // Clear DB
  state = state.copyWith(history: []); // Clear memory
}
```

## Data Flow

### Saving a Measurement

1. User triggers measurement via UI
2. `MeasurementController.takeMeasurement()` executes
3. Audio service performs acoustic ranging
4. Controller creates `MeasurementPoint` with results
5. **Repository saves to database**
6. Controller updates in-memory state
7. UI reflects new measurement

### Loading Measurements

1. App starts → `main.dart` initializes database
2. `MeasurementController` constructor calls `_loadMeasurements()`
3. **Repository fetches all measurements from database**
4. Controller populates state.history
5. UI displays persisted measurement history

## Performance Considerations

### Indexing Strategy

- **Timestamp index** enables O(log n) date range queries
- Primary key index on `id` for fast individual lookups
- No additional indexes to minimize storage overhead

### Query Optimization

- `getAllMeasurements()` uses `ORDER BY timestamp DESC` for chronological display
- Date range queries leverage the timestamp index
- Batch operations (deleteAll) use single transactions

### Memory Management

- Measurements loaded once on app start
- In-memory state kept in sync with database
- No lazy loading (small dataset expected)

## Migration Strategy

### Schema Evolution

Current schema version: **1**

When adding new fields or tables:
1. Update `database.drift` schema
2. Increment `schemaVersion` in `AppDatabase`
3. Add migration logic if needed
4. Run `flutter pub run build_runner build`
5. Test migration on existing data

### Data Preservation

- Upgrades maintain existing measurement data
- Downgrades would require export/import workflow
- No destructive migrations planned

## Testing Strategy

### Unit Tests

- **Repository tests**: Mock database, test CRUD operations
- **Controller tests**: Verify persistence integration
- **Database tests**: Test schema constraints and queries

### Integration Tests

- **End-to-end persistence**: Create → Save → Load → Verify
- **Migration tests**: Test schema upgrades with existing data
- **Performance tests**: Measure query times with large datasets

## Future Enhancements

### Potential Improvements

1. **Bulk Operations**: Batch insert multiple measurements
2. **Advanced Queries**: Filter by distance ranges, signal quality
3. **Data Export**: JSON/CSV export for external analysis
4. **Compression**: Compress large measurement histories
5. **Cloud Sync**: Optional synchronization with remote storage

### Schema Extensions

```sql
-- Future additions
ALTER TABLE measurements ADD COLUMN device_id TEXT;
ALTER TABLE measurements ADD COLUMN measurement_mode TEXT; -- 'single', 'continuous'
ALTER TABLE measurements ADD COLUMN environmental_data TEXT; -- JSON temperature/humidity
```

## Error Handling

### Database Errors

- **Connection failures**: Logged, app continues with in-memory state
- **Constraint violations**: Validation prevents invalid data insertion
- **Disk space issues**: Graceful degradation, user notification
- **Corruption**: Backup/restore mechanisms (future feature)

### Recovery Strategies

- **Failed saves**: Retry with exponential backoff
- **Load failures**: Fallback to empty state, attempt recovery on next launch
- **Migration errors**: Rollback to previous schema version

## Dependencies

```yaml
dependencies:
  drift: ^2.32.0
  sqlite3_flutter_libs: ^0.5.32
  path_provider: ^2.1.4
  path: ^1.9.0

dev_dependencies:
  drift_dev: ^2.32.0
  build_runner: ^2.4.12
```

## File Structure

```
lib/
├── core/database/
│   ├── database.drift          # Schema definition
│   ├── database.dart           # Database class
│   ├── database.g.dart         # Generated code
│   └── database_providers.dart # Riverpod providers
├── features/measurement/
│   ├── data/
│   │   └── measurement_repository.dart # Repository implementation
│   └── presentation/
│       └── measurement_controller.dart # Controller with persistence
└── main.dart                   # Database initialization
```

## Usage Examples

### Basic CRUD Operations

```dart
// Save measurement
await repository.saveMeasurement(measurementPoint);

// Load all measurements
final measurements = await repository.getAllMeasurements();

// Delete specific measurement
await repository.deleteMeasurement(measurementId);

// Clear all data
await repository.deleteAllMeasurements();
```

### Date Range Queries

```dart
final start = DateTime.now().subtract(Duration(days: 7));
final end = DateTime.now();
final recent = await repository.getMeasurementsByDateRange(start, end);
```

This persistence layer provides robust, type-safe storage for EchoLocate measurements with room for future enhancements as the app evolves.