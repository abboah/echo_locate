# EchoLocate v2 — Build Plan (SOURCE OF TRUTH)

> This document supersedes all earlier plans. If anything elsewhere disagrees with this file, **this file wins.** Last updated: 2026-06.

A clean, from-scratch rebuild of EchoLocate as a cross-platform Flutter app for **crowdsourced indoor mapping + navigation, built as an accessibility aid (especially for the visually impaired).**

---

## 0. What the app is (corrected concept)

People **scan** indoor spaces with their phone camera; the app reconstructs a **floor plan**, those plans are **crowdsourced** to a community backend, and anyone can then **browse and navigate** a building turn-by-turn — including a fully **eyes-free voice/haptic mode**.

**Sensing strategy (important — this changed):**
- **Camera + on-device AI is the PRIMARY sense.** Obstacle/hazard detection and reading signs/room-numbers aloud (ML Kit), plus depth/proximity awareness. This is the part people actually use, and the part we demo.
- **Acoustics is repositioned: room-type CLASSIFICATION, not ranging.** Phone acoustic *sonar/ranging* is not reliable (speaker↔mic crosstalk, 1/r⁴ echo loss, hardware roll-off, multipath). Instead the DSP analyzes **reverberation** to classify the space (corridor / small room / hall). This is the novel research contribution and it does **not** depend on the riskiest tech. A single-shot sonar distance + radar view is kept only as a small "lite" demo feature.
- **Accessibility is the purpose** that ties it together (voice guidance + haptics).

**Thesis framing:** lead with **acoustic room classification** as the technical novelty and **accessibility** as the impact; camera AI is the usable core and the impressive demo.

---

## 1. Architecture — HYBRID: Bloc presentation + Achieve repositories

> Decision: we use **flutter_bloc for the presentation layer**, sitting on top of **Achieve-style repositories**. We do **NOT** use Achieve's DataPage / OperationRunner / OverlayManager — Bloc owns screen state instead.

**Keep from Achieve:** Repository (abstract interface + impl with caching mixin), GetIt service locator, EventBus (optional, cross-feature).
**Drop from Achieve:** DataPage, OperationRunnerState, OverlayManager. (`BlocBuilder` + a `loading/error/data` state replaces them.)

### Per-feature recipe
1. **Model** — Freezed + Equatable, in `core/models/`.
2. **Repository** — abstract interface + impl with `RepositoryMixin` caching (`runPersistedQuery` / `runSecureQuery` / `runEphemeralQuery` / `runOperation`), in `features/<feature>/`.
3. **Bloc** — `event` / `state` / `bloc`; the Bloc calls the repository and emits `Loading / Loaded / Error`.
4. **Page** — renders with `BlocBuilder`; `BlocListener` for one-off effects (dialogs, navigation, toasts).
5. **Register** repository + bloc in `injection_container.dart` (GetIt).
6. **Route** — named route in the dual go_router.

### Live-sensing screens (vision / acoustic / scan / navigate)
The feature Bloc **subscribes to a GetIt-registered stream controller** (camera / audio / depth) in `services/sensing/` and `emit`s a state per frame; UI renders via `BlocBuilder`. This isolates real-time work to a few controllers.

### Folder structure
```
lib/
  core/
    models/      Building, Floor, FloorPlan, Wall, Poi, ScanSession,
                 Detection, RoomClass, Measurement, Contributor
    theme/       tokens, typography, light_theme, dark_theme, ThemeCubit
    config/
  features/<feature>/
    bloc/        <feature>_event · <feature>_state · <feature>_bloc
    <feature>_repository.dart            (abstract + impl w/ RepositoryMixin)
  ui/pages/
    guest/   onboarding · permission primers · auth
    user/    home · explore · building_detail · scan · navigate ·
             map_view · accessibility(voice) · maps(saved) · profile · settings
             (each may have /widgets)
  shared/    widgets (cards, bottom_nav, buttons, dialogs, toasts, banners),
             painters (radar, floor_plan), utils
  services/
    injection_container.dart             (GetIt: repos + blocs + controllers)
    event_bus/
    core/      supabase client · logging · config
    sensing/   camera_controller · audio_engine(dsp) · depth_controller · sensor_service
    ml/        mlkit (object detection + OCR) · tflite (room classifier)
    routing/   a_star · graph_builder
    export/    pdf
  router/    guest_router.dart · user_router.dart
```

---

## 2. Locked stack

| Layer | Choice |
|---|---|
| Framework | Flutter (Dart) — iOS + Android |
| Presentation | **flutter_bloc** (events → states → BlocBuilder) |
| Data layer | **Achieve-style repositories** + caching mixins |
| DI | **get_it** (service locator) |
| Routing | **go_router** — dual routers (guest/user), named routes only |
| Local persistence | **hive_ce** (+ hive_ce_generator) behind repositories |
| Cloud / crowdsource | **Supabase** (Postgres + Storage + Auth) |
| Primary sense | **camera** + **google_mlkit** (object detection + text/OCR) |
| Depth / mapping | monocular depth (proximity) first; **ARCore** depth = stretch (Android, platform channel) |
| Acoustic | **fftea** (DSP, ported from v1) + **record** (mic) + **flutter_soloud** (playback) |
| Acoustic classifier | **TFLite** (reverb → room type) |
| Sensors | sensors_plus |
| Voice / accessibility | flutter_tts + speech_to_text + haptics |
| Routing engine | custom **A\*** (Dart) |
| 3D preview | flutter_gl (stretch / polish) |
| Export | pdf + printing |
| Models | freezed + json_serializable + equatable |

> **Never repeat the v1 mistake:** commit to **hive_ce everywhere** (models, boxes, comments). Never reference any other local DB.

**Hive boxes:** `floorPlansBox`, `scanSessionsBox`, `measurementsBox`, `cachedMapsBox`, `settingsBox` (holds `themeMode`).

---

## 3. Design system (from Figma `MGYeyWGqLMH3rSaabjvfvI`)

**Tokens (confirmed from the design):**
| Token | Hex | Use |
|---|---|---|
| Coral | `#FB5B47` | single warm accent — primary actions, active states, route line |
| Ink | `#1C1B1A` | text, dark surfaces (nav highlights, dialogs' primary button) |
| Surface | `#F6F5F2` | cards, muted panels, scan placeholders |
| White | `#FFFFFF` | page background |

Style rule from the design notes: **"clean, one warm accent, white surfaces, no gradients."**
- Typography: **Hanken Grotesk** (confirm exact weights/sizes from Figma text styles).
- Rounded cards (~16 r), soft shadows, generous padding.
- **Bottom nav:** 5 tabs — Home · Explore · **[center Scan FAB]** · Maps · Profile.
- **Dark mode:** invert Surface/White ↔ Ink family; Coral stays the accent. Build both themes from the same tokens.

**Shared components to build once (Phase 1):** primary/secondary button, card, bottom nav + center FAB, dialog (e.g. End navigation / Discard scan), toast (success + undo), inline banner (warning/error), permission-primer layout, list skeleton/empty/offline state.

### Screen inventory (map → feature → phase)
*Confirmed from Figma (15 screens + design system):*

| Node | Screen | Feature | Phase |
|---|---|---|---|
| 7-488 | Home (location, search, Scan CTA, Recently mapped) | home | P1 |
| 7-895 | Location permission primer | onboarding | P1 |
| 7-939 | Camera permission primer (on-device, never stored) | onboarding | P1 |
| 7-301 | Building detail (floors, rooms, Navigate here, 3D) | explore | P1 UI · P2 data |
| 7-448 | Scan — camera view (Room type, Coverage, Size) | scan | P1 UI · P2 logic |
| 7-703 | Scan-quality inline banners (low light / tracking lost) | scan | P2 |
| 7-840 | Discard-scan dialog | scan | P2 |
| 7-265 | Navigation — 2D route (turn-by-turn) | navigate | P2 |
| 7-816 | End-navigation dialog | navigate | P2 |
| 7-189 | 3D floor-plan preview (2D/3D toggle) | map_view | P3 |
| 7-227 | Accessibility voice mode ("Turn right", waveform) | accessibility | P3 |
| 7-866 | Success dialog — map uploaded + leaderboard | crowdsource | P2 |
| 7-679 | Toast — success (location link copied) | shared | P1 |
| 7-654 | Toast — undo (scan deleted) | shared | P1 |
| 7-750 | Offline / error state (saved maps still work) | shared | P1 |
| 7-162 | Design tokens sheet | design system | P1 |
| 7-565 / 7-369 | Icon set | design system | P1 |
| 7-139 | Route-visualization component | shared/painter | P2 |

*Pending Figma reconnect (10 nodes — slot in when network returns):* `7-963, 7-728, 7-1010, 7-1122, 7-1155, 7-774, 7-372, 7-1089, 7-445, 7-1057` — expected to cover: onboarding/welcome, auth/sign-in, Explore/search, Maps/Saved list, Profile + leaderboard, **Settings (dark-mode toggle)**, 2D floor-plan view, loading/skeleton, plus more dialogs/toasts.

---

## 4. Phased build plan (UI is part of Phase 1)

Hard deadline **< 2 months**, scope **fixed by proposal** → protect a working spine at full depth; take the rest to proof-of-concept; deliver in 3 phases. **All UI screens are built in Phase 1 against mock repositories**, then later phases swap real data/logic into screens that already exist.

### PHASE 1 — Foundation + Design System + Full UI Shell + Core Sensing (Weeks 1–4)
**Build:**
- Fresh project; hybrid architecture skeleton (Bloc + Achieve repos + GetIt + EventBus + dual go_router).
- **Design system:** tokens, typography, **light + dark themes + ThemeCubit** (persisted to `settingsBox`), all shared components.
- **All screens built and navigable against mock/stub repositories** — Home, Explore, Building detail, Scan, Navigate, Map view, Accessibility, Maps/Saved, Profile, Settings, onboarding + permission primers, dialogs, toasts, banners, offline/empty states — **in both light and dark.**
- Hive init + adapters; Supabase client + auth (sign-in screens working).
- **Functional core (the protected spine):**
  - **Vision Assist** — camera stream + ML Kit object detection + OCR → spoken alerts (this is the "people will use it" feature).
  - **Acoustic room classification** — finish audio I/O (record + soloud), port DSP, reverb features → classifier (rule-based first; TFLite later).

**Accept:** app runs; every screen navigable in light + dark; sign-in works; Vision Assist announces a door/sign; acoustic names the room type.
**Background task from week 1:** collect & label reverb samples for the TFLite classifier.

### PHASE 2 — Mapping, Crowdsource & Navigation (Weeks 5–6)
**Build:**
- **Scan → 2D floor plan:** depth/proximity ("wall 2 m ahead" + haptic), accumulate into a plan; wire the real pipeline into the existing Scan UI + quality banners + discard dialog.
- **Crowdsource backend:** Supabase schema (buildings, floors, floor_plans, pois, contributors, ratings); upload a plan; browse nearby; cache to `cachedMapsBox`; wire real data into Home/Explore/Building detail/Maps.
- **Navigation:** floor plan → graph → custom **A\*** → turn-by-turn (arrow + 2D route); wire Navigate UI + end-navigation dialog; obstacle alerts reuse Phase 1 vision.

**Accept:** scan a real room → recognizable plan; upload; open it on another device; pick a room and get guided there.

### PHASE 3 — Accessibility, Intelligence & Evaluation (Weeks 7–8)
**Build:**
- **Accessibility voice mode:** full flow (flutter_tts + speech_to_text + haptics), eyes-free operation; wire the voice-mode screen.
- **Semantic labels** (ML Kit: doors/obstacles + room-number OCR placed on the plan); **swap in the TFLite** room classifier.
- **Polish:** 3D extruded preview (flutter_gl), PDF export, profile/leaderboard.
- **Evaluation (Chapter 5):** map accuracy vs tape (3 environments), classification accuracy, navigation success (sighted vs eyes-free) → tables + charts.

**Accept:** complete a navigation with the screen off; evaluation data ready.

---

## 5. Risk list (honest)
- **ARCore depth platform channel** — highest risk; **monocular depth is the default**, ARCore is stretch. Spike on a real device before depending on it.
- **TFLite classifier** — needs a reverb dataset; **start collecting in week 1**, rule-based fallback first.
- **Line-fitting on noisy point clouds (mapping)** — budget tuning time; allow manual correction.
- **Navigation graph from imperfect plans** — plan for manual correction in the UI.
- **flutter_gl (3D)** — least-maintained dep; keep in polish/stretch.
- **< 2 months** — Phases 2–3 are proof-of-concept depth by design. Depth on the spine, breadth elsewhere, honest evaluation.

## 6. Port-from-v1 checklist (fix on the way in)
- [ ] DSP engine: ChirpGenerator, CrossCorrelationService, ToFCalculator → `services/sensing/audio_engine` (now feeding the **classifier**, not a radar).
- [ ] Radar painter → `shared/painters/` (sonar "lite" demo only).
- [ ] PDF export → `services/export/`.
- [ ] **Fix:** `fromPolar` real trig (`x=d·cosθ, y=d·sinθ`); real noise gate (peak vs RMS/sidelobe); return `-1` on out-of-range instead of clamping; collapse duplicate Measurement models to one.

## 7. Driving Claude Code
- This file + `CLAUDE.md` are the contract. State = Bloc, data = Achieve repos, persistence = hive_ce, **never** reference Riverpod/Drift/Isar or DataPage.
- **One screen or one Bloc per prompt**, with its acceptance check stated up front.
- Point Claude at the specific Figma node for any UI task; build light + dark together.
- Test on a real Android device after the sensing milestones (camera/mic/depth) — emulators lie.
- For each Bloc, specify events + states explicitly.
