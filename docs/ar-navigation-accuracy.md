# AR Navigation — what "accurate" means, and how to measure it

Written 2026-08-29, on the day an ARCore-capable device first became available.
Files referenced are current as of that date.

Until now every accuracy claim about the AR arrow has been an argument. This
file replaces the arguments with a protocol, a set of numbers to hit, and the
tooling to read those numbers off a walk.

---

## 0. What the walker is actually being shown

Two very different things, and telling them apart is the first thing to check on
any capture:

- **A registered route.** Dart solves one rotation and one translation between
  the floor plan and ARCore's world (`services/mapping/route_registration.dart`)
  and hands native the whole path in world coordinates. The arrow points at real
  corners. The log says `REGISTERED` and then `Route …/…m … off …m` once a
  second.
- **A dead-reckoned leg.** No geometry was available, so the arrow can only say
  "keep going the way you set off, for so many metres". The log says
  `Leg anchored:` and then `Walk …`.

**A capture with no `REGISTERED` line in it is not a test of AR navigation.** It
is a test of the fallback. Section 1 is about making sure you are testing the
thing you think you are.

---

## 1. Prerequisites — the data, before any of the code matters

### 1.1 A scaled plan, or a merged map in metres

Registration needs geometry in metres. There are two sources and they fail
differently:

| Route from | Geometry from | Fails when |
| --- | --- | --- |
| Room-navigate (`room_navigate_page`) | `RoomPlanBridge.routePathFrom` | `RoomPlan.metresPerUnit == null` — nobody measured the tracing |
| Building navigate (`navigation_page`) | `routePathThroughGraph` | the merged schematic cannot place the route (see below) |

For a traced plan, the scale comes from the manual span measurement in
`room_trace_bloc.dart`. **Measure the longest span available** — a corridor run,
not a doorway. The scale error is relative to the span you calibrate against, so
a 2 m doorway multiplies its own error across the whole building.

Check the scale before walking: pick two rooms at opposite ends of the plan,
read the distance the app computes, and hold a tape against it.

### 1.2 The building flow refuses more often than it accepts

`routePathThroughGraph` returns null — deliberately — for a route that changes
floor, one with a landmark the merge never placed, and one whose laid-out
geometry contradicts its own recorded distances. Each refusal is logged. If the
building flow is not registering, read the log before assuming ARCore is at
fault:

```
Graph geometry disagrees with the walk at leg 2: laid out 41.3m against a recorded 12.0m — not registering
```

That line means the merge parked the route in its own frame because it shares no
landmark with anything already placed. The fix is another recorded walk that
crosses it, not a change to the AR layer.

---

## 2. The three measurements

All three come out of one capture. Start it before the walk:

```sh
tool/walk_capture.sh start straight-20m
# … walk …
tool/walk_capture.sh stop
tool/walk_capture.sh report walk-captures/straight-20m-*.log --straight=20.0
```

### 2.1 Odometry scale — how much ARCore's metres are worth

Tape-measure a straight line, 20 m or longer. Walk it at a normal pace, phone
held as a user would hold it. The report compares net displacement between the
first and last `Pose` line against the truth you passed in.

> **Target: under 5% error.**

This is the floor under every distance the app quotes. Everything downstream —
the countdown in the walker's ear, where the ring lands — inherits it.

### 2.2 Yaw drift — how much the world turns under a walk

Walk a closed loop back to your exact starting point, ideally a rectangle round
a block of rooms. The report prints the gap between the first and last position
as a fraction of the perimeter.

```sh
tool/walk_capture.sh report walk-captures/loop-*.log --loop
```

> **Target: under 5% of the perimeter.**

This is the same measure `FloorGraph` reports for a recorded walk
(`MergeResult.spreadM`), and for the same reason: a schematic that admits its
error is a result, one that hides it is a lie.

### 2.3 Off-route — whether the building agrees with the app

Walk a real route on a real plan, normally, following the arrows. The report
reads `RegisteredRoute.offsetM` back off the `Route … off …m` lines.

> **Target: mean under 1.0 m, max under 2.5 m.**

2.5 m is `ArGuidanceCubit._registrationHoldsM` — the point at which the app stops
believing its own registration and re-solves. A walk that reaches it has already
failed, whatever the walker thought of it.

**This is the only honest number in the log.** Everything else reports what the
app believes; this reports whether the building agrees.

---

## 3. What to read in the report beyond the verdicts

```
--- Registration
  REGISTERED Registration(yaw 12deg, plan Offset(1.0, 2.0) = WorldPoint(0.10, 0.20), measured)
  RECENTRE at leg 0: 0.62m of drift taken out at 10.0m along
  landmark corrections applied: 3
  landmark corrections refused: 0
```

- **`Registering late`** — the trail was rebuilt after a tracking blink and the
  registration fell back to chord matching. Correct behaviour, but it means the
  first corridor was walked without arrows.
- **`RECENTRE at leg N: Xm`** — how much drift each landmark took out. These
  numbers are the accuracy story of the walk: if they grow leg by leg, ARCore's
  odometry is drifting steadily and section 2.1 will show why. If they are all
  under 0.35 m they never fire at all, which means the registration is holding.
- **`RECENTRE REFUSED`** — a landmark and the registration disagreed by more than
  6 m. One of the two is badly wrong. Check whether the sign that was confirmed
  is the sign the route expected.
- **`Floor measured at y=…`** — plane fitting found the floor. If this says
  `No floor plane in 20000ms` on every walk, the rings are being drawn at the
  assumed 1.35 m below the phone and will look wrong to anybody not holding it
  at that height.
- **`Wall grid measured …` / `GRID SNAP …deg`** — where the rotation came from.
  See §5.4; these are the lines that say whether the yaw fix is doing anything.

---

## 4. Known gaps, deliberately left

- **No depth, so no occlusion.** The arrow draws through walls. On a route that
  turns a corner this reads as the arrow being wrong even when its bearing is
  right. Enabling `Config.DepthMode` would fix it and would take CPU from the ML
  Kit pipeline that reads door plates — which is the app's actual positioning
  system. That trade should be made against measured frame times from a real
  device, not in advance, which is why it is not made here.
- **Rotation is never corrected by a landmark.** One point cannot say anything
  about it (`Registration.recentredAt`). Only motion can, via the off-line
  re-solve. A registration that comes out rotated announces itself as a climbing
  `off …m` and is re-solved after 4 s beyond 2.5 m — after the walker has already
  acted on a bad arrow for a few strides.

  Since 2026-08-30 the yaw no longer *starts* from motion alone — see §5 — but
  once solved it is still only motion that can revise it.
- **Floor height is measured once per session.** Walking up a ramp within one
  session leaves the rings at the height of the floor the session started on.

---

## 5. Where the yaw comes from — added 2026-08-30

Written after a walk where the rings landed in the wrong room and the capture
turned out to be empty. Both of those are addressed here.

### 5.1 Why rotation was the whole error

Registration is a similarity transform: scale, rotation, and two of translation.
Three of those four were already sound. Scale is measured by the user and
applied in `room_plan_bridge.dart`. Translation comes from the walker having
told the app which room they are standing in. **Rotation was the only unknown,
and it was also the only one nothing downstream could repair.**

It is worth being precise about why knowing the destination does not help. The
end of the route is known *on the plan*; it is not known in ARCore's world,
because the walker has not been there yet. One point correspondence carries zero
information about rotation. So the yaw had exactly one source: comparing the
direction the walker was travelling against the direction the route leaves in.

And it is a lever. A yaw error of θ puts a ring at distance *d* off the line by
*d*·sin θ:

| yaw error | off the line at 10 m | at 20 m | at 40 m |
| --- | --- | --- | --- |
| 5° | 0.9 m | 1.7 m | 3.5 m |
| 10° | 1.7 m | 3.5 m | 6.9 m |
| 15° | 2.6 m | 5.2 m | 10.4 m |

Against a target of "mean under 1.0 m", anything past about 5° has already
failed, and it fails *worse the further the walker goes* — which is exactly what
a ring landing in the wrong room looks like.

### 5.2 The two fixes

**Matched baselines.** Native used to release a travel heading after 0.7 m of
net displacement (`MIN_TRAVEL_FOR_HEADING_M`) and Dart matched it against the
route's departure direction measured over 3 m (`_departureM`). Those describe
different stretches of walking, and the difference went straight into the yaw —
0.7 m out of a room is largely the act of getting through the doorway.

There is now a second, longer threshold, `MIN_TRAVEL_FOR_REGISTRATION_M = 3 m`,
published as `registrationHeadingDeg`. The short one still exists and still
anchors legs, because a leg can be corrected a few metres later
(`refineCameraAnchor`) and a registration cannot. `TRAIL_SAMPLES` went from 24 to
40 so the ring buffer can actually hold 3 m of net displacement on a walk that
is not perfectly straight.

**The wall grid.** ARCore has no idea what a corridor is — it has no semantics
at all, and no amount of asking will get it to recognise one. What it does have
is vertical planes, and a corridor's walls are vertical planes whose normals
point along the building.

Plane finding is now `HORIZONTAL_AND_VERTICAL`. Wall normals are flattened onto
the floor, folded onto a quarter turn — so both sides of a corridor and the end
wall all vote for the same answer — and averaged as unit vectors at four times
their bearing, which is what makes the fold work. The result is `wallGridDeg`:
the building's rectilinear grid, in ARCore's frame, owing nothing to how the
walker set off.

The plan has a grid too, read off the route's own legs (`Registration.planGridOf`)
— in a rectilinear building, the corridors a route runs down *are* the axes.

`Registration.snappedToGrid` puts the two together. Exactly four yaws carry the
plan's grid onto the world's, a quarter turn apart. **The measured heading picks
which of the four; the walls supply the value.** That split is the point: picking
among four candidates 90° apart only needs the heading right to within 45°,
which even a poor walk manages, while the precision comes from fitted planes
rather than footsteps.

It refuses in three cases, all logged: no walls fitted, a plan too unsquare to
have a grid, and a correction over 25° — which is not departure slop but a
heading in the wrong quadrant or planes fitted to something that is not a wall.

### 5.3 What this does not fix

- **Buildings that are not rectilinear.** A curved or splayed plan has no grid,
  `planGridOf` returns null, and the yaw falls back to the heading alone.
- **Rotation after registration.** Unchanged: landmarks still correct only
  translation. The grid is read once, during the plane-search window.
- **A wrong quadrant.** If the measured heading is more than 45° out, the snap
  picks the wrong candidate — and it will do so *confidently*. This is the one
  failure mode the change introduces, and `off …m` is still what catches it.

### 5.4 New lines in a capture

```
Wall grid measured at 3.2deg from 4 walls, spread 1.1deg
GRID SNAP -7.4deg onto the wall grid
REGISTERED Registration(yaw 3deg, …)
```

- **`Wall grid measured … spread …deg`** — the walls agreed. Spread is the
  circular scatter after folding; over `WALL_GRID_MAX_SPREAD_DEG` (6°) it is
  rejected instead.
- **`Wall grid rejected: N walls disagree by …`** — planes were found and were
  not a building. An out-of-square room, or a door and a bookcase.
- **`No wall grid in …ms`** — the search window closed with too few walls. The
  registration is back to pre-2026-08-30 behaviour, and the `off …m` numbers
  should be read as a test of the old path.
- **`GRID SNAP …deg`** — how much skew the walls took out. **This is the number
  that says whether any of this was worth it.** Consistently under a degree
  means the departure heading was already fine and the walls are only
  confirming it. Consistently 5–15° means they were carrying the walk.

### 5.5 The floor search window

`FLOOR_SEARCH_MS` went from 9 s to 20 s, because the search picked up a second
job. A floor is underfoot from the first frame; a corridor's walls are only
fitted once the walker has moved along them far enough to give ARCore parallax,
and that is the same three metres the registration heading waits for. A window
that shuts before the walker has set off cannot see what it is looking for.

The search now ends when *both* the floor and the grid are in hand, or when the
window expires — and it logs which of the two it failed to get. A capture that
says `No floor plane` on every walk means the rings are drawn at the assumed
1.35 m and will look wrong to anyone not holding the phone at that height, which
is a separate complaint from the rings being in the wrong place.

### 5.6 None of this is measured yet

Everything above is reasoned from the geometry and covered by unit tests
(`test/route_registration_test.dart`, `test/ar_guidance_cubit_test.dart`). **No
walk on a real device has confirmed any of it.** The numbers that would are the
ones in §2, and the specific question to ask of the first capture is whether
`GRID SNAP` is doing anything and whether the `off …m` mean came down.
