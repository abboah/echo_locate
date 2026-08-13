# Reading the plan, and knowing where you are — design

**Date:** 13 August 2026
**Status:** design agreed, not yet implemented
**Fixture:** `test/fixtures/plans/college_of_science_ff.jpg` — College of Science, first floor

---

## 1. Why

Three faults, one root.

**The map has no walkable path.** `FloorGraph.fromPlan` builds each edge as a straight
segment with `distanceM = from.distanceTo(to)` (`floor_graph.dart:399`). An edge *is* a
straight line, so joining the entrance to FF 12 asserts a corridor through every wall
between them. A\* then optimises over crow-flies distances: it returns routes nobody can
walk and quotes distances shorter than the walk. The painter faithfully draws that straight
band, which is why a drawn route does not follow the building.

**The phone does not know where the user is.** There is no gyroscope, magnetometer or
heading anywhere in `services/mapping`, `features/guidance` or `services/motion` —
`sensors_plus` is used only by the sonar demos. Step count is the sole motion input, so at a
junction the app cannot tell which branch was taken. Position is known only when OCR reads a
sign, and guessed in between.

**Mapping is all manual.** Every room number is typed by hand, though the plan already
carries them.

Underneath all three: *the map has no notion of a walkable path, and the phone has no notion
of where along one it is.*

## 2. What the fixture taught us

The design was revised after photographing a real board. Recorded here because each point
contradicts something that seemed reasonable in the abstract.

**The key is colour-coded, not text-coded.** The legend maps *swatches* to meanings
(Staircase, Lecture Hall, Office, Laboratory, Auditorium, Control Room, Common Room, Library,
Ibistek Boardroom, Washroom, Elevator, Location, Optometry Clinic). Nothing on the drawing
says "library" — FF 13 is a library *because it is blue*. No amount of text parsing connects
a room to its category; the fill colour must be sampled.

**Room labels are codes, not numbers.** `FF 1`–`FF 24`. A numeric filter would find nothing.
The prefix carries the floor: `GF` ground, `FF` first, `SF` second, `TF` third.

**The "LOCATION" pin is printed on the drawing.** It is a legend entry, and it marks where
the board itself hangs. Whoever is reading this sign is standing there.

**No scale bar and no dimensions.** `metresPerUnit` cannot be derived from this plan. It
stays null, `FloorGraph.metric` stays false, and **guidance does not regain step counts.**
An earlier claim that it would was wrong for this building.

**Glare is normal, not exceptional.** The board is behind gloss; window reflection washes out
the right-hand third — exactly where the legend sits. The most important text on the plan is
the worst lit. Any flow assuming one clean capture is already broken.

## 3. Decisions

| Decision | Choice | Why not the alternative |
|---|---|---|
| Corridor geometry | **Spine-first tracing.** Contributor traces corridor centrelines; rooms attach to them. | Adding corner nodes conflates geometry with places. Auto-skeletonising the image is research-grade and fails silently into a plausible-looking wrong map. |
| Node model | **Split waypoint from landmark.** | One node type doing both jobs is why corners would pollute the landmark picker, the OCR matcher and spoken guidance. |
| Localisation | **Steps + gyro turns, map-matched to the corridor polyline, reset by OCR reads.** | Landmark-only cannot detect a wrong turning until a sign proves it. A particle filter is more accurate but too much to build, tune and explain on this deadline. |
| Room categories | **Confirm the palette once per plan.** | Fully automatic propagates a glare-misread category name to every room of that colour. Manual is ~24 selections per floor and gets rushed. |
| Floor assignment | **Derived from the label prefix.** | A floor picker asks for what the plan already states. |

## 4. Data model

Three concepts where there is currently one.

- **Waypoint** — geometry only: `x`, `y`, `floorId`. No name. Never spoken, never listed in a
  picker, invisible to OCR matching.
- **Landmark** — a place, unchanged from today: `labelText`, `displayName`, `kind`, `roomId`.
  Either sits on the spine or hangs off it by a short stub.
- **Corridor** — a polyline of waypoints. Its length is **arc length**, not crow-flies.

A\* runs over the same graph. The Euclidean heuristic stays admissible because a polyline is
never shorter than its chord, so the search stays correct and `GuidanceBloc` keeps taking
`PlannedRoute` unchanged. `PlannedLeg` gains the polyline so the route can be drawn along the
hallway.

`LandmarkKind` needs widening — there is no toilet, exit, lobby, office, hall or lift-lobby
today, and `landmarks.kind` carries a **CHECK constraint** pinned to the current six, so this
is a migration rather than an enum edit. `LandmarkKind.fromName` already falls back to `sign`,
so older clients degrade rather than crash.

## 5. Capture flow

1. Photograph the plan; tap its four corners (deskew via homography).
2. **Separate close-up of the legend** when glare is detected over it, or on demand.
3. OCR everything. Read the legend's text and **sample its swatches**.
4. Detect room regions, sample each fill colour.
5. **Confirm the palette once** — the contributor okays ~13 colour→category pairs. Every room
   then inherits its category.
6. Floor comes from the label prefix. A plan whose labels disagree with the floor being traced
   is flagged as the wrong board.
7. Find the LOCATION pin — that becomes the default "you are here" for this building.
8. Trace the corridor spine. Rooms auto-attach to the nearest spine point.
9. Review, grouped by category, low-confidence colour matches flagged first.
10. Save. Repeat per floor; stairwell joins between `FF`/`SF` staircases are proposed
    automatically, with the manual join kept as override.

Colour matching runs in Lab space with a ΔE threshold, comparing room fills against legend
swatches **sampled from the same photograph**, so the warm colour cast cancels out. There are
two greens and two yellows on the fixture; ambiguous matches go to review rather than being
guessed. Confusing Auditorium with Optometry Clinic is precisely the silent-wrong-answer case.

## 6. Navigation flow

1. **Where you are** defaults to the LOCATION pin. The landmark picker becomes a correction,
   not a question, and a "read a sign" shortcut reuses the existing OCR and `LandmarkMatcher`.
2. **Where you are going** — landmark picker, or a room code matched by the same matcher.
3. A\* over the corridor graph. The route follows hallways; the quoted distance is the
   distance actually walked.
4. Guidance speaks each leg as it does today. Between signs, step count gives distance along
   the current corridor and the gyro resolves which branch was taken at a junction — relative
   rotation, which is reliable indoors where a magnetometer is not. Position is snapped to the
   polyline, so it can never sit inside a wall. Every OCR sign read resets drift to zero.

On an unscaled plan such as the fixture, leg lengths remain unitless: guidance names landmarks
and does not promise step counts.

## 7. Slices

Each ends on the device. No slice is done in a unit test, and each acceptance check is written
before its code.

| | Build | Device acceptance check |
|---|---|---|
| 1 | Capture → deskew → raw OCR list; glare detection; legend re-shoot | Photograph the real board: every room code and legend entry appears in the list |
| 2 | Swatch + fill sampling, palette confirmation, floor from prefix, review screen | Rooms come out categorised, not just numbered; junk excluded; wrong-floor board rejected |
| 3 | Waypoint/landmark split, spine tracing, auto-attach, migration, save | Reopen the building; corridor geometry persists |
| 4 | Corridor-following A\*, polyline on `PlannedLeg`, painter draws it | Pick two rooms: the drawn line bends round corners and the distance is plausible |
| 5 | Turn detection, map matching, OCR reset | Walk it: position advances along the corridor, the turn registers, a sign snaps it back |

Slice 4 is the first point the original complaint is visibly dead.

## 8. What this touches

`floor_graph.dart`, `route_planner.dart`, `route_layout.dart` and `floor_plan_painter.dart`
were rewritten in the stream merge (`docs/stream-merge-handoff.md`, merged 11 Aug). This design
lands on top of all four, so the author of that work should review this before implementation
starts.

Also needed: a migration on `traced_plans` and `save_traced_plan` for the waypoint/corridor
model, and a widening of the `landmarks.kind` CHECK constraint.

## 9. Risks

1. **Glare over the legend** is the highest-likelihood failure and it hits the highest-value
   text. Mitigated by the separate legend shot and the palette confirmation, not eliminated.
2. **Two greens and two yellows** on the fixture. ΔE thresholds are a guess until run against
   real captures; ambiguity must route to review rather than resolve by ordering.
3. **Room-region detection** assumes rooms are filled blocks bounded by lines — true on this
   fixture, unverified on hand-drawn or monochrome plans.
4. **Gyro turn detection** is untested here. Phone-in-pocket orientation, and a user who turns
   while standing still, are the cases that will need field tuning.
5. **No scale** means no step counts on this building. If a plan elsewhere carries a scale bar
   or a dimension, filling `metresPerUnit` is an opportunistic extra, not part of the flow.
6. **`GF`/`FF`/`SF`/`TF` is assumed.** A building using `1F`/`2F` needs the parser to accept
   both.
