# CLAUDE.md — EchoLocate v2

Authoritative working rules for this repo. Full detail in `EchoLocate-v2-build-plan.md` (the source of truth). If unsure, read that file.

## What this app is
Crowdsourced indoor mapping + navigation, built as an **accessibility aid** (esp. visually impaired). Users scan spaces with the **camera**, the app builds floor plans, plans are shared via Supabase, and anyone can navigate a building turn-by-turn including an **eyes-free voice/haptic mode**.

- **Primary sense = camera + on-device ML Kit** (obstacle detection + read signs aloud).
- **Acoustics = room-type CLASSIFICATION via reverberation (TFLite), NOT ranging/sonar.** (Phone sonar ranging is unreliable; a single-distance radar is a "lite" demo only.)

## Architecture — HYBRID (do not drift)
**flutter_bloc for presentation, on top of Achieve-style repositories.**
- **KEEP from Achieve:** Repository (abstract interface + impl w/ `RepositoryMixin` caching), GetIt DI, EventBus.
- **DROP from Achieve:** DataPage, OperationRunnerState, OverlayManager. Bloc owns screen state (`BlocBuilder` for loading/error/data).
- **Per feature:** Model (freezed) → Repository → Bloc (event/state/bloc) → Page (BlocBuilder) → named route. Register repo + bloc in `injection_container.dart`.
- **Live-sensing screens** (vision/acoustic/scan/navigate): the Bloc subscribes to a GetIt stream controller in `services/sensing/` and emits per frame.

## Hard rules
- **State = Bloc. Data = Achieve repositories. Persistence = hive_ce (exception: scalar settings/onboarding flags use shared_preferences). Routing = go_router (dual guest/user, named routes only). DI = get_it.**
- **NEVER** reference Riverpod, Drift, Isar, Provider, or Achieve's DataPage/OperationRunner. Commit to **hive_ce everywhere** (models, boxes, comments).
- Build every screen in **light AND dark** (ThemeCubit + tokens). No gradients.
- Repositories return typed models, never `dynamic`.

## Design tokens
Coral `#FB5B47` (single accent) · Ink `#1C1B1A` · Surface `#F6F5F2` · White `#FFFFFF`. Rounded cards, soft shadows, one warm accent, white surfaces. Figma file: `MGYeyWGqLMH3rSaabjvfvI`.

**Type: Lexend**, not Hanken Grotesk — chosen for its reading-fluency research, which is the point for this audience, and body sizes run a step above Material's defaults for the same reason. See `app_typography.dart`.

**Bottom nav: Home · Explore · [center Assist FAB] · Maps · Profile.** The centre FAB starts Assist, not Scan — the AR capture path was removed on 2026-08-31 and tracing a photographed plan is the only authoring path now.

Everything visual comes from `core/theme/`: `AppColors`, `AppDimens`, `AppTypography`, `AppTheme`. **Style through the theme, not per-widget.** `AppTheme` styles ElevatedButton, FilledButton, Outlined, Text and Icon buttons, Card, Chip, ListTile, Divider, Switch, SnackBar, BottomSheet, Tooltip, inputs and progress — a screen that needs a one-off colour is usually a token that should exist.

**Accessibility is a hard rule here, not a polish pass.** Every tappable that is not a labelled Material control gets a `Semantics` node saying what it is and its state; state carried only by colour is state a blind user does not get. Touch targets ≥44dp. Never pin a box that contains text to a fixed height — `minHeight` instead — the system font is the first setting this app's users change.

## Phases (see build plan for detail)
- **P1 (wk 1–4):** foundation + design system + **all UI screens vs mock repos, light+dark** + auth + core sensing (Vision Assist, acoustic classification).
- **P2 (wk 5–6):** scan→floor plan, Supabase crowdsource, A* navigation — wire real data into existing screens.
- **P3 (wk 7–8):** accessibility voice mode, semantic labels + TFLite, 3D/PDF/profile, evaluation.

## Workflow
- One screen or one Bloc per task; state its acceptance check first.
- Point at the specific Figma node for UI work.
- Test sensing (camera/mic/depth) on a real Android device.
- Don't claim done without verifying (build/run/observe).
