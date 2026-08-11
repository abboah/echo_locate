# Stream merge — handoff

**Date:** 11 August 2026
**Branch:** `v2-sound` (merge commit `fee4f77`, merging `main` into it)
**Status:** merge resolved, `flutter analyze` clean over `lib` and `test`, **363 tests pass**
(up from 350 — 13 added). PR not yet opened; see [Open items](#open-items).

---

## 1. What this was

`landmark-navigation-spec.md` split the work into Stream A (2D map + routing) and Stream B
(capture + guidance). Both streams **independently built the mapping layer**, so the branches
had two different implementations of `FloorGraph`, `route_layout`, `RoutePlanner` and the
floor-plan painter. This merge reconciles them into one system and rewrites the spec to match.

- `main` carried the complete Stream B (capture, guidance, OCR, step service, stride
  calibration, plan trace) **plus** a leaner Stream A.
- `v2-sound` carried a richer Stream A (bigger planner and painter, `PlanViewport`,
  `FloorPlanBloc` with its own voice guidance) and no Stream B.

14 files conflicted, 4 of them whole-file add/add.

## 2. The resolution rule

**Keep the interfaces the rest of the app already speaks; port the better behaviour onto
them.** `main` was the base, because its Stream B was unopposed and its `GuidanceBloc` (435
lines + 647 lines of tests) is coupled to `PlannedRoute`/`PlannedLeg` and `FloorGraph.metric`.

| Kept from `main` | Ported in from `v2-sound` |
|---|---|
| `PlannedRoute` / `PlannedLeg` as guidance's currency | multi-floor `MapNode.floorId`, `nodesOn`, `edgesOn`, `floorIds` |
| Per-direction wording on `GraphEdge`; `metric`; `fromPlan(TracedPlan)` | `mergeWithDiagnostics` → `MergeResult.spreadM` (§10 evidence) |
| `FloorMapBloc` as the map screen's bloc | geometric turn recomputation + approach-matched wording |
| `TracedPlan` / plan-trace integration | `FloorPlanView` + semantics + hit testing; `PlanViewport`; `misclosureOf` |

## 3. What changed, file by file

### `lib/services/mapping/map_node.dart`
Now holds **`MapNode` only** (it previously also carried `MapEdge` and a second `FloorGraph`).
Gains `floorId`. `MapEdge` is gone — `GraphEdge` in `floor_graph.dart` is the single edge type,
because it carries per-direction wording that `MapEdge` did not.

### `lib/services/mapping/route_layout.dart`
`layout(route, [landmarks])` — landmarks are optional and supply each node's floor.

**A floor change consumes no horizontal distance.** The climb is real metres (guidance quotes
them) but it is vertical; spending it on the plane pushed every floor-2 landmark eight metres
down a ground-floor corridor. The landing is now placed directly above the stairwell.

Also adds `misclosureOf(nodes)` — how far a walked loop fails to close, for §10.

### `lib/services/mapping/floor_graph.dart`
`GraphEdge` / `Neighbour` / `FloorGraph` from `main`, plus:

- `floorIds`, `nodesOn(floorId)`, `edgesOn(floorId)`. A stairs edge has one end on each plane
  and belongs to **neither** — drawing it would imply a corridor that is not there.
- `mergeWithDiagnostics(routes, [landmarks])` → `MergeResult { graph, spreadM,
  unanchoredRouteIds }`. `spreadM` is how far apart a landmark's separate placements were
  before averaging.
- Merge ordering is now **most-overlapping-first** (from `v2-sound`), and disconnected routes
  are still **parked clear** of what is drawn (from `main` — `v2-sound` stacked them at the
  origin).

> ⚠️ **Bug fixed during the merge.** My first pass keyed layout frames by `route.id`, which
> silently dropped routes sharing an id — it broke a guidance test whose fixture used `r1`
> twice. Frames are now indexed positionally. Covered by
> *"routes sharing an id are all kept"*.

### `lib/services/mapping/route_planner.dart`
Still `const RoutePlanner()` and still returns `PlannedRoute`, so **`GuidanceBloc` is
untouched**. `plan()` gains two optional params, `landmarks` and `recorded`. Two behaviour
changes ported from `v2-sound`:

1. **Turns are recomputed** from the merged geometry. A recorded `turnDeg` is relative to the
   leg that preceded it *in that recording*; splicing two walks makes it refer to an approach
   the user never made. Walking a recorded corner backwards now inverts it instead of
   steering into a wall.
2. **Wording is dropped when the approach differs.** "Turn right; the stairwell is at the
   end" is false approached from elsewhere. Requires `recorded:` to be passed — without it
   the edge wording is taken at face value, which is right whenever the route follows one
   contributor's walk (and is what guidance's mid-walk replan does).

**Not ported:** `v2-sound`'s instruction *synthesis*. A leg nobody phrased stays `null` and
`GuidanceBloc._legSentence` composes the neutral sentence — it is the only place that knows
whether a step count can be promised.

### `lib/ui/widgets/floor_plan_painter.dart`
`v2-sound`'s `FloorPlanView` + `_FloorPlanPainter`, retyped to `GraphEdge` and `PlannedRoute`.
Caller filters by floor (`graph.nodesOn` / `edgesOn`), so the painter stays dumb.

Why this one won: per-kind landmark shapes (readable in greyscale), corridors as bordered
bands, label collision handling, a "you are here" ripple, tap hit testing — and
**`semanticsBuilder`**, which publishes every landmark as a node naming it, its kind and its
role in the journey. Without it the plan is one unlabelled box to a screen reader, and
tapping a landmark is the one manual input the screen depends on.

### `lib/features/routing/bloc/floor_map_bloc.dart` + state/event
`FloorMapBloc` survives and gains:

- `floors`, `activeFloorId`, `worstSpreadM` on the state; `mappedFloorIds`, `labelForFloor`,
  `nodesOnActiveFloor`, `edgesOnActiveFloor`, `landmarksById` as derived getters.
- `FloorMapFloorSelected` event.
- `FloorMapRequested(buildingId, destinationRoomId:)` — the deep link from
  `building_detail_page` ("navigate to this room") now preselects the destination and plans
  on open instead of asking the user to pick what they just tapped.
- The planner call passes `landmarks` and `routes` so approach-matching works.

### Removed
`floor_plan_bloc.dart` / `_event` / `_state` and their three test files. Its voice guidance
existed only because `GuidanceBloc` did not yet exist on that branch; `GuidanceBloc` is
strictly more capable (steps, OCR, obstacles, recovery ladder). Its plan-viewing job is
`FloorMapBloc`'s. DI registration removed.

### `lib/features/buildings/building_repository.dart`
Mock `floorsOf` returns `floor-g` / `floor-$i` — **the same ids `MockRouteRepository`'s
landmarks carry**. `main`'s `$buildingId-floor-g` disagreed with them, which left the floor
switcher labelling planes with raw ids. (The real seed migration resolves actual uuids from
the `floors` table, so this only ever mattered for the mocks.)

### `build.yaml`, `lib/core/models/building.dart`
Comment-only conflicts; both sides' reasoning merged into one block.

## 4. Spec rewrite — `landmark-navigation-spec.md`

- Header notes the streams merged 11 Aug 2026.
- **§5** "The contract between the two streams" → "The seam between map and guidance". Records
  that the split served its purpose, and that the map and the voice must stay *the same graph
  read two ways*. Documents the two seeded library routes and why **two** matters (they share
  early legs and diverge on floor 2 — that overlap is what A\* needs).
- **§6/§7** no longer "Stream A"/"Stream B". §6 A2–A5 rewritten to describe what was built
  (floor-aware layout, merge diagnostics, turn recomputation, semantics).
- **§8** "Shared files — merge conflict risk" → "How the two halves were reconciled", with the
  kept/ported table and the two deliberate drops.
- **§9** marks day 10 as the merge point.
- **§10** gains a **Schematic drift** row (`spreadM` + `misclosureOf`).

## 5. Tests

13 added, all passing. New coverage sits in:

- `test/route_planner_test.dart` — two new groups: *turns are recomputed from the merged
  geometry* (corner measured from the approach actually taken; first leg has no turn;
  backwards inverts; floor change is described not turned into) and *wording only survives
  where it is still true*.
- `test/floor_graph_test.dart` — *the merge reports its own error* (spread, unanchored routes,
  duplicate ids) and *floors* (climb does not displace the plane; each plane carries only its
  own nodes and corridors).
- `test/floor_plan_painter_test.dart` — rewritten for `FloorPlanView`: semantics tree contents,
  destination announced on its own floor, tap hit testing.
- `test/navigation_page_test.dart` — rewritten for `FloorMapBloc`: floor switcher, plane
  redraw, room deep link.

⚠️ `find.bySemanticsLabel` does **not** reach `CustomPainterSemantics` nodes — they hang off
the render object, not a widget. Use the `semanticsLabels(tester)` helper in
`floor_plan_painter_test.dart`, which walks the tree from `tester.getSemantics(...)`.

Also updated: `test/route_repository_test.dart` expected one seeded library route with 4 legs;
there are now **two** routes and the Reading Hall one has **5** legs.

## 6. Open items

1. **The PR is not open.** `gh` 2.97.0 is installed but not authenticated. Run
   `gh auth login`, then:
   ```
   gh pr create --base main --head v2-sound \
     --title "Combine the map and guidance streams" --body-file docs/stream-merge-handoff.md
   ```
   The push of `v2-sound` first failed with `HTTP 408` (large push); `http.postBuffer` and
   `http.version HTTP/1.1` are now set locally. Confirm `git push origin v2-sound` landed.
2. **Nothing has run on a device.** Everything above is verified by `flutter analyze` and the
   unit/widget suite only. `CLAUDE.md` requires camera/mic/step work to be checked on a real
   Android device — the floor switcher, the semantics tree and the room deep link all want a
   pass on hardware.
3. **`worstSpreadM` has never seen real capture data.** The map only shows the note above
   1.5 m (`_spreadWorthMentioningM` in `navigation_page.dart`); that threshold is a guess
   until §10's field runs produce numbers.
4. **`unanchoredRouteIds` is computed but unused.** The painter does not yet distinguish a
   parked, unconnected wing from the connected map. Worth drawing differently before anyone
   captures a building with a detached wing.
5. `tool/analyze_correlation.dart` and `tool/analyze_wav.dart` still emit 8 `avoid_print`
   infos. Pre-existing on both branches, untouched here.
