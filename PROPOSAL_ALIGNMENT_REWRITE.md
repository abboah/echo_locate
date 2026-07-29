# EchoLocate Proposal Alignment Rewrite (Assessment-Safe)

This document rewrites your proposal sections to align with the current implementation and reduce over-claim risk during assessment.

## 1) Revised Project Positioning (Use this in title/abstract/introduction)

**Recommended framing:**
EchoLocate is a **software-defined, local-first prototype** that investigates whether commodity smartphone audio hardware can support **assisted indoor distance measurement and 2D spatial point mapping** using FMCW chirps, cross-correlation, and sensor-based orientation.

**Do not frame as:**
- fully automatic room reconstruction,
- guaranteed high-precision architectural mapping,
- deployable navigation-grade assistive product.

---

## 2) Revised Sections (Drop-in text)

## INTRODUCTION AND BACKGROUND (Revised)
The rapid proliferation of smartphone compute power and embedded sensors has enabled new forms of environmental sensing without specialized hardware. EchoLocate explores this opportunity by implementing an active acoustic sensing prototype using only a phone’s speaker and microphone. By emitting Frequency Modulated Continuous Wave (FMCW) chirps and analyzing reflected echoes through cross-correlation and Time-of-Flight (ToF) estimation, the system estimates distance and maps sampled points in a 2D coordinate space. This project sits at the intersection of Digital Signal Processing (DSP), mobile sensing, and Flutter application engineering, with emphasis on feasibility, limitations, and practical trade-offs under real indoor conditions.

## PROBLEM STATEMENT (Revised)
Indoor measurement tools are either low-cost but error-prone (manual tape methods) or accurate but expensive (laser meters and LiDAR-enabled devices). This creates a practical accessibility gap for students, DIY users, and small-scale professionals. There is a need for a low-cost, privacy-preserving approach that can provide useful indoor distance estimates and assistive spatial awareness without additional hardware.

## AIM OF THE PROJECT (Revised)
To design and evaluate EchoLocate, a Flutter-based, software-defined acoustic sensing prototype that performs indoor distance estimation and assisted 2D spatial mapping on commodity smartphones, without relying on LiDAR or dedicated laser hardware.

## SPECIFIC OBJECTIVES (Revised)
- Implement FMCW chirp generation in the 16–20 kHz band and validate waveform consistency.
- Implement a Dart DSP pipeline (FFT + cross-correlation + ToF estimation) for distance inference.
- Integrate orientation sensing (accelerometer/magnetometer) to map sequential measurements into a 2D coordinate frame.
- Build a prototype visualization workflow for radar/point-map floor-plan assistance.
- Implement local-first persistence and report export (PDF) for offline operation and privacy.
- Evaluate measurement error under controlled indoor scenarios and compare against baseline tools (tape/laser meter), targeting ±5% as a **benchmark objective**, not a guaranteed outcome.

## PROJECT SCOPE (Revised)
### In Scope
- Acoustic chirp emission and echo capture on Android.
- On-device DSP for ToF-based distance estimation.
- Sensor-assisted 2D point plotting from sequential measurements.
- Local-first data storage and PDF report export.
- Prototype-level usability features and basic reliability testing.

### Out of Scope
- Fully automatic semantic room understanding (e.g., automatic wall/object classification).
- 3D reconstruction or volumetric modeling.
- Outdoor robustness guarantees.
- Cloud sync and multi-device collaboration.
- CAD-grade geometric fidelity and direct AutoCAD export.

## JUSTIFICATION (Revised)
EchoLocate is justified as a feasibility-driven, low-cost alternative to hardware-dependent indoor measurement workflows. Its local-first architecture minimizes privacy risk for sensitive indoor layout data and avoids cloud dependency. The project’s technical contribution lies in demonstrating an end-to-end mobile DSP and sensing pipeline while explicitly quantifying its performance boundaries.

## METHODOLOGY (Revised emphasis)
Use iterative development with weekly validation loops:
1. Signal generation validation,
2. DSP pipeline validation,
3. sensor-fusion integration,
4. prototype UI integration,
5. controlled benchmarking and error analysis.

Each phase should include measurable acceptance criteria and a documented limitations log.

---

## 3) Critical Proposal Corrections (Line-by-line intent)

Use these replacements to avoid examiner pushback:

1. Replace **"high-precision indoor spatial mapping"** with **"prototype indoor distance estimation and assisted 2D spatial mapping"**.
2. Replace **"will deliver ±5%"** with **"targets ±5% under controlled indoor conditions"**.
3. Replace **"feature-complete deployable product"** with **"research prototype with validated core pipeline"**.
4. Replace **"Isar NoSQL database"** with **"Drift local database"** (to match current implementation).
5. Replace **"tool for visually impaired navigation"** with **"exploratory assistive spatial-awareness prototype"** unless accessibility features are fully implemented and tested.
6. Replace **"generate comprehensive 2D floor plans"** with **"generate 2D point-based floor-plan approximations"**.

---

## 4) Viva Defense Script (Short)

If asked "Is this production-ready?"
> No. This is a validated CS prototype. The contribution is a complete on-device acoustic sensing pipeline and quantified performance under controlled indoor environments.

If asked "Does it automatically detect all walls/objects?"
> Not currently. The system performs assisted point mapping from acoustic distance plus orientation data. Automatic semantic reconstruction is future work.

If asked "Why is this still strong academically?"
> It integrates DSP theory, mobile sensing, algorithm implementation, system design, and empirical evaluation with clear limitations and reproducible outputs.

---

## 5) Suggested Deliverable Language (Final report)

- **Delivered:** chirp generation, ToF pipeline, sensor-assisted point mapping, local persistence, PDF export.
- **Partially delivered:** floor-plan interaction polish, accessibility suite breadth, multi-environment benchmarking depth.
- **Future work:** robust multipath handling, semantic wall extraction, stronger calibration strategy, richer UX workflows.
