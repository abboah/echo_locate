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
  `No floor plane in 9000ms` on every walk, the rings are being drawn at the
  assumed 1.35 m below the phone and will look wrong to anybody not holding it
  at that height.

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
- **Floor height is measured once per session.** Walking up a ramp within one
  session leaves the rings at the height of the floor the session started on.
