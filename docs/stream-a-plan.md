# Stream A — Phased Implementation Plan

**Companion to** `landmark-navigation-spec.md` §6. That spec is the source of truth for
*what* Stream A owns; this file is the ordering, the decisions, and the progress log.

**Scope:** 2D map + routing. Migration, models, repository, turtle layout, graph merge,
A*, `FloorPlanPainter`, map screen.

**Remaining at time of writing: ~7 working days.** Phases 1–2 are pure Dart — no device,
no dependency on Stream B, fully unit-testable. Phase 3 is the only UI-heavy phase.
Ordering is chosen so Stream B receives contract additions as early as possible.

---

## Status board

| Phase | Work | Est. | Status |
|---|---|---|---|
| 0 | Close A1 — seed to 5 legs, repository test | 0.5 d | ☑ done |
| 1 | Layout kernel — A2 turtle + A3 merge | 1.5 d | ☑ done |
| 2 | A* + route synthesis — A4 | 1.5 d | ☑ done |
| 3 | `FloorPlanPainter` + map screen — A5 | 2.5 d | ☑ done, verified on device |
| 4 | Field-data hardening + handoff | 1.0 d | ◐ code hardened + verified on live Supabase; KNUST capture outstanding |

Update this table as phases land. Each phase's acceptance check is stated before its work,
per `CLAUDE.md`.

---

## Already banked (A1, do not rebuild)

| A1 piece | Where |
|---|---|
| Migration + RLS + `save_route` RPC | `supabase/migrations/20260803090000_landmark_navigation.sql` |
| Seed route | `supabase/migrations/20260803090100_seed_library_route.sql` |
| Freezed models | `lib/core/models/{landmark,walk_route,route_draft}.dart` |
| `RouteRepository` + `MockRouteRepository` | `lib/features/routing/route_repository.dart` |
| `SupabaseRouteRepository` (offline-first) | `lib/features/routing/supabase_route_repository.dart` |
| DI registration | `lib/services/injection_container.dart` |

---

## Phase 0 · Close A1 — 0.5 day

A1 is built but its acceptance check does not pass as written, and it is the one piece
Stream B already consumes. Fixing it now is cheap; fixing it after capture writes against
it is not.

**Work**

1. `20260803090100_seed_library_route.sql` — split the final leg into two (landing →
   corridor junction → Reading Hall door) so the seed has **5 legs**, adding the junction
   landmark. Mirror the change exactly in `MockRouteRepository._libraryRoute`; if the two
   diverge, offline and online render different maps.
2. New `test/route_repository_test.dart`, modelled on `test/building_repository_test.dart`:
   - `routesOf('knust-library')` returns 5 legs in `seq` order
   - `routeTo` picks the highest `verifiedCount`
   - `saveRoute` rejects an empty draft
   - offline fallback returns the cached copy after a simulated fetch failure

**Accept:** `flutter test test/route_repository_test.dart` green; the spec's A1 acceptance
check literally passes.

### Outcome

Done. Seed and mock both carry 5 legs (the floor-2 directory board splits the old final
leg); 18 new tests, full suite 160 green.

Three defects surfaced that were not in the plan:

1. **`explicit_to_json` was off** — `WalkRoute.toJson()` emitted its `steps` as live
   `RouteStep` objects rather than maps, and `Floor.toJson()` did the same with rooms.
   Invisible over the wire, fatal in the Hive cache: the write throws inside
   `runOfflineFirstQuery`'s try, the catch finds no cache, and a *successful* network read
   surfaces as a failure. Every offline-first read of routes or buildings was broken. Fixed
   globally in a new `build.yaml`; codegen regenerated.
2. **`MockRouteRepository.routeTo` returned the first match**, not the most-verified, so the
   mock disagreed with the server. Ranking extracted to a shared `bestRouteTo`, now used by
   both, with ties resolved deterministically.
3. **`MockRouteRepository.saveRoute` accepted empty drafts** while the Supabase impl
   rejected them. Message shared as `emptyDraftMessage`.

---

## Phase 1 · Layout kernel (A2 + A3) — 1.5 days

New directory `lib/services/mapping/`. Nothing in it imports Flutter.

### 1a · Geometry value types

`lib/services/mapping/map_node.dart`

```dart
class MapNode    { final String landmarkId; final String floorId; final double x, y; }
class MapEdge    { final String fromId, toId; final double distanceM; }
class FloorGraph { final Map<String, MapNode> nodes; final List<MapEdge> edges; }
```

**Decision:** these are plain immutable classes with `Equatable`, **not** freezed.
`CLAUDE.md`'s freezed rule covers repository models; these are derived geometry, never
persisted or serialised. The source says so in a comment, or the next reader "fixes" it.

### 1b · A2 · Turtle layout

`lib/services/mapping/route_layout.dart`

```dart
List<MapNode> layout(WalkRoute route, Map<String, Landmark> landmarks);
```

Start at origin heading 0°. Per leg: `heading += turnDeg`, advance `distanceM`, emit node.

**The case the spec omits:** legs into `LandmarkKind.stairs` / `.lift` change *floor*, not
floor-plane position. `Landmark.breaksStepCounting` already marks exactly these. Lay each
`floorId` out on its own plane; a stairs leg advances the floor and carries `(x, y)` across
unchanged, so the floor-2 landing sits directly above the ground stairwell. Without this,
the seeded route places a floor-2 door 8 m down a ground-floor corridor and the Phase 3 map
is nonsense.

Landmark lookup is needed for `floorId`, hence the second parameter.

**Accept:** unit test — 4 legs of 10 m turning 90° each returns within 0.01 m of origin;
a stairs leg emits a node on a new `floorId` at the same `(x, y)`.

### 1c · A3 · Node snapping and graph merge

`lib/services/mapping/floor_graph.dart`

```dart
FloorGraph merge(List<WalkRoute> routes, List<Landmark> landmarks);
```

Lay each route out independently, group nodes by `landmarkId`, average duplicate positions,
rebuild edges weighted by `distanceM`. Deduplicate edges between the same pair, keeping the
mean distance.

No least-squares. Loops will not close; that is a schematic, per spec §6 A3.

**Accept:** unit test — two synthetic routes sharing two landmarks merge into one connected
graph; node count equals distinct landmark count; no duplicates.

### Outcome

Done. 26 tests across `test/route_layout_test.dart` and `test/floor_graph_test.dart`; both
spec acceptance checks pass, plus the seeded route merging into a stacked two-floor
schematic.

**One design change beyond the plan: frames are aligned before averaging.** The spec's
"average duplicate positions" is only correct while every route starts from the same
landmark. A route recorded from the floor-2 stairwell lays out with the stairwell at *its*
origin, so averaging it against a route that placed the stairwell 18 m east yields a point
that is in neither place, and drags everything downstream with it. `merge` now anchors each
route onto the already-placed set: two shared landmarks fix rotation and position, one fixes
position only, none marks the route unanchored. Still no least-squares — only the first one
or two correspondences are used, per spec §6 A3.

Two things the merge now returns that the report will want (`mergeWithDiagnostics`):
`spreadM` per landmark — how far apart its separate placements were before averaging, which
is accumulated turn error made visible — and `unanchoredRouteIds`. `misclosureOf` in
`route_layout.dart` measures the same thing within a single route. These exist because spec
§10 asks for the schematic's error as a *measured result*, and Phase 4 records them against
real captures.

Also caught: `layout` read its start landmark from `steps.first` **before** sorting by
`seq`, so a route arriving in PostgREST's arbitrary order started from the wrong node.

---

## Phase 2 · A* and route synthesis (A4) — 1.5 days

The demo moment, and the least-specified part of the spec. The pathfinding is the easy half.

### 2a · Pathfinding

`lib/services/mapping/route_planner.dart`

```dart
List<String> findPath(FloorGraph graph, String fromLandmarkId, String toLandmarkId);
```

Textbook A*, heuristic = straight-line distance between laid-out positions. Tens of nodes;
no optimisation warranted. Cross-floor edges carry their real `distanceM`; the planar
heuristic underestimates them, which keeps it admissible.

### 2b · Path → `WalkRoute` synthesis

```dart
WalkRoute? planRoute(FloorGraph graph, List<WalkRoute> recorded, List<Landmark> landmarks,
                     {required String fromRoomId, required String toRoomId});
```

Three things the spec does not spell out:

1. **Room → landmark resolution.** `Landmark.roomId` is nullable and sparse. Resolve via
   matching `roomId`; return `null` cleanly when a room has no landmark, and make both the
   UI and Stream B handle that null rather than throw.

2. **Reversed legs.** A room-to-room path traverses recorded legs backwards. When it does,
   **negate `turnDeg`** — and the stored `instruction` is now false. "Turn right; the
   stairwell is at the end of the corridor" is wrong walking the other way. Synthesise
   replacement text from `turnDeg` plus the destination landmark's `displayName`. Keep the
   recorded instruction only for legs traversed forward.

3. **Output shape.** Return a `WalkRoute` with resequenced `seq` and `stepsRecorded: null`
   — it is synthetic, and computed distance must never be presented as measured evidence.
   Stream B's `GuidanceBloc` then cannot tell a planned route from a recorded one, which is
   the entire point.

**Handshake — morning of Phase 2, not the end:** tell Stream B that `planRoute` returns a
plain `WalkRoute` and that `stepsRecorded == null` marks it synthetic. That is the only
contract addition beyond spec §5. Learned late, they will have hardcoded around it.

**Accept:** the spec's own check — seed a second route (entrance → 209) alongside the
Reading Hall one; `planRoute` between two rooms returns a path nobody walked, with sane
turns and instructions in both directions. Unit test, no device.

### Outcome

Done — `lib/services/mapping/route_planner.dart`, 24 tests. The demo moment works:
`planBetweenRooms(from: 'reading-hall', to: 'study-2b')` returns Reading Hall → directory
board → Study Room 2B, spliced from the tail of one recording and the reversed tail of
another.

Delivered as a `RoutePlanner` class rather than free functions — the Bloc holds one per
building, because merging is not free and the graph does not change while the screen is
open. `RoutePlanner.from(routes, landmarks)` merges and is ready to plan.

The second seeded route is **entrance → Study Room 2B**, not 209: `study-2b` is a room the
mock building repository actually has, and 209 is not. It shares its first four legs with
the Reading Hall route and diverges at the floor 2 directory board, which is exactly the
branch A* needs. New migration `20260805090000_seed_study_room_route.sql`; mirrored in the
mock.

**One correction to the plan's design.** The plan said reversed legs "negate `turnDeg`".
That is not enough. A recorded `turnDeg` is relative to *the leg that preceded it in that
recording*; splice legs from two different walks together and the stored angle refers to an
approach the user never made, in either direction. Turns are therefore **recomputed from the
merged geometry** — bearing in, bearing out, snapped to the vocabulary the capture UI offers
(0, ±45, ±90, ±135, 180) because "turn 73 degrees" is useless spoken aloud.

The rule for wording follows from the same fact: a recorded instruction is replayed verbatim
**only when the user arrives the way its author did** (same predecessor landmark).
Otherwise it is rebuilt from the recomputed turn, the destination's `displayName`, and the
walked distance. A human sentence about a real corridor beats a generated one, so the
recorded text is preferred wherever it is still true — and a false instruction spoken to
somebody who cannot see the corridor is worse than silence.

Other decisions worth knowing:
- **Distances are always the walked ones**, never the schematic's geometry. Layout is
  derived from distances, so reading them back off the plan would be circular.
- Floor changes get no turn — the two nodes share a point, so there is no direction to
  measure — and are described ("Take the stairs to the floor 2 landing").
- Where several contributors recorded one leg, the most-verified route's wording wins.
- A 30-line binary heap is inlined rather than adding `package:collection`: spec §8 lists
  `pubspec.yaml` as shared with Stream B, and this is cheaper than that merge conflict.
- `WalkRoute.isPlanned` (id prefix `planned:`) marks a synthesised route.

**Stream B handshake:** `planBetweenRooms` / `planBetweenLandmarks` / `planToRoom` all
return a plain `WalkRoute`, so `GuidanceBloc` cannot tell a planned route from a recorded
one. `stepsRecorded == null` on every leg marks it synthetic — never count a computed
distance as measured evidence in the evaluation chapter.

---

## Phase 3 · `FloorPlanPainter` and map screen (A5) — 2.5 days

**Deliver into the existing screen.** `/building/:id/navigate` →
`lib/ui/pages/navigate/navigation_page.dart` already exists with a static mock
`_FloorPlanPainter` and `_InstructionCard`, laid out to Figma 7:265 and already
theme-aware. Its own doc comment says Phase 2 wires the real floor plan and A* route into
that exact layout. Do that.

**Do not create `lib/ui/pages/map/`.** `lib/ui/pages/maps/` already exists and is the
saved-buildings tab; a near-identical sibling will be confused with it forever.

### 3a · `FloorPlanPainter`

`lib/ui/widgets/floor_plan_painter.dart` — promote the private mock out of
`navigation_page.dart`, made data-driven.

Takes a `FloorGraph`, the active `floorId`, an optional highlighted `WalkRoute`, and the
four theme colours the mock already threads through (`brightness`, `hairline`, `onSurface`,
`muted`). Follow `radar_painter.dart`: public `StatelessWidget` wrapper, private painter,
a real `shouldRepaint`.

**Viewport fitting is the actual difficulty.** The graph is in metres with arbitrary extent
and origin. Compute the bounding box of nodes on the active floor and fit to canvas with
padding, preserving aspect ratio. Build it as a separate testable function, not inline in
`paint()` — get it wrong and everything renders off-screen with no clue why.

Draw order: corridor edges (hairline) → route highlight (coral `#FB5B47`, the single
accent) → landmark nodes glyphed by `LandmarkKind` → labels from `displayName`.
No gradients.

### 3b · Bloc

`lib/features/routing/bloc/floor_plan_{bloc,event,state}.dart`, following `MapsBloc`
exactly — status enum, `OperationFailure` caught, `copyWith` state.

Loads landmarks and routes for the building, merges to a `FloorGraph`, holds active floor
and selected destination, calls `planRoute` when the destination changes. Register in
`injection_container.dart` — **keep that edit to one commit on its own**, per spec §8.

### 3c · Screen wiring

`NavigationPage` gets a `BlocBuilder` for loading / error / data, a floor switcher (the
seed spans ground and floor 2, so this is exercised immediately), and `_InstructionCard`
fed from the real current `RouteStep`.

**Accept:** the seeded route renders as a recognisable corridor schematic in **light and
dark**; switching floors moves between planes; a synthesised A* route highlights correctly.
Verified by running on device — this is the screen the examiners see.

### Outcome

Code complete: `lib/services/mapping/plan_viewport.dart`,
`lib/ui/widgets/floor_plan_painter.dart`, `lib/features/routing/bloc/floor_plan_*.dart`,
and `navigation_page.dart` rebuilt against real data. 30 tests (11 viewport, 15 bloc,
4 widget), 242 in the suite, analyzer clean.

**The on-device check has not been done** — no Android device was attached when this was
written, and `flutter devices` offered only Windows and Edge. The widget tests do paint the
seeded plan through `AppTheme.light` and `AppTheme.dark` and assert no exception, but that
is not the same as looking at it. Run it on the Infinix before calling A5 finished.

Delivered into the existing `/building/:id/navigate` screen as planned. Three things the
plan did not anticipate:

1. **`BuildingFloor` had no `id`.** Landmarks reference `floor_id`, but the Dart model
   exposed only `label` and `rooms`, so there was nothing to join on and the floor switcher
   could only have shown raw uuids. Added `id` (defaulted to `''` so nothing else breaks),
   selected it in `SupabaseBuildingRepository.floorsOf`, and gave the mock floors ids
   matching the seeded landmarks.
2. **Nothing could say where the user is.** Without it the map cannot follow a walk and
   "route from here" is impossible. Added `FloorPlanPositionChanged(landmarkId)` — the map
   follows the user up the stairs, and any route planned afterwards starts from where they
   now are. **This is Stream B's hook:** feed it every OCR landmark confirmation.
3. **The room tile opened navigation without saying which room.** The destination now
   travels as a `?room=` query parameter, so a deep link to a specific door survives a cold
   start.

Smaller decisions:
- Landmark **shape** carries its kind (square for stairs/lift, ringed circle for doors,
  small circle for junctions/signs), not colour alone — the plan stays readable in
  greyscale and for anyone who cannot separate coral from grey.
- Corridors are drawn as a bordered band, all casings before all fills, so a junction does
  not get a seam cut across it.
- The floor switcher lists **only floors that carry landmarks**. The library declares four
  storeys and two have been walked; four tabs would read as a broken map rather than an
  incomplete one.
- Empty states are distinguished: "nobody has walked this building yet" is not the same
  claim as "you appear to be offline", and the user can act on one of them.
- A planned route is badged **"Estimated route"** on the map. It was spliced from other
  people's walks and nobody has verified it end to end.

Testing note: `testWidgets` runs in a fake-async zone where the mock repository's latency
never elapses, so bloc state is loaded once in `setUpAll` outside it. `google_fonts` also
needs `allowRuntimeFetching = false` or the suite hangs on an HTTP fetch.

---

## Phase 4 · Field-data hardening and handoff — 1 day

Runs during the spec §9 days 10–12 KNUST capture. Real routes break assumptions the seed
does not.

- **Degenerate graphs:** single-leg routes; a destination landmark with no `roomId`;
  disconnected components after merge (two routes sharing nothing). Each must render or
  fail gracefully, never throw.
- **Scale sanity:** real legs of 2 m and 40 m in one building — check viewport fitting does
  not collapse.
- **Merge drift:** once two real routes share a landmark, measure how badly the loop fails
  to close. **Screenshot it and record the misclosure in metres.** That is a spec §10
  evaluation result, not a bug — Deliverable 6 needs numbers about the schematic's honesty.
- Support Stream B integrating `planRoute` into `GuidanceBloc`.

**Accept:** two independently captured KNUST routes merge and render; the room-to-room A*
case works on real data; misclosure measured and written down.

### Outcome — partial

The code-side hardening is done: `test/floor_plan_hardening_test.dart`, 14 tests covering
single-leg routes, a leg from a landmark to itself, zero-distance legs, duplicate `seq`,
2 m and 40 m legs sharing one plan, a building-sized plan, a landmark recorded but never
walked to, missing landmark entries, disconnected wings, wildly disagreeing recordings, and
determinism across PostgREST's arbitrary row order. All passed first time — the layout and
merge were already robust — so the value here was the widget tests, which found two real
bugs:

1. **A route somebody actually walked was badged "Estimated route".** `planToRoom` always
   went through A* and synthesis, so a path exactly matching a recording came back as a
   reconstruction — throwing away its verification count and the contributor's step counts.
   `RoutePlanner` now hands back the recording itself when one covers the whole path.
2. **`total_distance_m` is a denormalised column** and nothing stops a client writing a
   route whose stored total disagrees with the legs it also wrote. The legs are the
   evidence, so they now win; otherwise guidance announces a distance remaining that its own
   steps never add up to.

Still outstanding, and it needs the building:

- **The KNUST field capture itself.** Two independently captured routes, merged and
  rendered.
- **Merge misclosure on real data.** `mergeWithDiagnostics` returns `spreadM` per landmark
  and `worstSpreadM`, and `misclosureOf` measures it within a single route; the bloc already
  surfaces `worstSpreadM`. Nobody has pointed them at a real walk yet. Screenshot the result
  and record the number in metres — spec §10 wants it as a result, not an excuse.
- **The on-device run of the map screen** (see Phase 3).

### The demo moment had no route through the UI

Found after the phase was otherwise finished, and worth its own note. `planBetweenRooms`
worked and was well tested, but **nothing in the app could reach it**: the only way to set a
destination was the `?room=` deep link from a room tile, which always plans from the
entrance, and no widget dispatched `FloorPlanDestinationSelected` or
`FloorPlanPositionChanged`. Spec §6 A4 says of the room-to-room case "this is the demo
moment — make sure it works", and an examiner could not have seen it.

Added:
- **A destination picker** in the header — rooms grouped by floor, rooms with no recorded
  landmark greyed out rather than accepting the tap and then explaining why nothing
  happened. Plus a clear-route control.
- **Tap a landmark to say "I am here."** In the field that claim comes from OCR reading the
  sign; on a desk, or when the camera cannot see it, somebody has to be able to say it by
  hand. Both feed the same `FloorPlanPositionChanged`.

The full path now works and is covered end to end by
`test/navigation_page_test.dart` — open to the Reading Hall, switch to floor 2, tap the
Reading Hall door, ask for Study Room 2B, and get a two-leg route badged "Estimated route".

Three more bugs fell out of building it:

3. **The destination button overlaid the plan**, making every landmark beneath it
   untappable — and those taps are how the user says where they are. Moved into the header.
4. **The room list was truncated.** A default-height modal sheet with a lazily-built
   `ListView` left rooms below the fold unreachable and, because they were never built,
   invisible to tests too. Now `isScrollControlled` with a bounded height.
5. `PlanViewport` had no value equality, so `shouldRepaint` compared identity and the plan
   repainted on every frame. It is now `Equatable`, and hit testing shares exactly the
   projection that was drawn rather than recomputing its own.

### Stream B handoff — ready

- `RoutePlanner.planBetweenRooms` / `planToRoom` / `planBetweenLandmarks` return a plain
  `WalkRoute`. `GuidanceBloc` cannot tell planned from recorded, which is the point.
- `WalkRoute.isPlanned` and `stepsRecorded == null` mark a synthetic route. Never count a
  computed distance as measured evidence.
- `FloorPlanPositionChanged(landmarkId)` is the hook: feed it every OCR landmark
  confirmation and the map follows the user, including up the stairs, and any route planned
  afterwards starts from where they now are.
- `Landmark.matchesExactly` and `Landmark.normalise` already exist for the OCR matcher;
  fuzzy tolerance belongs in Stream B's matcher so it can be tuned in one place.

---

## Shared files — merge-conflict discipline

Per spec §8. Stream A touches only:

- `lib/services/injection_container.dart` (Phase 3b) — commit alone
- `lib/core/routes/app_routes.dart` / `lib/router/app_router.dart` — possibly not at all,
  since `/building/:id/navigate` already exists

No `pubspec.yaml` changes, no `AndroidManifest.xml` changes. Conflict risk with Stream B is
near zero if the DI registration is committed by itself.

---

## Decisions log

| Decision | Rationale |
|---|---|
| Geometry types are `Equatable`, not freezed | Derived geometry, never persisted; freezed rule covers repository models |
| Per-floor layout planes, stairs carry `(x, y)` | Otherwise floor-2 landmarks land in ground-floor corridors |
| Reversed legs negate `turnDeg` and re-synthesise instruction | The recorded sentence is false in the other direction |
| `stepsRecorded: null` marks a synthetic route | Computed distance must never read as measured evidence |
| Deliver A5 into existing `navigation_page.dart` | Route, layout and theming already exist; a parallel `map/` dir would shadow `maps/` |
| No least-squares loop closure | Spec §6 A3 — label the artifact a schematic, because it is one |
| Align route frames before averaging | Averaging only works while every route shares an origin; one starting elsewhere drags shared landmarks out of place |
| Recompute turns from geometry, not by negating | A recorded turn is relative to *its* predecessor leg; spliced paths have a different one |
| Replay a recorded instruction only on a matching approach | The sentence is false from any other direction, and a false instruction is worse than silence |
| Return the recording when it covers the whole path | Preserves verification count and step counts; a real walk is not an "estimated route" |
| Legs beat the stored `total_distance_m` | The column is denormalised and can drift from the legs written beside it |
| Landmark shape carries kind, not colour alone | Readable in greyscale and without colour discrimination |
| A position change on the route advances it; off the route replans | Progress and deviation are different events; conflating them narrates a walk the user has left |
| Voice lives in the Bloc, driven by `onChange` | Every handler can move the user onto a new leg; wiring speech to some of them goes quiet exactly when the route changes |
| The spoken line and the card's semantics label are one getter | Two sources for the same sentence drift, and the screen reader gets the stale one |
| Card is a `liveRegion` only while the voice is muted | With both on, TalkBack and the TTS engine read the same instruction over each other |
| Landmarks published via `semanticsBuilder` | A `CustomPaint` is one opaque box otherwise, and tapping a landmark is the screen's only input |

---

## Verification status

| Check | State |
|---|---|
| `flutter test` | 287 passing |
| `flutter analyze lib test` | clean |
| Tap targets (`androidTapTargetGuideline`, iOS) | pass — asserted in test |
| Text contrast (`textContrastGuideline`) | pass — asserted in test |
| Accessibility pass on device | **pending** — phone is PIN-locked |
| Android debug build + install | done — Infinix X657C, API 29 |
| Map screen on device, light theme | done |
| Map screen on device, dark theme | done |
| Room-to-room demo on device | done — against mock **and** real Supabase |
| Schema, RLS, `save_route` on the live project | done |
| Seeded data read back through the app | done |
| KNUST field capture | **not done** — needs the building |

Nothing in this work has been committed.

### Against the live Supabase project

`supabase/setup_all.sql` was run in the SQL editor, real credentials went into `.env`, and
the whole chain was re-driven on the device with the mock repositories out of the picture.
Everything the mock produced, the real backend reproduces: Home lists the eight seeded
buildings, KNUST Library floor 2 offers Help Desk / Reading Hall / Study Room 2B, and the
Reading Hall route draws the same ground-floor L with "Leg 1 of 5 · 12 m · 53 m to go".

The merge is visible on real rows: floor 2 shows both recorded walks on one plane, sharing
the landing and the directory board, with the inactive branch to the Reading Hall door drawn
neutral and the active one to Study Room 2B in coral. That is A3 doing its job on data that
travelled through PostgREST rather than a Dart constant.

The destination picker also greys out the rooms no landmark reaches — the ground-floor rooms
and Help Desk — which is the reachability check reading the live graph.

**One real bug only this run could find.** `_onPositionChanged` moved the marker and followed
the user between floors, but never reconsidered the route. Standing at the Reading Hall door
while heading to Study Room 2B, the screen still said "Leg 1 of 5 · past the entrance desk" —
describing a walk from the front door the user was nowhere near. Fixed by distinguishing the
two cases: a landmark *on* the current route is progress and keeps the recording, so
`currentStep` advances as before; a landmark off it means the route no longer starts where
the user stands, so it is replanned from there. If nothing connects the new position to the
destination, the route is dropped and the screen says so rather than drawing a plan that
begins somewhere the user is not.

With that fixed the spec's demo moment works end to end on live data: tapping the Reading
Hall door replans to "Estimated route · 13 m", "Leg 1 of 2 · Continue straight for about
6 metres to Floor 2 directory board", over legs taken from two different recorded walks.

---

## Accessibility and interaction pass

An audit of the UI found the visual system in good shape — token discipline held (seven
hardcoded colours and one hardcoded spacing across 27 files), light and dark genuinely
built rather than bolted on. The gap was behavioural, and specific to what this app claims
to be: thirteen `Semantics` usages in the whole codebase, no haptics anywhere, and the
navigation screen rendering an instruction it never spoke while `SpeechService` sat wired
up and idle. A wayfinding aid for blind users that only writes its directions down is not
finished, however well it draws.

**Voice.** `FloorPlanBloc` now speaks each leg as it becomes current, driven from
`onChange` — every handler can move the user onto a different leg, so guidance hung off
individual handlers would go silent exactly when the route changed under them. It speaks
once per leg, not per rebuild: switching floors or redrawing the plan says nothing. Muting
stops mid-sentence; unmuting re-speaks the leg the user is on rather than leaving them in
silence until the next landmark. Arrival is announced as arrival, not as another leg.

Instructions are completed rather than padded: a contributor's recorded sentence ("Straight
ahead, past the entrance desk") gains "12 metres", while a synthesised one already carrying
its distance does not have it read out twice.

**The plan is no longer silent.** `_FloorPlanPainter` publishes every landmark through
`semanticsBuilder`, labelled with its name, kind and role in the journey — "Help desk,
junction, on your route". Each node is activatable, so "I am here", the only input this
screen has, no longer requires a sighted aim at a 6px dot. Semantics rebuild on geometry
and labels only, never on the animation frame.

**Touch targets.** Every control is 48dp. The floor switcher was 44 and the header buttons
42; both are now asserted by `meetsGuideline(androidTapTargetGuideline)` rather than
eyeballed, alongside iOS targets and text contrast.

**Haptics.** Landmark taps, floor changes and toggles click; choosing a destination is a
medium impact; arrival is a heavy one. A 6px target needs to confirm itself — without it a
miss and a hit feel identical until the plan redraws.

**Motion.** Legs cross-fade and slide, the turn arrow scales between directions, the
progress bar tweens rather than jumping, the floor pill animates its selection, and the
"you are here" halo ripples out and settles when the user moves. All of it is finite and
one-shot; the halo respects `MediaQuery.disableAnimations`, and nothing loops, so no
repaint runs forever and no `pumpAndSettle` can hang on it.

### On-device run — Infinix X657C, API 29

The device the spec names as the project's blocker for ARCore runs this fine, which is
the point: none of this needs ARCore.

Verified by looking at it: Explore → KNUST Library → floor 2 → Reading Hall opens the plan
and draws the ground floor as an L — Main entrance, 12 m up to the Help desk, 18 m right to
the Ground floor stairwell — with the route in coral, the position halo on the entrance, the
G/2 floor switcher showing exactly the two walked floors, and the card reading "Leg 1 of 5 ·
Straight ahead, past the entrance desk · 12 m · 53 m to go". That is the seeded route,
correct end to end, from the turtle layout through to the instruction text.

**`.env` was the first thing that had to change.** It had been copied from `.env.example`,
whose placeholder values are non-empty, so `AppConfig.hasSupabase` was true and the app
pointed at `https://your-project-ref.supabase.co`. Blanked the keys so the Mock
repositories — and the seeded routes — are used.

Two defects only a real screen showed, both now fixed:

6. **Landmark labels ran off both edges.** `PlanViewport` fits the *nodes*; a label is up to
   110 px wide centred on one, so "Main entrance" and "Ground floor stairwell" — landmarks
   that by their nature sit at the ends of a corridor — were clipped. Labels are now nudged
   back inside the canvas instead of being centred blindly.
7. **The header was crushed to "KNU…" / "Ground…".** The labelled "Change destination" pill
   ate the width on a 360 dp screen. It is now an icon button matching the back button, with
   the label carried in `Semantics` — which is the audience that matters most here anyway.

Both fixes were then confirmed on the device, in dark theme as well as light: the building
name reads in full and no label is clipped.

**The demo moment, verified on the phone.** Standing at the Reading Hall door — set by
tapping the node, the same event OCR will fire — asking for Study Room 2B returns
Reading Hall door → directory board → Study Room 2B door, badged **"Estimated route · 13 m"**,
with leg 1 reading *"Continue straight for about 6 metres to Floor 2 directory board"*. That
sentence is synthesised: the recording says "the Reading Hall is the second door on your
right", which is false walked the other way. A journey nobody recorded, assembled from the
tails of two separate walks.

The destination sheet behaves as designed too — "From Reading Hall door" as the header, and
every room with no recorded landmark (all three ground-floor rooms, plus Help Desk) greyed
out rather than accepting a tap it cannot honour.

One more defect found by looking at it, now fixed:

8. **Standing at the destination, the card read "Leg 1 of 5".** `currentStep` matched the
   user's landmark against each leg's *start*, and the final door starts no leg, so it fell
   through to the first — telling somebody who had arrived to set off again. It now falls
   back to the leg that *ends* there, and the card shows "Arrived · Reading Hall door" with
   a check and a full progress bar (`FloorPlanState.hasArrived`).
