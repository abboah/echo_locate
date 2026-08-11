# Landmark Navigation — Build Spec

**Status:** approved scope, August 2026 · **streams merged 11 August 2026**
**Team:** two developers. Built as Stream A (2D map + routing) and Stream B (capture +
guidance); both are now integrated on one branch and the split is history — see §5.
**Window:** ~2 weeks to submission

---

## 1. Context

EchoLocate's proposal promised indoor floor plans generated from ARCore depth-from-motion,
converted to walls by RANSAC/Hough line fitting, then navigated with A*. The depth capture
half of that works — `ArCoreDepthService`, `ArCoreDepthHandler.kt`, `DepthFrame` and
`ScanCapabilityCubit` are built and tested. The rest never will be inside the deadline, and
one hardware fact makes it worse: **the team's test device (Infinix X657C) is not
ARCore-certified.** ARCore's install service fails to resolve it at all (`requestInfo
returned: -100`), so scanning is gated off on the only phone available for daily work.

This spec replaces sensor-derived geometry with **landmark-derived geometry**.

The building is already mapped — room numbers, floor signs and directory boards are painted
on its walls. Sighted people navigate by reading them; blind people cannot. So a contributor
walks the building once, the app reads the signage with OCR and counts steps between
sightings, and that recording becomes both the navigation data and, after a layout pass, a
2D schematic map.

Nothing here needs ARCore, beacons, WiFi fingerprinting, or a positioning system.

**The core design idea, in one line:** step counting gets the user near the next landmark,
and reading the sign confirms they are there. Dead reckoning alone drifts without bound;
sign reading alone cannot say how far to walk. Each covers the other's failure, and every
landmark resets accumulated step error to zero.

### Prior art (this is not speculative)

- **NaviLens** — camera-read coded tags at decision points, spoken aloud; deployed in the
  Barcelona metro and other transit systems specifically for blind passengers.
- **Seeing AI / Envision** — OCR-reads-the-world as an assistive primitive, at scale.
- **Apple Indoor Survey, GoodMaps** — the principle that somebody walks a venue once with a
  phone to generate its data.

---

## 2. Already built — do not rebuild

| Capability | Where |
|---|---|
| Camera → ML Kit object detection → obstacle stream | `lib/services/sensing/detection_service.dart` |
| Callout rules (nearest wins, proximity bands, cooldowns) | `lib/services/sensing/callout_policy.dart` |
| Text-to-speech wrapper | `lib/services/speech/speech_service.dart` |
| Mic/speaker contention arbiter | `lib/services/audio/audio_arbiter.dart` |
| Repository caching (`runOfflineFirstQuery`, `runOperation`) | `lib/data/repository_mixin.dart` |
| Buildings / floors / rooms + RLS + KNUST seed | `supabase/migrations/` |
| Radar `CustomPainter` — pattern to copy for the map | `lib/ui/widgets/radar_painter.dart` |
| Sonar, reverb analysis, room classification | `lib/services/dsp/`, `lib/services/acoustic/` |
| Auth, all screens, light/dark, DI, routing | throughout |

`google_mlkit_text_recognition` and `speech_to_text` are already in `pubspec.yaml` and
imported nowhere. OCR is this spec's centre, not a new dependency.

## 3. Out of scope

RANSAC/Hough line fitting · point-cloud accumulation · AR waypoint overlay · 3D extruded
preview (`flutter_gl`) · PDF export · trained TFLite classifier (the rule-based
`RoomClassifier` stands, and argues its own case in source) · iOS/ARKit · compass headings
(indoor magnetic interference makes them unreliable — turns are recorded as discrete taps).

Sonar and acoustic classification stay in the repo and the report as Deliverable 2. They are
out of the *demo narrative*: measuring distance to a wall is not a user story. Room
classification stays in the product — "you are in a large hall" is worth hearing on entry.

---

## 4. Data model

Three new tables plus one column. Written as a migration in `supabase/migrations/`,
following the existing file conventions.

```sql
-- A thing the camera can recognise and the user can stand at.
create table public.landmarks (
  id            uuid primary key default gen_random_uuid(),
  building_id   text not null references public.buildings (id) on delete cascade,
  floor_id      uuid not null references public.floors (id) on delete cascade,
  kind          text not null check (kind in
                  ('entrance','junction','stairs','lift','door','sign')),
  label_text    text not null,              -- normalised OCR target: '204'
  aliases       text[] not null default '{}', -- observed misreads: '2O4', '2 04'
  display_name  text not null,              -- 'Reading Hall door'
  room_id       uuid references public.rooms (id) on delete set null,
  created_by    uuid references public.profiles (id) on delete set null,
  created_at    timestamptz not null default now()
);

-- One recorded walk: a start point to a destination room.
create table public.routes (
  id                  uuid primary key default gen_random_uuid(),
  building_id         text not null references public.buildings (id) on delete cascade,
  start_landmark_id   uuid not null references public.landmarks (id),
  destination_room_id uuid not null references public.rooms (id) on delete cascade,
  total_distance_m    numeric not null default 0,
  verified_count      int not null default 0,
  created_by          uuid references public.profiles (id) on delete set null,
  created_at          timestamptz not null default now()
);

-- One leg, landmark to landmark.
create table public.route_steps (
  route_id          uuid not null references public.routes (id) on delete cascade,
  seq               int not null,
  from_landmark_id  uuid not null references public.landmarks (id),
  to_landmark_id    uuid not null references public.landmarks (id),
  instruction       text not null,     -- spoken: 'straight past the help desk'
  distance_m        numeric not null,
  steps_recorded    int,               -- contributor's raw count; evidence only
  turn_deg          int not null default 0,  -- 0, ±90, ±135; see §6
  primary key (route_id, seq)
);

alter table public.profiles add column stride_length_m numeric;
```

RLS follows the existing pattern: readable by any authenticated user, writable by the
creator or an existing building contributor (`public.can_edit_building`).

### The one modelling rule that matters

**Store metres. Never store steps as the canonical distance.**

A contributor with a 78 cm stride and a user with a 65 cm stride do not share a step count.
The contributor's count is converted to metres on capture; the user's metres are converted
back into *their* steps on playback. `steps_recorded` is kept only as raw evidence for the
evaluation chapter.

---

## 5. The seam between map and guidance

Originally the contract that let two developers work in parallel: Stream A owned the
migration, the models and the repository; Stream B consumed them. That worked, and the split
has now served its purpose — both halves are integrated and the sections below describe one
system rather than two assignments.

What survives the merge is the seam itself, and it is worth keeping deliberate. The map and
the voice are **the same graph read two ways**, and they cannot be allowed to drift apart:
the picture an examiner checks and the directions a blind user follows have to be the same
claim about the building, or one of them is lying.

### The types both halves speak

```dart
// lib/core/models/landmark.dart, walk_route.dart  (freezed, matching existing models)
class Landmark   { id, buildingId, floorId, kind, labelText, aliases, displayName, roomId }
class RouteStep  { seq, fromLandmarkId, toLandmarkId, instruction, distanceM, turnDeg }
class WalkRoute  { id, buildingId, startLandmarkId, destinationRoomId, totalDistanceM, steps }
```

`WalkRoute` is what a contributor **recorded**. `PlannedRoute` is what a user is about to
**walk** — see §6 A4. Guidance takes the second, so following a recording and following an
A\* path are one code path; the harder case would rot if only the demo exercised it.

```dart
// lib/features/routing/route_repository.dart
abstract class RouteRepository {
  Future<List<Landmark>> landmarksOf(String buildingId);
  Future<List<WalkRoute>> routesOf(String buildingId);
  Future<WalkRoute?>      routeTo(String buildingId, String roomId);
  Future<void>            saveRoute(WalkRoute route, List<Landmark> newLandmarks);
  Future<TracedPlan?>     tracedPlanOf(String buildingId);
}
```

`SupabaseRouteRepository` implements it with `runOfflineFirstQuery` so routes work offline
once fetched — the same pattern as `SupabaseBuildingRepository`.

### Seed data

The map and A\* needed real input before capture existed, so **two hand-authored routes** are
seeded (KNUST Library ground floor → Reading Hall, and → Study Room 2B). The pair matters
more than either one: they share their first legs and diverge on floor 2, which is what gives
A\* somewhere to leave one contributor's walk and join another's. One seeded route would have
made §6 A4 untestable.

---

## 6. The map and routing

**Lives in:** `supabase/migrations/`, `lib/core/models/landmark.dart`, `walk_route.dart`,
`traced_plan.dart`, `lib/features/routing/`, `lib/services/mapping/`,
`lib/ui/pages/navigate/`, `lib/ui/widgets/floor_plan_painter.dart`

### A1 · Schema, models, repository
Migration, freezed models, `RouteRepository` + `SupabaseRouteRepository`, seed routes.
**Accept:** `routesOf('knust-library')` returns two seeded routes, the Reading Hall one with
5 legs; offline fallback returns the cached copy.

### A2 · Turtle layout — *pure Dart, no device*
Convert a route's legs into 2D coordinates. Start at the origin facing 0°; for each leg,
rotate by `turn_deg`, advance `distance_m`, emit a node.

```dart
// lib/services/mapping/route_layout.dart
List<MapNode> layout(WalkRoute route, [Map<String, Landmark> landmarks]);
double? misclosureOf(List<MapNode> nodes);
// MapNode: landmarkId, floorId, x, y
```

Landmarks are passed in because they carry the floor. **A floor change consumes no
horizontal distance:** the climb is real metres and guidance quotes them, but spending them
on the plane would push every floor-2 landmark eight metres down a ground-floor corridor.
The landing is placed directly above the stairwell, which is where it physically is.

**Accept:** a 4-leg square (10 m, turn 90° each) returns to within 0.01 m of the origin; a
route that climbs puts the landing at the stairwell's coordinates on the upper plane.

### A3 · Node snapping and graph merge
Routes in one building share landmarks. Two routes through "floor 2 stairwell" pass through
the *same point*. Each route is laid out in its own frame, then rotated and translated onto
the landmarks it already shares with what is placed — one shared landmark fixes position, two
fix rotation. Routes are placed most-overlapping first, so capture order does not decide
whether a building comes out as one map or three. A route sharing nothing is parked clear of
the rest rather than stacked on top of it.

```dart
// lib/services/mapping/floor_graph.dart
static FloorGraph  merge(List<WalkRoute>, [Map<String, Landmark>]);
static MergeResult mergeWithDiagnostics(List<WalkRoute>, [Map<String, Landmark>]);
static FloorGraph  fromPlan(TracedPlan);
```

Angular error accumulates and loops will not close cleanly. **Do not fight this with
least-squares optimisation.** Average duplicates and label the artifact a schematic — that
is what it is. But *do* measure it: `MergeResult.spreadM` reports how far apart a landmark's
separate placements were before averaging, and the map screen states the worst of it. A
schematic that admits its own error is a result; one that hides it is a lie. (§10.)

`fromPlan` is the counterpart, for a plan traced off the building's own posted floor plan:
those coordinates are absolute, so there is nothing to lay out or average away. Such a graph
is usually **unitless** — `FloorGraph.metric` is false, A\* does not care, and anything that
speaks a distance aloud checks it first.

**Accept:** two routes sharing two landmarks merge into one connected graph with no
duplicate nodes; two recordings that disagree by 6 m report a 6 m spread; routes that share
an id are all kept.

### A4 · A* over the graph
Textbook A\* — these graphs are tens of nodes, not thousands. Heuristic: straight-line
distance between laid-out node positions, which is admissible because the turtle layout walks
the recorded metres and a cross-floor pair sits at the same point.

The search is the easy half. A path spliced from fragments of other people's walks **cannot
reuse their words or their turns**:

- **Turns are recomputed** from the merged geometry. A recorded `turnDeg` is relative to the
  leg that preceded it *in that recording*; splice two walks together and the stored angle
  refers to an approach the user never made. The result is snapped to the vocabulary the
  capture UI offers, because "turn 73 degrees" is useless to somebody who cannot see the
  corner.
- **Wording survives only where it is still true.** A direction nobody walked has no words at
  all, and even the right direction is dropped when the user arrives a different way than its
  author did — "turn right; the stairwell is at the end" becomes a lie approached from
  anywhere else, and a lie spoken to somebody who cannot see the corridor is worse than
  silence. A leg with no wording is left null and guidance says something neutral.

**Accept:** given entrance→Reading Hall and entrance→Study 2B recorded separately,
planning Reading Hall→Study 2B returns a path nobody ever walked. **This is the demo moment.**
Walking a recorded corner backwards inverts its turn rather than replaying it.

### A5 · `FloorPlanView` and the map screen
Renders one floor of the graph: corridors as bordered bands, landmarks shaped by kind, the
active route in coral, a "you are here" ripple. Light and dark, per `CLAUDE.md`. A floor
switcher picks the plane — only the picture changes, since the graph spans every floor and
A\* routes across them.

**It is not left silent.** Every landmark is published as a `CustomPainterSemantics` node
naming it, its kind, and its role in the current journey, so a screen reader can explore the
plan and activate a landmark to say "I am here". A `CustomPaint` is one unlabelled box
otherwise, and tapping a landmark is the one manual input the screen depends on.

**Accept:** the seeded route renders as a recognisable corridor schematic in both themes;
the semantics tree carries every landmark on the drawn floor; a tap resolves to the landmark
that was drawn nearest it.

> The map is for sighted contributors, for verification, and for the examiners. A blind user
> is served by the same graph through voice — and, where they do reach for the picture, by
> its semantics. Say so in the report.

---

## 7. Capture and guidance

**Lives in:** `lib/services/sensing/text_recognition_service.dart`,
`lib/services/sensing/landmark_matcher.dart`, `lib/services/motion/step_service.dart`,
`lib/services/motion/stride_profile.dart`, `lib/features/capture/`,
`lib/features/guidance/`, `lib/features/plan_trace/`, `lib/ui/pages/capture/`,
`lib/ui/pages/guidance/`, `lib/ui/pages/plan_trace/`

### B1 · OCR service
Wrap `google_mlkit_text_recognition` as a stream of recognised text blocks, mirroring
`DetectionService`'s shape.

**Do not run object detection and OCR on the same frame.** Alternate — objects on even
frames, OCR on odd. `DetectionService`'s existing `_busy` flag already serialises frame
work; extend that loop rather than opening a second camera stream.

Matching is fuzzy: normalise case and whitespace, then accept a Levenshtein distance ≤1
against `label_text` or any entry in `aliases`. `0`/`O` and `1`/`I` confusions are the
common real-world misreads.
**Accept:** printed "204" on A4 is matched from ~2 m in office lighting.

### B2 · Step service
Wrap `pedometer` (4.2.0, verified publisher, wraps the **hardware** step counter — the same
sensor Google Fit uses, not hand-rolled accelerometer maths). Add
`ACTIVITY_RECOGNITION` to `AndroidManifest.xml` — it is not declared yet — and request it
through the existing `permission_handler`.

Stride calibration: user walks a measured 10 m, `stride = 10 / steps`. If skipped, fall back
to `stride ≈ 0.415 × height`. Persist to `profiles.stride_length_m`.

Some Samsung devices do not expose step counting at all. Detect this and degrade to §7 B5
level 2 rather than failing.
**Accept:** counted steps are within 5% of a manual count over 50 m.

### B3 · Capture flow
The contributor walks the building once:

1. Stand at the start, point at the directory board → OCR proposes text → confirm as a
   landmark, name it, pick a `kind`
2. Walk to the next decision point — steps count in the background
3. Point at the next sign → OCR proposes → confirm
4. Tap the turn taken: **straight / left / right / sharp left / sharp right / stairs**
   → `0 / -90 / +90 / -135 / +135 / stairs`
5. Type or dictate the instruction for that leg
6. Repeat to the destination door, then upload

Turns are tapped, not sensed. A compass would add magnetic-interference error for no gain.

**Target: 15–20 minutes per route.** One person, one phone, one afternoon for a floor.
**Accept:** a real route through a KNUST building is captured and appears in Postgres.

### B4 · GuidanceBloc
Subscribes to obstacles, OCR reads, and step ticks. Holds `currentStepIndex` and
`stepsSinceLandmark`. `expectedSteps = distanceM / userStride`.

Spoken progression per leg:

| Trigger | Utterance |
|---|---|
| leg start | "Straight past the help desk, about 25 steps." |
| ~50% | "About halfway." |
| ~80% | "You're close — sweep your phone to find the sign." |
| OCR match on `toLandmark` | "Reading Hall door." → advance, reset count |
| >120%, no match | enter recovery (B5) |

**An OCR match advances the leg regardless of step count.** The counter never accumulates
error across a route.

**Speech priority — extend `AudioArbiter`:** urgent obstacle > landmark confirmed >
progress update > routine obstacle. Without this the user hears "in ten steps, turn—"
layered over "CHAIR AHEAD", which is worse than useless for someone who cannot see it.

Haptics on urgent obstacle and on landmark reached (`VIBRATE` is already declared).
**Accept:** a blindfolded volunteer completes a captured route unaided.

### B5 · Fallback ladder
Each rung needs less than the one above:

1. **Steps + OCR** — primary
2. **OCR only** — no distances, instruction only ("walk to the end of the corridor, then
   look for the sign"). Works with zero sensors. This is the floor, and it is what a phone
   without a step counter gets.
3. **Recovery sweep** — on overshoot or an *I'm lost* tap: "stop, sweep your phone slowly
   left to right", then match against **every** landmark in the building, not just the
   expected one. On a hit: *"You're at the floor 2 stairwell — one landmark past your turn.
   Turn around; the Reading Hall door is about 12 steps behind you."*
4. **Ask a person** — "Ask someone nearby: you're looking for Room 204." A designed
   fallback, not a failure. It is what blind travellers already do.

The real mitigation is **landmark density** — one every 10–15 m keeps step error
irrelevant. The design lever is "record more landmarks", not "measure better".
**Accept:** deliberately walk past a landmark; recovery relocalises and re-guides.

---

## 8. How the two halves were reconciled

Both streams reached the mapping layer and built it differently. That is recorded here
because the resolution is a design decision, not a merge mechanic, and the reasoning should
outlive the branches.

**One graph, one planner, one painter.** Where the two implementations disagreed, the
interfaces that the rest of the app already spoke were kept, and the better *behaviour* was
ported onto them:

| Kept | Ported in |
|---|---|
| `PlannedRoute` / `PlannedLeg` as guidance's currency | multi-floor `MapNode.floorId`, `nodesOn` / `edgesOn` |
| Per-direction wording on `GraphEdge`, `FloorGraph.metric`, `fromPlan` | `mergeWithDiagnostics` spread evidence (§10) |
| `FloorMapBloc` as the map screen's bloc | geometric turn recomputation and approach-matched wording (§6 A4) |
| | `FloorPlanView`, its semantics tree and hit testing, `PlanViewport` |

Two things were **dropped deliberately**. The floor-plan screen's own voice guidance is gone:
it existed only because guidance did not yet, and `GuidanceBloc` is strictly more capable —
it has the step counter, OCR, obstacles and the recovery ladder. And instruction *synthesis*
in the planner was not adopted: a leg nobody phrased stays `null`, and guidance composes the
neutral sentence, which is the one place that knows whether a step count can be promised.

Files both halves touched — `injection_container.dart`, `app_router.dart`, `app_routes.dart`,
`pubspec.yaml`, `AndroidManifest.xml` — are now single-owner. Keep edits to them small.

---

## 9. Sequencing

Delivered as:

**Days 1–2** — schema, models, repository, seed, together. Then split.
**Days 3–6** — map: layout, merge, A\*. Capture: OCR, steps, capture flow.
**Days 7–9** — map: painter and screen. Guidance: GuidanceBloc, priority, haptics, recovery.
**Day 10** — **streams merged** (§8); one branch from here.
**Days 10–12** — field capture at KNUST, evaluation runs, fixes.
**Days 13–14** — report.

Report edits need no code and run in parallel throughout (§11).

## 10. Evaluation — Deliverable 6

Every limitation above is measurable. That turns them into results rather than excuses.

| Measure | Method | Target |
|---|---|---|
| Step count accuracy | counted vs manual, 50 m × 5 walks | within 5% |
| Stride calibration error | calibrated vs tape over 20 m | within 5% |
| OCR read range and angle | printed A4 and real signage, varying distance/angle | report the envelope |
| Landmark confirm rate | legs confirmed by OCR before overshoot | >80% |
| End-to-end success | blindfolded volunteers, 5 routes | completion rate + time + wrong turns |
| Room classification | `RoomClassifier` vs known room types, ~10 rooms | confusion matrix |
| Sonar range accuracy | vs tape, 3 environments | existing Deliverable 2 evidence |
| Schematic drift | `MergeResult.spreadM` across real captures; `misclosureOf` on a walked loop | report the envelope |

The last row is the one the map itself reports on screen. It is not a target to hit — the
schematic is derived from step counts and tapped turns and *will* drift — it is the number
that says by how much, which is what turns "this is a schematic" from a disclaimer into a
measurement.

## 11. Report edits (no code — start now)

- **Drift → hive_ce** everywhere, including the ER diagram (Figure 3.32), FR-08, FSR-08,
  §1.5, §1.7, §3.14.2, §3.15. The diagram currently describes a database that does not exist.
- **Riverpod → flutter_bloc** in §3.15.
- **Coral** `#E8553A` → `#FB5B47` in §3.14.1.
- **FR-01/FR-02 rewrite** — floor plans derived from recorded landmark routes, not depth
  point clouds. Depth capture is retained and reported as built; reconstruction is dropped.
- **FR-04** — rule-based RT60 classification rather than TFLite, with the justification
  already written in `room_classifier.dart`.
- **New FRs** for Assist mode and authentication. Both are built and neither appears
  anywhere in Chapters 1–3.
- **Re-date** the 12-week plan in §1.10 (currently ends 8 June 2026).
- **Add the device-certification finding as a limitation.** ARCore's install service returns
  `-100` on uncertified budget hardware and settles on `UNKNOWN_ERROR` rather than
  `UNSUPPORTED_DEVICE_NOT_CAPABLE`, so capability detection must fail closed. For an
  accessibility app aimed at users on budget Android, that is a genuine deployment result —
  see the reasoning already in `scan_capability_cubit.dart`.

## 12. What this delivers against the proposal

| Deliverable | Outcome |
|---|---|
| D1 Mapping engine | Depth capture retained; **2D schematic derived from recorded routes** replaces point-cloud reconstruction |
| D2 Acoustic DSP | Complete (rule-based classifier) |
| D3 Navigation & routing | **A* over the landmark graph** + obstacle detection + sign reading. AR overlay dropped |
| D4 Mobile application | Installable APK, full flow, light/dark |
| D5 Crowdsourced database | Supabase schema + offline cache; PDF dropped |
| D6 Evaluation report | §10 |
| D7 Report + source | Chapters 1–5 revised, repo, Supabase project |

**The claim to defend:** a positioning-free indoor wayfinding system for blind and
low-vision users on commodity Android hardware, where the building's own signage is the
positioning system, step counting spans the gaps between signs, and the floor plan is
derived from crowdsourced walks rather than sensors.
