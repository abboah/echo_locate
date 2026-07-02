# EchoLocate v2 — Build Plan (Rebuild · Bloc · Hive)

A clean rebuild of EchoLocate as a cross-platform Flutter app for crowdsourced indoor mapping + navigation. Computer vision (ARCore) is the primary sensing layer; the **acoustic sonar is kept as a standalone feature** and also feeds room classification. State management: **Bloc**. Local persistence: **Hive**. Cloud: **Supabase**.

> Supersedes the earlier build plan. This is the "rebuild fresh, keep the sound" version.

---

## 0. Strategy

Fresh Flutter project. Port the genuinely good parts of the old code (the DSP engine is well-written) into a new, clean structure built around Bloc + Hive.

**Sound is a first-class feature, not just a fallback.** It plays two roles:
1. **Sonar feature** — single-shot distance measurement + radar view (the original idea, kept as one feature of the app).
2. **Room classification + fallback** — the same DSP pipeline feeds a room-type classifier and a backup distance when vision fails.

This means you finish the acoustic I/O (mic + playback) anyway, and it pays off twice.

**Port from old repo:** the DSP service (chirp generator, FFT cross-correlation, ToF, parabolic interpolation) — it's clean and decoupled. Rewrite everything else fresh under the new architecture.

---

## 1. The make-or-break: ARCore depth (do this first)

- **ARCore is Android-only; iOS uses ARKit.** Put depth sensing behind a shared Dart interface; implement Android (ARCore) first.
- Depth access needs a **custom platform channel** with native Kotlin — the Flutter ARCore plugins won't be enough.
- **Build scanning Android-first.** The consumption side (sonar, browse, navigate, accessibility) is plain Flutter and runs on both platforms immediately.

> **Spike M0 before anything else:** a throwaway Kotlin module that runs ARCore, grabs a depth frame + pose, and prints the numbers on a Flutter screen. If it works, proceed. If not, fall back to ML Kit segmentation + manual corner-tapping for the floor plan.

---

## 2. Locked stack

| Layer | Choice |
|---|---|
| Framework | Flutter (Dart) |
| State management | **Bloc** (flutter_bloc) |
| DI | get_it |
| Routing | go_router |
| Local persistence | **hive_ce** (Hive Community Edition) + hive_ce_generator |
| Cloud / crowdsource | Supabase (Postgres + Storage + Auth) |
| Depth sensing | ARCore Depth API (Android, platform channel); ARKit later for iOS |
| On-device vision | Google ML Kit (object detection + text recognition) |
| DSP | fftea (port existing chirp + cross-correlation) |
| Audio | flutter_soloud (playback) + **record** (mic capture — was missing before) |
| Acoustic classifier | TensorFlow Lite |
| Sensors | sensors_plus |
| Voice | flutter_tts + speech_to_text |
| Routing engine | custom A* (Dart) |
| 3D preview | flutter_gl |
| Export | pdf + printing |

> **Don't repeat the old bug:** the old repo declared one DB but referenced another in comments. Commit to **hive_ce** everywhere — models, boxes, comments.

---

## 3. Architecture (feature-first + Bloc + services)

```
lib/
  core/            theme, design tokens, router, di (get_it), constants
  data/
    local/         Hive boxes, type adapters, local data sources
    remote/        Supabase client, remote data sources
    models/        Hive-annotated: Building, Floor, FloorPlan, Wall, Poi,
                   ScanSession, Measurement, Contributor
    repositories/  repo interfaces + implementations
  features/
    onboarding/    bloc / view / widgets
    auth/
    sonar/         <- KEPT sound feature: measure distance + radar
    scan/          <- NEW: ARCore depth -> point cloud -> floor plan
    acoustic/      <- room classifier + fallback (shares DSP with sonar)
    explore/       building browser + detail
    navigation/    graph builder, A*, turn-by-turn, AR overlay, obstacle alerts
    accessibility/ voice mode, haptics
    map_view/      2D floor-plan render + 3D preview
    profile/       contributor stats, badges, leaderboard
  services/        dsp, audio, vision (ARCore channel), sensor, mlkit,
                   routing, export        <- shared engines
  shared/          widgets, utils, painters (radar, floor plan)
android/app/src/main/kotlin/...           <- ARCore native code
```

Each feature folder: `bloc/` (event, state, bloc), `view/`, `widgets/`.

**Hive boxes:** `floorPlansBox`, `sessionsBox`, `measurementsBox`, `cachedMapsBox` (community maps downloaded from Supabase), `settingsBox`. Store a `FloorPlan` as one Hive object with embedded `walls` / `pois` lists. Listing = `box.values`; no joins needed locally.

**Bloc pattern for sensing:** stream frames in as events.
- `ScanBloc`: `StartScan`, `DepthFrameReceived`, `FinishScan` -> `ScanInitial`, `Scanning(pointCloud, coverage)`, `ScanComplete(floorPlan)`
- `SonarBloc`: `Measure` -> `SonarIdle`, `Measuring`, `SonarResult(distance, heading)`
- plus `AuthBloc`, `ExploreBloc`, `NavigationBloc`, `AccessibilityBloc`.

---

## 4. Build sequence (risk-ordered)

Each milestone has an acceptance check. Build in order.

### M0 — Spike: ARCore depth -> Flutter
Native Kotlin ARCore session -> depth + pose -> platform channel -> Flutter.
**Accept:** live depth numbers print on a real Android device.

### M1 — Foundation
Fresh project; folder structure; Bloc + get_it; go_router; design system (coral `#FB5B47`, ink `#1C1B1A`, Hanken Grotesk, tokens from the mockups); Hive init + adapters; Supabase client + auth (Google/Apple/email screens).
**Accept:** app runs, theme applied, sign-in works, empty home renders.

### M2 — Sonar feature (the kept sound feature)
Port DSP engine (chirp, FFT cross-correlation, ToF, parabolic interpolation). Add **mic capture** (record) + **real playback** (flutter_soloud) — the I/O that was stubbed before. Wire `SonarBloc` to the radar view.
*Fixes to land while porting:* real `fromPolar` trig (`x = d*cos θ, y = d*sin θ`), and a real noise gate (compare peak to RMS/sidelobe, not to itself).
**Accept:** a real measurement produces a real distance + heading on the radar.

### M3 — Scan -> 2D floor plan (vision)
Accumulate depth frames into a point cloud (with pose); RANSAC/Hough line-fitting -> wall segments -> 2D plan; live render on the Scan screen.
**Accept:** walk a real room, get a recognisable plan; dimensions sane vs tape.

### M4 — Semantic labels (ML Kit)
Object detection (doors, obstacles) + text recognition (room numbers/signs); place labels on the plan.
**Accept:** doors and room numbers appear during a scan.

### M5 — Acoustic room classifier + fallback
Reuse M2's DSP: extract reverb features -> TFLite classifier (corridor / small room / hall); acoustic fallback distance when depth is unreliable.
**Accept:** classifier names the space type; fallback fires in low light.

### M6 — Crowdsource backend
Supabase schema (buildings, floors, floor_plans, pois, contributors, ratings); upload a plan; browse nearby buildings; building detail; load a plan; cache into `cachedMapsBox`.
**Accept:** scan on one device, open it on another.

### M7 — Navigation
Floor plan -> navigation graph; A* routing; turn-by-turn voice + arrow; AR waypoint overlay; real-time obstacle alerts (ML Kit).
**Accept:** pick a room, get guided there; obstacle announced en route.

### M8 — Accessibility mode
Full voice flow (flutter_tts + speech_to_text), proximity haptics, eyes-free operation.
**Accept:** complete a navigation with the screen off.

### M9 — Persistence, 3D, export, polish
Hive persistence of plans/sessions/history; 3D extruded preview (flutter_gl); PDF export; profile/leaderboard; empty/error/loading/dialog/toast states from the mockups.
**Accept:** offline reload works; PDF exports; all screens present.

### M10 — Evaluation
Map accuracy (3 environments vs tape), classification accuracy, navigation success rate (sighted vs accessibility).
**Accept:** data tables + charts ready for Chapter 5.

---

## 5. Driving Claude Code

1. **`CLAUDE.md` at repo root** — paste sections 2–3 (stack + architecture). Add: "State = Bloc, persistence = hive_ce, never reference any other DB."
2. **M0 as a real spike** in a throwaway branch before anything depends on it.
3. **One milestone per session, one task per prompt.** "Write the FloorPlan Hive model + adapter" beats "do the data layer."
4. **Give the acceptance check up front.**
5. **Point it at the HTML mockups** for any UI task.
6. **Test on a real Android device** after M0, M2, M3, M5 — emulators won't give real ARCore/mic behaviour.
7. **For each Bloc, specify events + states explicitly** in the prompt; Claude Code fills in the rest cleanly.

---

## 6. Risk list (honest)

- **ARCore<->Flutter channel (M0)** — highest risk; spike first.
- **iOS scanning (ARKit)** — optional/later; ship Android-first scanning.
- **Line-fitting on noisy point clouds (M3)** — budget tuning time.
- **TFLite classifier (M5)** — needs reverb training samples per room type; keep scope small.
- **Navigation graph from imperfect plans (M7)** — plan for manual correction in the UI.
- **hive_ce** — community-maintained; pin the version and keep models simple (no relational queries locally).

---

## 7. Port-from-old checklist

- [ ] DSP engine: ChirpGenerator, CrossCorrelationService, ToFCalculator -> `services/dsp/`
- [ ] Radar painter -> `shared/painters/` (reused by sonar feature)
- [ ] PDF export -> `services/export/`
- [ ] Design tokens (from HTML mockups) -> `core/theme`
- [ ] Supabase auth pattern (from JustBuy/JEPS) -> `data/remote` + `features/auth`

**Fix on the way in:** `fromPolar` trig, noise-gate comparison, return `-1` on out-of-range instead of clamping, drop the duplicate Measurement models down to one.


 i want to build a v2, so I'll create a new branch(echolocate
  v2). this is what we are going to be doing. we will be redoing
  all of that, checkout echolocate v2 build plan. what do you
  think about it,