# EchoLocate Expansion: Computer Vision + AI Quality Scoring

**Objective:** Enhance floor-plan accuracy and usability by adding vision-based wall suggestion and AI-driven measurement quality filtering.

**Timeline:** 4 weeks (2 devs working in parallel)  
**Target:** Submission-ready proof-of-concept with measurable improvement metrics.

---

## High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    EchoLocate Enhanced                       │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  Audio Engine (Existing)  →  ToF Distance  ──┐               │
│       ↓                                       │               │
│ Sensor Fusion (Existing) → 2D Points  ──────┤→ Floor Plan    │
│       ↓                                       │   Aggregator  │
│ Camera Feed (NEW) → CV Wall Hints ─────┐    │               │
│       ↓                                 │    │               │
│ Measurement Quality (NEW) ← AI Scoring ┘    │               │
│                                          ──→┤               │
│                                              ↓               │
│                           Enhanced 2D Floor Map + Confidence │
└─────────────────────────────────────────────────────────────┘
```

---

## Module 1: Computer Vision – Wall Detection & Edge Suggestions

### Purpose
Use camera frames to detect corners/edges and suggest wall line locations, reducing manual point placement effort and improving map consistency.

### Scope
- Capture live camera frames while user scans (already have camera permission in Android)
- Detect straight edges and corners using Canny edge detection + Hough line transform
- Project detected lines onto the 2D floor-plan canvas as "wall suggestions"
- User can accept/reject suggestions with a single tap

### Tech Stack
- **Package:** `opencv_flutter` (or `image` + custom Canny) or `google_mlkit_object_detection` for simpler edge inference
- **Recommendation:** Use `image` package (lightweight, no native bridge complexity) with simple edge filter for MVP

### Integration Points
```dart
// New service: lib/services/vision/wall_detector.dart
class WallDetector {
  Future<List<WallSuggestion>> detectWallsFromFrame(Uint8List imageBytes) async {
    // 1. Convert to grayscale
    // 2. Apply Canny edge detection
    // 3. Apply Hough line transform
    // 4. Convert image coordinates to floor-plan 2D space (reverse of camera calibration)
    // 5. Return line segments with confidence scores
  }
}

// Modify: lib/features/floorplan/presentation/floorplan_controller.dart
// Add: Future<void> suggestWallsFromCamera() { ... }

// Modify: lib/shared/widgets/floor_plan_painter.dart
// Add: overlay rendering for semi-transparent wall suggestions
```

### Acceptance Criteria
- ✓ Detects 3+ edge lines from a typical room corner in <500ms
- ✓ Overlay renders on floor plan with 80%+ visual accuracy
- ✓ User can toggle suggestions on/off
- ✓ No app crash on poor lighting or blurry frames

### Dev Responsibility
**Dev A (Primary)**

---

## Module 2: AI Measurement Quality Scoring

### Purpose
Classify each acoustic measurement as `good/uncertain/noisy` based on signal features (SNR, correlation peak height, ambient noise level). Better measurements get higher weight; noisy ones are auto-filtered or flagged.

### Scope
- Compute signal-to-noise ratio (SNR) from recorded echo
- Extract correlation peak height as confidence metric
- Apply simple rules-based or lightweight ML model to score quality
- Display confidence indicator on floor plan (color, opacity, badge)
- Optionally auto-reject measurements below confidence threshold

### Tech Stack
- **Rule-based (fast, interpretable):**  
  `quality_score = 0.3 * snr_norm + 0.5 * peak_height_norm + 0.2 * ambient_noise_inv`
- **Lightweight ML (if going fancier):**  
  TensorFlow Lite on-device model (~1MB) trained on synthetic/lab data
- **Recommendation for MVP:** Rule-based is faster to integrate and easier to debug

### Integration Points
```dart
// New service: lib/services/dsp/quality_scorer.dart
class MeasurementQualityScorer {
  double scoreQuality({
    required List<double> correlation,
    required double snr,
    required double ambientNoiseLevel,
  }) {
    // Returns 0.0 (bad) to 1.0 (excellent)
  }
}

// Modify: lib/services/audio/audio_service.dart
// After ToF calculation, add quality score:
final quality = qualityScorer.scoreQuality(...);
return MeasurementResult(distance, quality);

// Modify: lib/features/floorplan/domain/floorplan_model.dart
class FloorPlanPoint {
  // Add field:
  final double? qualityScore; // 0.0–1.0
}

// Modify: lib/shared/widgets/floor_plan_painter.dart
// Color/opacity of points based on quality score
```

### Acceptance Criteria
- ✓ Scores computed in real-time (<100ms overhead per measurement)
- ✓ High-quality measurements (lab distance) score >0.8
- ✓ Noisy measurements (echoes, reflections) score <0.5
- ✓ Visual feedback to user (color gradient or badge)
- ✓ Optional threshold: measurements below 0.4 are rejected with user notification

### Dev Responsibility
**Dev B (Primary)**

---

## Module 3: AR Overlay (OPTIONAL – Lower Priority)

### Scope (if time permits after Modules 1 & 2)
- Render floor plan as semi-transparent overlay on live camera feed
- User can verify floor-plan accuracy by walking through the space visually
- **Risk:** Requires camera calibration (intrinsic parameters), coordinate frame alignment

### Tech Stack
- `arcore_flutter_plugin` (Google's ARCore for Android)
- Manual camera calibration data (3–5 test images, compute focal length/distortion)

### Verdict
- **Worth it:** Only if Modules 1 & 2 are done by Week 3
- **Otherwise:** Defer to future work (mention in final report as natural progression)

---

## 4-Week Execution Plan

### Week 1: Setup & Core Implementation (Parallel)
**Dev A (Vision):**
- [ ] Set up camera frame capture service
- [ ] Implement basic Canny edge detection using `image` package
- [ ] Prototype wall line extraction (Hough lines)
- [ ] Unit test on 3 sample room images

**Dev B (AI/Quality):**
- [ ] Extract SNR and correlation peak metrics from existing audio pipeline
- [ ] Design quality scoring formula and tune weights on lab test data
- [ ] Unit test scorer against synthetic good/bad measurements
- [ ] Create test dataset: 20 high-confidence, 20 noisy samples

**Joint:** Sync on coordinate system alignment (camera frame ↔ floor-plan space).

### Week 2: Integration & Polish (Parallel)
**Dev A (Vision):**
- [ ] Integrate wall detector into FloorPlanController
- [ ] Add UI: toggle button "Show Wall Suggestions"
- [ ] Render suggestions on floor-plan canvas with semi-transparent overlay
- [ ] Test on 5+ real room corners (phone camera)
- [ ] Fix any latency/crash issues

**Dev B (AI/Quality):**
- [ ] Wire quality scorer into AudioService.measureDistance()
- [ ] Update FloorPlanPoint model to include qualityScore
- [ ] Render quality as point color/opacity in floor-plan painter
- [ ] Add user-visible confidence badge or threshold rejection logic
- [ ] A/B test on benchmark dataset: accuracy before/after filtering

**Joint:** Merge branches, test integrated flow (vision + quality) end-to-end.

### Week 3: Benchmarking & Evaluation (Parallel)
**Dev A (Vision):**
- [ ] Run controlled test in 3 rooms (small, medium, large)
- [ ] Compare accuracy: suggestions-only vs. manual vs. acoustic-only
- [ ] Generate 5–10 before/after floor-plan visualizations
- [ ] Document turnaround time: camera capture → suggestion renderin g

**Dev B (AI/Quality):**
- [ ] Benchmark quality scorer on 100+ measurements from 3 environments
- [ ] Measure: false negatives (good measurements rejected), false positives (bad measurements accepted)
- [ ] Generate ROC-style analysis or confusion matrix table
- [ ] Optimal threshold tuning based on results

**Joint:** Synthesize results; prepare accuracy comparison report.

### Week 4: Report & Polish (Joint)
- [ ] Update PROJECT_STATUS.md with completed features
- [ ] Write "Expansion Results" section for final report (2–3 pages)
- [ ] Create demo script and UI walkthrough video (5–10 min)
- [ ] Final regression: no crashes, all TODOs in code are resolved
- [ ] Code review and cleanup (comments, naming, structure)

---

## Success Metrics

| Metric | Target | How to Measure |
|---|---|---|
| Wall suggestion accuracy | >80% of suggestions match actual walls | Manual inspection of output overlays |
| Quality score discrimination | 90%+ AUC for good vs. noisy measurements | ROC curve on test dataset |
| Performance overhead | <200ms total per scan cycle | Profiling logs + user timing trials |
| User experience | <3 taps to place a wall via suggestions | User flow walkthrough |

---

## Risk Mitigation

| Risk | Likelihood | Mitigation |
|---|---|---|
| Camera frame processing too slow | Medium | Use downsampled frames (480p); profile early |
| Quality scorer overfits to lab data | High | Test on diverse indoor environments in Week 2 |
| AR integration scope creep | High | **Decision point Week 2:** if vision + quality not solid, skip AR |
| Coordinate frame misalignment | Medium | Establish camera ↔ floor-plan calibration in Week 1 |

---

## Deliverables

At project end, you'll have:

1. **Vision Module**  
   - `WallDetector` service with unit tests
   - Visual "wall suggestions" overlay on floor plan
   - Benchmark report: detection accuracy, latency

2. **Quality Scoring Module**  
   - `MeasurementQualityScorer` service with tuned thresholds
   - Quality badges/colors on floor-plan points
   - Accuracy comparison: baseline vs. quality-filtered measurements

3. **Enhanced Floor Plan**  
   - Visual representation blending acoustic data + vision suggestion + quality score
   - Export PDF includes quality metadata

4. **Academic Value**  
   - Multi-modal sensor fusion (audio → vision → ML filtering)
   - Quantified improvement metrics for final report
   - Clear limitations and future work (AR, stronger ML models, etc.)

---

## Questions to Resolve Before Starting

1. **Priority conflict resolution:** If wall suggestion contradicts acoustic measurement, which wins (always user)?
2. **Quality threshold:** Default to accept/reject/flag measurements below confidence threshold?
3. **Camera usage:** Continuous capture during scanning (battery/heat) or on-demand (slower)?
4. **AR scope:** Hard yes/no now, or optional Week 4 if time?

---

**Next Step:** Discuss this with Dev A & B; confirm priorities and finalize questions above.
