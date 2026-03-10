# Project Status

This document tracks the current state of the **EchoLocate** application. It will be updated regularly to reflect progress through development. The intention is to capture what's implemented, what's pending, and provide a snapshot of the core components for backend development (audio, DSP, persistence, export) while the UI is handled separately.

## 📝 Overview

EchoLocate is a Flutter-based app aimed at measuring distances using audio chirps. The app will play a chirp, record the response, compute time-of-flight via DSP, and allow users to build a floor plan. Core features include:

- Audio signal generation and capture
- Digital signal processing (FFT, correlation, ToF calculation)
- Measurement storage and retrieval
- Floor plan creation and PDF export
- Separation of backend logic from UI (designer provides UI later)

## ✅ Completed Work (as of 2026-03-09)

### Project Setup
- Flutter project scaffolded with Riverpod, GoRouter, and basic logging.
- `main.dart` initializes database and logger.
- Theming and routing infrastructure in place (`AppTheme`, `appRouter`).

### DSP & Math Services
- `fft_service.dart`: FFT and cross-correlation algorithms implemented.
- `tof_calculator.dart`: Time-of-flight calculation logic written.
- `chirp_generator.dart`: Chirp waveform generation.

### Audio Engine ✅ COMPLETED
- Initialize flutter_soloud and add `record` package for microphone capture.
- Implement playback of chirp and recording of response audio.
- Manage lifecycle/disposal of audio resources.
- Full implementation with WAV conversion, error handling, and validation.

### Feature Code
- `measurement_controller.dart`: State management class with example data.
- `measurement_screen.dart`: Screen skeleton using controller (UI placeholders).
- `measurement_repository.dart`: Stub with TODOs for actual database ops.

### Shared Modules
- Basic models, widgets, constants under `shared/` and `core/`.
- Utility logging in `core/utils/logger.dart`.

### Testing
- A single widget test file exists (`test/widget_test.dart`) but no real tests yet.

## ⚠️ Remaining Tasks / TODOs

These items are the current focus for backend work before UI integration:

1. **Measurement Pipeline ✅ COMPLETED**
   - DSP services wired into `MeasurementController` via `AudioService.measureDistance()`.
   - `measureDistance()` emits chirp, records echo, correlates signals, and calculates ToF.
   - Controller now handles azimuth retrieval, state updates, and history.
   - Signal strength placeholder remains (TODO: derive from correlation peak height).
   - Expose real distance values, start/stop logic.

2. **Persistence ✅ COMPLETED**
   - Implemented Drift database with `measurements` table (x, y, distance, angle, signal_strength, timestamp).
   - Created `MeasurementRepository` with full CRUD operations (save, getAll, getByDateRange, delete, deleteAll).
   - Integrated repository into `MeasurementController` for automatic persistence.
   - Added database initialization in `main.dart` with proper provider setup.
   - Measurements are now automatically saved to database and loaded on app start.
   - Clear history now deletes from both memory and database.

3. **Floor Plan & Export ✅ COMPLETED**
   - Enhanced floor plan models with comprehensive `FloorPlan` and `FloorPlanPoint` classes.
   - Added point types (measurement, reference, wall, obstacle) and metadata tracking.
   - Implemented `FloorPlanRepository` with full CRUD operations using Drift database.
   - Created `floor_plans` and `floor_plan_points` tables with proper relationships.
   - Built `FloorPlanController` with scanning logic, point management, and persistence.
   - Implemented complete `PDFExportService` with measurement and floor plan PDF generation.
   - Added PDF printing, saving, and sharing capabilities using `pdf` and `printing` packages.
   - Integrated floor plan creation from measurement collections with automatic area estimation.

4. **Tests**
   - Add unit tests for DSP functions, controllers, repositories.
   - Test audio service stubs when implementation is available.

5. **Miscellaneous**
   - Clean up TODO comments as tasks are completed.
   - Maintain database initialization and migrations.

> **Note:** UI/UX work is **not** being done yet — designers are working on Figma. Backend should be ready to plug in once designs are available.

## 📌 How to Update This File

- After completing significant features or closing TODOs, add an entry to the "Completed Work" section with a date stamp.
- Move items from "Remaining Tasks" to "Completed Work" as they are finished.
- Update overview if the project scope changes.
- This document should serve both developers and presenters to understand progress at a glance.

---

_Last updated: 2026‑03‑09_
