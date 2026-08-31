# EchoLocate — Chapters 1 to 4, Submission Working Document

**What this is.** Everything needed to bring Chapters 1–4 to submission, in one place and internally
consistent. Chapters 1–3 exist and are revised here section by section; Chapter 4 did not exist and
is drafted in full from the codebase.

**Status:** current as at 31 August 2026, against a codebase that builds, analyses clean, and passes
840 tests.

**The principle, and it runs through everything below:** the documentation describes what was built.
Where the proposal named a technology that was deliberately rejected, the proposal is corrected.
Where an objective was superseded by a better-evidenced approach, it is replaced. Where something was
delivered but never promised, it is promoted. Nothing here claims work that does not exist.

---

## How to use this document

| Part | Covers | What to do |
|---|---|---|
| **Part A** | Chapters 1–3 | Section-by-section replacements. Anything not listed needs no change. |
| **Part B** | Chapter 4 | A full draft in the departmental template. Paste and add figures. |
| **Part C** | Cross-cutting | Figure checklist, limitations, open decisions. |

Drop-in prose is given as indented block quotes in the register of the existing document. Bracketed
notes mark where a screenshot, diagram or measurement must be inserted before submission.

**Before you paste anything:** close `GROUP 4_Chapter_1_to_3.docx` in Word. It is currently open, and
a lock file sits beside it.

---

## What the system is, in one paragraph

Hold this steady across all four chapters, because inconsistency here is what a reviewer checking for
coherence will find first:

> EchoLocate is a crowdsourced indoor mapping and navigation application. A contributor traces a
> building's floor plan — photographing the plan posted on its wall — and publishes it. Anyone else
> loads that plan, picks a destination, and is guided there turn by turn. Guidance is offered in two
> co-equal modes: **map-and-sound**, which draws the route over the plan and speaks it with haptic
> cues and step counting, requiring no camera and no ARCore; and **augmented reality**, which adds an
> arrow registered into the building itself for sighted walkers on ARCore-certified phones. An
> on-device acoustic Digital Signal Processing pipeline classifies the type of space a user is
> standing in from its reverberation, and on-device machine learning reads signage aloud and warns of
> obstacles.

Three things that follow from that paragraph, and that the original chapters get wrong:

1. **The system is not an active sonar instrument.** Acoustics performs room *classification*. The
   title must change.
2. **Floor plans are authored by tracing, not captured by depth sensing.** There is no point cloud,
   no RANSAC, no Hough transform, and no capture module.
3. **Map-and-sound guidance is not a fallback.** It is the mode most users will walk in, because
   ARCore certification is a property of the handset and most handsets in this setting lack it.

---

# PART A — CHAPTERS 1 TO 3

## 0. Summary of what changes

| Area | Chapter 1–3 as written | Delivered | Action |
|---|---|---|---|
| Project title | "Active sonar system" | Sonar is one component; accessible indoor navigation is the core | **Retitle** |
| State management | Riverpod (§3.2, §3.15) | flutter_bloc | **Correct** |
| Local persistence | Drift/SQLite (Obj 7, §3.14.2, §3.15) | hive_ce | **Correct** |
| Floor-plan generation | ARCore point cloud → RANSAC/Hough | Human tracing → polygon geometry | **Replace objective** |
| 3D extruded preview | flutter_gl | Not built | **Move to future work** |
| Room classifier | TensorFlow Lite | Rule-based over RT60/EDT | **Replace, and defend as better** |
| Chirp parameters | 2–8 kHz, 40 ms | 13–19 kHz, 120 ms | **Correct — this is an improvement** |
| PDF export | Deliverable 5 | Not built | **Descope — future work** |
| Map-and-sound guidance | Folded into the AR overlay | A co-equal mode, and the one most users will walk in | **Promote to its own objective** |
| AR route registration | Not mentioned | Built — plan↔ARCore similarity transform | **Promote to an objective** |
| Landmark re-anchoring | Not mentioned | Built | **Promote** |
| Stride calibration | Not mentioned | Built | **Promote** |

Two of these — AR route registration and landmark re-anchoring — are the most technically
substantial things in the repository and appear nowhere in the proposal. Promoting them is the
single biggest gain available to the revision.

---

## 1. Project title

The current title commits the whole system to being an active sonar instrument. What was built
is an indoor mapping and navigation system in which acoustic DSP performs room *classification*.
Defending the present title requires defending sonar ranging as the system's core, and the
measured 0.6 m floor on uncalibrated hardware makes that indefensible.

**Recommended:**

> ECHOLOCATE: A CROWDSOURCED MOBILE SYSTEM FOR INDOOR FLOOR-PLAN MAPPING AND ACCESSIBLE
> TURN-BY-TURN NAVIGATION, WITH ACOUSTIC ROOM CLASSIFICATION USING DIGITAL SIGNAL PROCESSING

**Alternative, shorter:**

> ECHOLOCATE: A MULTIMODAL MOBILE SYSTEM FOR CROWDSOURCED INDOOR MAPPING AND ACCESSIBLE
> INDOOR NAVIGATION USING AUGMENTED REALITY AND ACOUSTIC DIGITAL SIGNAL PROCESSING

Both retain the Digital Signal Processing contribution explicitly, which matters if DSP is a
departmental requirement on this project. Both lead with what demonstrably works.

---

## 2. §1.3 Aim of the project — replacement

> To design, implement and evaluate EchoLocate, a cross-platform Flutter application that enables
> ordinary users to author two-dimensional indoor floor plans of buildings that have never been
> digitally mapped, to share those plans through a crowdsourced repository, and to navigate them
> turn by turn — including an augmented-reality waypoint overlay registered into the building
> itself and a fully eyes-free voice-and-haptic mode for blind and low-vision users — using only
> the sensors present on a commodity smartphone, supported by an on-device acoustic Digital
> Signal Processing pipeline that classifies the type of space a user is standing in.

---

## 3. §1.4 Specific objectives — replacement

Replace the eight objectives with the following nine. The extra one is map-and-sound guidance, which
the proposal folded into the AR overlay and which is in fact the mode most users will walk in.

> **1. Implement Human-in-the-Loop Floor-Plan Authoring:** Develop a module that allows a
> contributor to produce a metrically scaled 2D floor plan of a building storey, either by
> photographing a posted floor plan and tracing its rooms and corridors, or by tracing the space
> directly, yielding closed room polygons, circulation corridors, and the door openings that
> connect them.
>
> **2. Derive a Navigable Graph from Traced Geometry:** Implement a pipeline that converts traced
> room polygons into a routable graph in which rooms and corridors become nodes, doorways become
> weighted edges, and corridor centrelines provide the polyline a walker physically follows.
>
> **3. Implement Graph-Based Indoor Route Planning:** Develop a custom Dart A* routing engine over
> the derived graph that computes door-to-door shortest paths and converts the resulting node
> sequence into spoken turn-by-turn instructions expressed in the vocabulary a walker can act on.
>
> **4. Implement Map-and-Sound Turn-by-Turn Guidance:** Deliver a planned route as a drawn line over
> the floor plan together with spoken turn-by-turn instructions, haptic cues and step counting, with
> per-user stride calibration so distances are spoken in the walker's own paces — requiring no camera
> and no ARCore, so that guidance is available on any Android handset and usable entirely eyes-free.
>
> **5. Register a Planned Route into the Physical Building using Augmented Reality:** Implement a
> similarity transform that carries plan coordinates into the ARCore world frame from a single
> known position and a single observed heading, so that an augmented-reality waypoint arrow points
> at the true destination rather than dead-reckoning from an assumed starting orientation, and
> re-anchor that registration whenever a landmark is confirmed. This is an additional presentation of
> the route in Objective 4, not a replacement for it.
>
> **6. Implement On-Device Semantic Detection:** Integrate Google ML Kit object detection and text
> recognition to raise real-time obstacle alerts and to read room numbers and signage aloud from
> the live camera feed, processed entirely on the device.
>
> **7. Implement Acoustic Room Classification using Digital Signal Processing:** Develop a
> Dart-native Frequency Modulated Continuous Wave chirp generation and Fast Fourier Transform
> pipeline that extracts reverberation features — reverberation time, early decay time, and the
> ratio between them — from a measured impulse response, and classifies the type of space from
> those features using physically interpretable decision rules.
>
> **8. Build a Crowdsourced Map Repository with Local-First Persistence:** Implement a Supabase-backed
> community repository allowing users to publish the floor plans they author and to browse, load
> and navigate plans contributed by others, over a local-first on-device store that keeps authored
> plans and drafts fully available offline.
>
> **9. Evaluate and Document Performance Boundaries:** Conduct controlled tests across a minimum of
> three indoor environments, measuring floor-plan dimensional accuracy against a calibrated tape
> measure, acoustic room-classification accuracy, and navigation success rate for both sighted and
> accessibility-mode users, explicitly documenting limitations, failure cases, and the approaches
> that were attempted and rejected.

---

## 4. §1.5 Project scope — amendments

**Add to In Scope:**

> **Human-in-the-loop floor-plan authoring:** Metrically scaled 2D plans produced by a contributor
> tracing a photographed or observed floor, comprising room polygons, corridors, doorways and room
> type labels.
>
> **Augmented-reality route registration:** A plan-to-world similarity transform allowing a planned
> route to be laid into the physical building, with re-anchoring at confirmed landmarks.
>
> **Per-user stride calibration:** Measurement of an individual walker's step length so that stored
> distances are converted into that user's steps.

**Move from In Scope to Out of Scope:**

> **Automatic floor-plan generation from depth sensing:** Reconstruction of wall geometry from an
> accumulated ARCore depth point cloud using RANSAC and Hough-transform line fitting. This was
> attempted and is reported in Chapter [4/5]; the resulting geometry was not of sufficient quality
> for navigation and was superseded by human-in-the-loop tracing.
>
> **Extruded 3D preview:** The system produces and renders 2D plans only.
>
> **Learned acoustic classification:** Room type is determined by interpretable decision rules over
> measured reverberation quantities rather than by a trained neural network — see §3.11.2 and the
> justification in §[3.3].

**Also add to Out of Scope:**

> **PDF export of floor plans:** Generation of shareable PDF documents from a captured plan. Plans
> are shared through the crowdsourced repository itself, which is the route the system is designed
> around: a plan is published once and read by everyone, rather than exported per person into a
> document that cannot be navigated. A PDF is a picture of a map; the repository serves the map. The
> capability would be a straightforward addition — the plan renderer that draws a floor on screen is
> the same one a document would use — and it is recorded as future work rather than as a limitation.

---

## 5. §1.8 Methodology — tools table corrections

Replace these rows. The rest of the table stands.

| Tool / Technology | Role in EchoLocate |
|---|---|
| **flutter_bloc** (replaces Riverpod) | Presentation-layer state management; each screen owns a Bloc or Cubit that exposes loading, error and data states to the widget tree. |
| **hive_ce** (replaces Drift/SQLite) | Local-first on-device store holding authored plans, unpublished drafts and cached repository queries, keeping the application fully usable offline. |
| **fftea** (replaces "Dart FFT Pipeline") | Fast Fourier Transform over captured audio, supporting reverberation feature extraction — the project's Digital Signal Processing component. |
| **flutter_soloud / record** (new) | Chirp emission through the device speaker and synchronised capture of the returning signal. |
| **ARCore (custom platform channel)** | Motion tracking and world-frame pose for the augmented-reality waypoint overlay and route registration, accessed from Flutter through a native Android platform channel. |
| **pedometer / sensors_plus** (new) | Hardware step counting for distance estimation along a route leg, with stride length calibrated per user. |

**Remove:** TensorFlow Lite, Drift (SQLite), flutter_gl and `pdf`. None is used.

---

## 6. §1.9 Deliverables — replacement

> **Deliverable 1 – Floor-Plan Authoring Module:** A tracing workflow producing metrically scaled 2D
> floor plans comprising room polygons, corridors, doorways and room type labels, from either a
> photographed posted plan or direct tracing of the space, with draft persistence protecting
> partially completed work.
>
> **Deliverable 2 – Acoustic DSP and Room-Classification Module:** A Dart-native FMCW chirp
> generation and FFT pipeline extracting reverberation features from a measured impulse response,
> with an interpretable rule-based classifier mapping those features to a space type. This
> deliverable constitutes the Digital Signal Processing contribution of the project.
>
> **Deliverable 3 – Indoor Navigation and Routing System:** A graph-derivation pipeline and custom
> Dart A* routing engine producing door-to-door routes and turn-by-turn instructions, together with
> an augmented-reality waypoint overlay registered into the physical building and re-anchored at
> confirmed landmarks.
>
> **Deliverable 4 – EchoLocate Mobile Application (Flutter):** An installable Flutter application
> providing authoring, browsing and navigation workflows, a 2D plan view, and a full accessibility
> suite comprising an eyes-free voice-and-haptic guidance mode with obstacle alerts, sign reading
> and per-user stride calibration.
>
> **Deliverable 5 – Crowdsourced Map Repository with Local-First Persistence:** A Supabase-backed
> community repository for publishing, browsing, loading and navigating shared floor plans, over a
> local-first on-device store supporting offline authoring and use.
>
> **Deliverable 6 – Evaluation and Test Report:** A validation report documenting floor-plan
> dimensional accuracy against a calibrated tape measure across a minimum of three distinct indoor
> environments, acoustic room-classification accuracy, and navigation success rate for sighted and
> accessibility-mode users, including raw data tables, statistical analysis, and a discussion of
> limitations and of approaches attempted and rejected.
>
> **Deliverable 7 – Final Project Report and Source Code:** *(unchanged)*

---

## 7. §3.2 Architecture — replacement

> EchoLocate adopts a local-first, layered client architecture with a thin cloud tier, allowing each
> layer to be developed and tested independently. The presentation layer is a Flutter application
> using flutter_bloc for state management and Go Router for navigation, rendering the authoring,
> browsing, 2D plan and guidance screens and driving the voice-and-haptic accessibility mode; each
> screen owns a Bloc that exposes its loading, error and data states, and live-sensing screens
> subscribe to long-lived sensing services rather than opening hardware themselves. Beneath it, a
> repository layer exposes typed domain models — buildings, floors, room plans, landmarks and routes
> — behind abstract interfaces, so that on-device and cloud-backed implementations are
> interchangeable and the presentation layer is unaware which is in use. The on-device sensing and
> processing layer is the analytical core of the system: it derives a navigable graph from traced
> room geometry, computes routes through it with a custom A* engine, registers those routes into the
> ARCore world frame so that an augmented-reality arrow can be laid into the building, runs Google
> ML Kit object and text detection for obstacle alerts and sign reading, and executes a Dart-native
> FMCW acoustic pipeline whose FFT-derived reverberation features classify the type of space. The
> persistence layer uses a local-first hive_ce store so that authored plans, unpublished drafts and
> cached queries remain fully available offline. A thin cloud tier built on Supabase backs the
> crowdsourced repository, allowing users to publish the plans they author and to browse, load and
> navigate buildings mapped by others. All sensing, routing and plan computation runs on the device;
> the cloud is used only for sharing finished maps, keeping the system privacy-preserving by design.

---

## 8. §3.3 Component design — replacement table

| Component | Function |
|---|---|
| **Floor-Plan Authoring Module** | Captures a photograph of a posted floor plan or a direct trace of the space, and lets a contributor lay down closed room polygons, corridors and door openings, assign room types, and set a metric scale. Drafts are written on every structural change so that partially completed work survives interruption. |
| **Graph Derivation and Routing Engine** | Converts traced geometry into a navigable graph — rooms and corridors as nodes, doorways as weighted edges — and computes door-to-door shortest paths using a custom Dart A* implementation, expanding each leg along the corridor centreline to produce the polyline a walker actually follows. Converts the node path into turn-by-turn instructions. |
| **AR Route Registration and Guidance Layer** | Computes the similarity transform carrying plan coordinates into the ARCore world frame from one known position and one observed heading, lays the planned route into the room, and re-anchors the transform whenever a landmark is confirmed. Reports measured along-leg distance back to the guidance engine, which treats it as a measurement that can refine but never override landmark confirmation. |
| **Semantic Detection Module** | Runs Google ML Kit object detection and text recognition on the live camera feed to raise obstacle alerts and to read room numbers and signage aloud, entirely on-device. Shares a single camera stream with the AR layer, since ARCore holds the camera exclusively while a session is active. |
| **Acoustic DSP Pipeline** | Emits a linear FMCW chirp and applies a Dart-native Fast Fourier Transform to the captured response, extracting reverberation time, early decay time, decay linearity and usable decay range, and mapping them to a space type through interpretable decision rules. Constitutes the project's Digital Signal Processing contribution. |
| **Accessibility and Motion Services** | Delivers guidance as synthesised speech and haptic patterns for eyes-free use, arbitrating access to the microphone and speaker between the voice interface and the acoustic pipeline, and counts steps against a per-user calibrated stride length so that distances are spoken in the walker's own paces. |
| **Crowdsource and Persistence Service** | Manages local-first storage in hive_ce and synchronises published plans with the Supabase repository, handling upload, browsing, loading and contributor records. |

---

## 9. §3.11 Algorithms — replacements

### 3.11.1 Algorithm 1 — Floor-Plan Authoring and Graph Derivation

*(replaces the point-cloud/RANSAC/Hough algorithm)*

| Step | Operation |
|---|---|
| Input | A photograph of a posted floor plan, or the space itself; contributor input. |
| Step 1 | Establish a metric scale by having the contributor mark a known real-world distance on the plan. |
| Step 2 | Trace closed polygons for each room and corridor, capturing corners in plan coordinates (+x east, +y north). |
| Step 3 | Assign a room type from a fixed vocabulary chosen so that every entry is identifiable from a doorway. |
| Step 4 | Mark door openings on shared walls, recording which two spaces each connects. |
| Step 5 | Clean the traced geometry: merge near-coincident corners, square near-orthogonal walls, and discard degenerate polygons. |
| Step 6 | Derive the navigable graph — rooms and corridors become nodes, openings become weighted edges, corridor centrelines are extracted as the walkable spine. |
| Output | A `RoomPlan` comprising room polygons, corridors, openings, type labels and a metric scale, together with the graph derived from it. |

### 3.11.2 Algorithm 2 — Acoustic Room Classification

| Step | Operation |
|---|---|
| Input | Microphone and speaker access; a trigger from the user or from a room-labelling action. |
| Step 1 | Emit a linear FMCW up-sweep of **13–19 kHz over 120 ms** at 44.1 kHz, and record the response. The near-ultrasonic band places the sweep above the region carrying almost all speech, footstep and HVAC energy, so ambient noise contributes little to the correlation; it is also faint or inaudible to most listeners, which matters for a system intended to be used repeatedly in occupied buildings. |
| Step 2 | Correlate the recording against the transmitted sweep. Matched-filter processing gain follows the time–bandwidth product; at 6 kHz of bandwidth, 120 ms yields TB ≈ 720 (≈ 28.6 dB) while leaving range resolution unchanged, since that is set by bandwidth alone. |
| Step 3 | Apply a windowed FFT and derive the energy decay curve of the response. |
| Step 4 | Fit a straight line to the decay in dB and extract **RT60** (extrapolated from a reliable portion of the decay), **early decay time** (the same slope over the first 10 dB), the **fit quality** r², and the **usable decay range** in dB. |
| Step 5 | Gate on fit quality and decay range: an estimate derived from noise or from too short a capture is rejected rather than classified. |
| Step 6 | Classify by interpretable rules over RT60 and the EDT/RT60 ratio. A low ratio indicates a non-diffuse field — the acoustic signature of a corridor, where strong parallel reflections make early decay much shorter than late decay. Short RT60 with a diffuse field indicates a small furnished room; long RT60 indicates a large, lightly absorbing hall. |
| Output | A space-type classification with an associated confidence, or an explicit rejection. |

**Justification to carry into the text.** A rule-based classifier is preferred here over a learned
model, and this should be argued rather than apologised for. The thresholds derive from Sabine's
relation, which ties reverberation time to volume and absorption and therefore causes room classes
to separate along RT60 for physical reasons. Every decision the classifier makes can be defended
from room acoustics. A small neural network trained on the handful of reverberation samples
obtainable within a 12-week project could not be defended in the same way, would carry an
unquantified generalisation risk, and would require a data-collection exercise that buys little
additional separation. The thresholds are exposed as parameters precisely so that the evaluation in
Chapter 5 can re-fit them against measured rooms.

### 3.11.3 Algorithm 3 — A* Indoor Navigation

Substantially correct as written. Two amendments:

- **Step 1** should read that the graph is derived from traced room geometry rather than from
  "walkable cells": rooms and corridors are nodes, doorways are weighted edges, and both route
  endpoints sit on doorways rather than at room centres, so that a route begins and ends at a door
  a walker can actually see.
- **Step 6** should note that the AR overlay is a *registered* route rather than a floating
  waypoint marker, cross-referencing the registration described in §3.3.

### 3.11.4 Algorithm 4 — Route Registration *(new — recommended)*

This is the most novel algorithm in the system and currently appears nowhere in the report.

| Step | Operation |
|---|---|
| Input | A planned route in plan coordinates; a live ARCore session; the room the walker has declared themselves to be in. |
| Step 1 | Take the walker's ARCore position at the moment guidance starts as corresponding to their known position on the plan. This fixes the translation. |
| Step 2 | After a few steps, read the direction of travel from ARCore pose and the direction of the route's first leg from the plan. Assume these coincide; the rotation follows. |
| Step 3 | Note that scale is not an unknown: the plan's metres-per-unit is set by the contributor, so both frames are already metric. A planar similarity transform therefore has three unknowns, and one point plus one direction supplies exactly three constraints. |
| Step 4 | Correct for handedness: the plan is a right-handed 2D frame read from above, whereas the floor of the ARCore world read the same way is left-handed. |
| Step 5 | Apply the transform to lay the whole route into the room at once, and emit a confidence value from the quality of the heading estimate. |
| Step 6 | On each confirmed landmark, re-solve the transform against that landmark's known plan position, replacing the initial heading assumption with a measurement. |
| Output | A rotation and translation carrying plan coordinates into the ARCore world, with confidence, refreshed at every landmark. |

---

## 10. §3.14.2 Database design — replacement

> EchoLocate uses a local-first hive_ce store for on-device persistence, with a Supabase (PostgreSQL)
> cloud tier holding published copies of shared plans. Locally, authored plans and their unpublished
> drafts are held under separate key prefixes so that an incomplete trace can never overwrite the
> published plan it is a draft of, and repository queries are cached against the same store to keep
> browsing usable offline. The cloud schema is normalised around a `buildings` table and its
> dependent `floors` and `rooms`, a `room_plans` table holding traced geometry per floor, a
> `landmarks` table, `routes` and `route_steps` for recorded walks, `profiles` for contributor
> records and `building_contributors` for attribution, and `saved_maps` for a user's own library.
> Foreign keys with cascade deletion keep a plan and its dependent rows consistent.

Figure 3.32 must be redrawn against this schema. The migrations under `supabase/migrations/` are
the authoritative source.

---

## 11. §3.15 Development tools

Apply the same corrections as §1.8 above. The two tables should match exactly.

---

## 12. Chapter 2 — light touch

The literature review, comparative analysis and research-gap sections largely survive, because the
*problem* has not changed. Two amendments:

- **§2.7 Research gaps.** If the gap is currently framed around automatic depth-based mapping, re-frame
  it around the supply problem: indoor maps barely exist, and the binding constraint is the cost of
  producing them, not the cost of sensing. Human-in-the-loop authoring at near-zero marginal cost is
  a legitimate answer to that gap and is what you built.
- **§2.8 Conceptual design.** Redraw to match the revised §3.2.

---

## 13. The revision note

The supervisor reviews documentation for internal consistency and completeness rather than guiding
the build, and the assessment meeting is the first contact. This is not a change to request
permission for — it is a change to **declare**, with its rationale, in a short note accompanying the
revised chapters. Handing over a documented delta demonstrates control of the project; letting him
discover the mismatch between the objectives list and the demo does the opposite. Frame it as scope
refinement driven by evidence, which is what it is:

> Two of the proposed sensing approaches were implemented and evaluated on hardware, and neither met
> the standard required for navigation: depth-from-motion floor-plan reconstruction accumulated
> heading error that compounded over a storey, and uncalibrated acoustic ranging floored out at
> roughly 0.6 m. Rather than report two failed modules, the project redirected the effort into
> human-in-the-loop plan authoring and augmented-reality route registration, both of which were
> delivered and are demonstrable. The Digital Signal Processing contribution is retained in the
> acoustic room-classification pipeline. The revised chapters describe the system as built; the
> approaches that were attempted and rejected are reported in full in Chapter [4/5] as findings.

Lead the presentation with this, rather than waiting to be asked. The first thing said about the
project should be what it is now and why, not a demo that quietly contradicts a document already in
his hands.

---


# PART B — CHAPTER 4

**CHAPTER 4 — IMPLEMENTATION, TESTING, AND RESULTS**

Follows the departmental template. Its own §4.1.4–4.1.9 (hashing, checksum recovery, data
shuffling) belong to a different project and are replaced by EchoLocate's modules; the Login
Module is retained, since the system genuinely has one.

---

# 4.1 IMPLEMENTATION

## 4.1.1 Introduction

Chapter Three specified the architecture, components and algorithms of EchoLocate. This chapter
reports how that specification was realised, how the result was verified, and what it achieves.

The delivered system comprises **36,566 lines of Dart** (excluding generated code), **4,465 lines of
Kotlin** implementing the native augmented-reality layer, and **16,498 lines of automated test code**
covering **840 test cases** across 57 test files. The application presents **22 screens**, each
implemented in both light and dark themes.

Implementation followed three conventions held throughout, because a multimodal system accumulates
coupling quickly without them:

1. **Repositories return typed models, never untyped maps.** Each domain area exposes an abstract
   interface with interchangeable on-device and cloud implementations, so the presentation layer is
   unaware which is in use.
2. **Blocs own screen state; services own hardware.** Sensing services are registered as singletons
   and Blocs subscribe to them, rather than each screen opening the camera or microphone itself. This
   matters because ARCore holds the camera exclusively while a session is active.
3. **Every screen is built in light and dark** from a shared token set, so no screen carries a
   hard-coded colour.

[Insert Figure 4.1: implemented layered architecture — redraw of Figure 3.1 against the delivered system]

---

## 4.1.2 Implementation of the Frontend

### UI Designs

The interface follows a five-destination bottom navigation pattern — Home, Explore, a centre action,
Maps, Profile — with full-screen flows pushed above it. Twenty-two screens were implemented:

| Group | Screens |
|---|---|
| Onboarding and authentication | onboarding, welcome, sign in, sign up, camera primer, location primer |
| Browsing | home, explore, maps, building detail |
| Authoring | map building, building mapping hub, plan trace, room trace, plan editor |
| Navigation | navigate, room navigate, guidance |
| Sensing | assist, acoustic, sonar, depth probe, room plan probe |
| Profile | profile, stride calibration |

The visual system uses a single warm accent (coral `#FB5B47`) against a near-black ink and an
off-white surface, with Hanken Grotesk throughout, rounded cards and soft shadows. Every colour and
spacing value is drawn from a token file rather than written at the point of use, which is what makes
the dark theme a redefinition of tokens rather than a second set of screens.

Permission priming is handled by dedicated primer screens shown once before the first camera or
location request, rather than by raising a system dialogue cold. A user who denies a permission
because they did not expect it is expensive to recover.

[Insert Figures 4.2–4.x: screenshots of principal screens in both light and dark themes]

### UI Code Listing

Each screen owns a Bloc or Cubit and renders from its state. The pattern below, from
`lib/ui/pages/explore/explore_page.dart`, is representative: a `BlocBuilder` rebuilds on state change,
user actions are dispatched as events, and every branch of the state — loading, failure, data — is
rendered explicitly rather than assumed.

```dart
Expanded(
  child: BlocBuilder<ExploreBloc, ExploreState>(
    builder: (context, state) => switch (state.status) {
      ExploreStatus.initial || ExploreStatus.loading =>
        const Center(child: CircularProgressIndicator()),
      ExploreStatus.failure => Center(
        child: Text(
          state.error ?? 'Could not load buildings',
          style: theme.textTheme.bodyMedium,
        ),
      ),
      ExploreStatus.success => ListView.builder(...),
    },
  ),
),
```

Filter interaction dispatches an event rather than mutating local widget state, and `buildWhen`
restricts rebuilds to the field that actually changed:

```dart
BlocBuilder<ExploreBloc, ExploreState>(
  buildWhen: (a, b) => a.category != b.category,
  builder: (context, state) => ... _FilterChip(
    label: label,
    selected: state.category == id,
    onTap: () => context.read<ExploreBloc>().add(ExploreCategoryChanged(id)),
  ),
),
```

---

## 4.1.3 Implementation of the Backend

### Backend Designs

The backend is local-first: everything works offline against an on-device `hive_ce` store, and
published plans synchronise with a Supabase (PostgreSQL) tier.

The cloud schema is defined across ten migrations under `supabase/migrations/`, normalised around
`buildings` and its dependent `floors` and `rooms`, with `room_plans` holding traced geometry per
floor, `landmarks`, `routes` and `route_steps` for recorded walks, `profiles` and
`building_contributors` for attribution, and `saved_maps` for a user's own library. Foreign keys with
cascade deletion keep a plan and its dependent rows consistent.

Three design decisions are worth reporting:

**Drafts are isolated from published plans by key prefix.** Tracing a floor is roughly twenty minutes
of standing in a corridor, and until a plan is published it exists nowhere but in memory. A draft is
written on every structural change, under a prefix that makes it impossible for an incomplete trace to
overwrite the plan it is a draft of.

**Plans are stored as encoded JSON strings, not as maps.** The nested lists of immutable models within
a plan are not types the local store recognises, and it fails at the moment of saving. Encoding once
at the boundary makes that failure impossible rather than intermittent.

**Plan replacement is last-write-wins by design.** Two contributors tracing the same floor produce two
opinions of the same geometry, and merging polygons cannot be done sensibly without asking a person
which is right.

[Insert Figure 4.x: revised entity-relationship diagram — replaces Figure 3.32]

### Backend Code Listing

Storage is reached through an abstract interface, so the on-device and Supabase implementations are
interchangeable. From `lib/features/room_trace/room_plan_repository.dart`:

```dart
abstract class RoomPlanRepository {
  /// The traced rooms for one floor, or null when nobody has traced it.
  Future<RoomPlan?> planFor(String buildingId, String floorId);

  /// Every floor of a building that has been traced.
  Future<List<RoomPlan>> plansOf(String buildingId);

  /// Stores a plan, replacing whatever that floor had.
  Future<void> save(RoomPlan plan);

  Future<void> delete(String buildingId, String floorId);

  /// Keeps the floor as it stands right now, without publishing it.
  /// Always device-local: a draft is by definition work somebody has not
  /// chosen to share.
  Future<void> saveDraft(RoomPlan plan);

  Future<RoomPlan?> draftFor(String buildingId, String floorId);
  Future<void> clearDraft(String buildingId, String floorId);
}
```

Implementations are selected once at startup, in `lib/services/injection_container.dart`, so no screen
knows which is in use:

```dart
getIt.registerLazySingleton<RoomPlanRepository>(
  () => AppConfig.hasSupabase
      ? SupabaseRoomPlanRepository(Supabase.instance.client)
      : const LocalRoomPlanRepository(),
);
```

---

## 4.1.4 The Login Module

Authentication is provided by Supabase, with native Google sign-in through Android's Credential
Manager yielding an ID token that Supabase exchanges for a session.

The module is implemented as `AuthRepository` (abstract), `SupabaseAuthRepository` (production) and
`MockAuthRepository` (used when no Supabase configuration is present, keeping its session in a local
box). `AuthBloc` holds the session state for the whole application, and the router listens to it: a
redirect swaps between a guest route tree (onboarding, welcome, sign in, sign up) and the
authenticated tree whenever the Bloc emits.

```dart
String? _redirect(BuildContext context, GoRouterState state) {
  final settings = getIt<SettingsRepository>();
  final authenticated = getIt<AuthBloc>().state is AuthAuthenticated;
  final onGuestPath = _guestPaths.contains(state.matchedLocation);

  if (!settings.onboardingSeen) { ... return AppRoutes.onboarding; }
  if (!authenticated) {
    if (onGuestPath && location != AppRoutes.onboarding) return null;
    return AppRoutes.welcome;
  }
  if (onGuestPath) return AppRoutes.home;
  return null;
}
```

Network and credential failures are translated into readable messages at the repository boundary
rather than surfaced as exceptions, and this behaviour is covered by tests
(`supabase_auth_repository_test.dart`).

[Insert Figure 4.x: sign-in and sign-up screens, both themes]

---

## 4.1.5 The Floor-Plan Authoring Module

This module replaces the depth-based plan generation specified in Chapter Three. Tracing produces a
metrically scaled floor in about twenty minutes, depends on no tracking quality, and — decisively for
this project — works identically on every Android phone rather than only on ARCore-certified ones, so
contributing is open to everyone rather than to owners of particular handsets.

A contributor produces a floor plan by photographing a posted plan, or by tracing the space directly,
and laying down closed polygons for rooms and corridors. Corners are captured in plan coordinates with
+x east and +y north; a metric scale is established by marking one known real-world distance.

Traced geometry is cleaned rather than trusted (`room_cleanup.dart`, `floor_squaring.dart`):
near-coincident corners are merged, near-orthogonal walls are squared, and degenerate polygons are
discarded. Room types come from a short wall-board vocabulary rather than a building-code
classification, because a contributor must choose one while standing in a corridor and every entry has
to be identifiable from a doorway.

Because a large building cannot be traced in one sitting, a floor is authored a wing at a time, and
wings are reconciled by a person dragging one into place against another. This substitutes
human-in-the-loop alignment for pose-graph optimisation, on the grounds that the latter is weeks of
work and the former is a contributor who can see the building.

[Insert Figure 4.x: tracing a plan, setting scale, a completed floor]

---

## 4.1.6 Implementation of the Graph Derivation and Routing Method

Traced geometry is converted into a navigable graph in which rooms and corridors are nodes and
doorways are weighted edges (`room_graph.dart`). Routes are computed by a custom Dart A*
implementation (`route_planner.dart`) using a straight-line Euclidean heuristic, admissible because
the layout preserves recorded distances.

```dart
final cameFrom = <String, Neighbour>{};
final costSoFar = <String, double>{from: 0};
final open = <String>[from];

while (open.isNotEmpty) {
  // A list scan rather than a heap: a floor holds tens of landmarks, and the
  // constant factor of a priority queue is not worth the code.
  var currentIndex = 0;
  var bestEstimate = double.infinity;
  for (var i = 0; i < open.length; i++) {
    final estimate = costSoFar[open[i]]! + _heuristic(graph, open[i], to);
    if (estimate < bestEstimate) { bestEstimate = estimate; currentIndex = i; }
  }
  final current = open.removeAt(currentIndex);
  if (current == to) {
    return _reconstruct(graph, cameFrom, from, to, landmarks, recorded);
  }

  for (final neighbour in graph.neighboursOf(current)) {
    final cost = costSoFar[current]! + neighbour.distanceM;
    final known = costSoFar[neighbour.landmarkId];
    if (known != null && known <= cost) continue;
    costSoFar[neighbour.landmarkId] = cost;
    cameFrom[neighbour.landmarkId] =
        Neighbour(landmarkId: current, edge: neighbour.edge);
    if (!open.contains(neighbour.landmarkId)) open.add(neighbour.landmarkId);
  }
}
return null;
```

Two details distinguish the implementation from the textbook algorithm:

**Both route endpoints sit on doorways, not room centres.** A route from the middle of one room to the
middle of another begins and ends in open floor with no door in sight. Endpoints were moved onto the
doorway while retaining the room they belong to, so the final spoken instruction still names the room.

**Waypoints and the drawn polyline are deliberately separate.** Waypoints are decision points and
produce one spoken instruction per pair; the polyline expands each corridor leg along that corridor's
centreline, so the drawn route follows the hallway round a corner. Merging them would generate an
instruction for every bend a walker does not need told about.

[Insert Figure 4.x: a planned route drawn over a traced floor]

---

## 4.1.7 Implementation of the Augmented-Reality Route Registration Technique

This is the most substantial component of the system, and it is not in Chapter Three — it was built
because the arrow specified there could not work without it.

**The problem.** Plan geometry works in the plan's own frame: +x east, +y north, origin wherever
tracing began. ARCore works in a frame it invents at session start, +y up, floor in the x–z plane.
Guidance originally bridged the two by refusing to — it walked a chain of *relative* turns, each
measured from the last, so no absolute direction was ever needed. That is exactly why the arrow could
not navigate: a chain of relative turns is only as good as the direction its first link was hung from,
and that was whichever way the phone happened to be pointing.

**The solution.** A planar similarity transform has four unknowns, but scale is not among them here —
the plan's metres-per-unit is set by the contributor, so both frames are already metric. That leaves
three, and three is exactly what one point plus one direction supplies:

- **The point** — the walker's position on the plan is known at the moment guidance starts, because
  they chose the room they are in. Their ARCore position at that instant is the same place in the
  other frame.
- **The direction** — after a few steps ARCore knows which way they are travelling, and the plan knows
  which way the first leg runs.

The implementation corrects for handedness: the plan is a right-handed 2D frame read from above,
whereas the floor of ARCore's world read the same way is left-handed.

**Reducing the remaining risk.** The heading assumption is the technique's whole risk, and it is
deliberately a small one — it is made as a walker sets off toward a destination they have just chosen,
down the only corridor leaving the room they said they were in. A confidence value lets callers decide
whether to trust the transform, and re-registration at each confirmed landmark replaces the assumption
with a measurement.

**Wall-grid snapping.** Because corridors are rectilinear, the route's own legs imply a grid. Leg
bearings are summed as unit vectors at *four times* their bearing, weighted by length — quadrupling
makes legs at 0°, 90°, 180° and 270° reinforce rather than cancel, whereas averaging bearings directly
would place a corridor and the one crossing it at 45°, the one answer that cannot be right. The
measured yaw selects which quarter turn; the grid supplies the value.

```dart
for (var i = 0; i + 1 < path.length; i++) {
  final delta = path[i + 1] - path[i];
  final length = delta.distance;
  if (length < minLegM) continue;          // short legs do not vote
  final quadrupled = 4 * planBearingOf(delta);
  sumSin += length * math.sin(quadrupled);
  sumCos += length * math.cos(quadrupled);
  weight += length;
}
if (weight <= 0) return null;

final resultant = math.sqrt(sumSin * sumSin + sumCos * sumCos) / weight;
if (spreadOfResultant(resultant) > maxSpreadRad) return null;
return foldToQuarter(math.atan2(sumSin, sumCos) / 4);
```

**Native layer.** ARCore integration was written directly rather than taken from a plugin — 4,465
lines of Kotlin:

| File | Lines | Role |
|---|---|---|
| `ArGuidanceHandler.kt` | 2,448 | Session lifecycle, pose streaming, route anchoring |
| `ArrowRenderer.kt` | 636 | OpenGL rendering of the guidance arrow |
| `ArCoreDepthHandler.kt` | 453 | Depth API access and availability checks |
| `RegisteredRoute.kt` | 358 | The route as laid into the world frame |
| `ArGlSurface.kt` | 263 | External-texture surface shared with Flutter |
| `CameraBackgroundRenderer.kt` | 239 | Camera feed as the AR background |
| `MainActivity.kt` | 68 | Platform-channel registration |

A significant performance decision sits in `ArGlSurface.kt`: the camera preview reaches Flutter as an
external texture rather than as encoded frames, removing a per-frame encode/decode round trip from the
render path.

[Insert Figure 4.x: the AR arrow in a corridor; Figure 4.y: registration geometry diagram]

---

## 4.1.8 Implementation of the Semantic Detection Module

Google ML Kit object detection and text recognition run against the live camera feed to raise obstacle
alerts and read room numbers and signage aloud (`detection_service.dart`,
`text_recognition_service.dart`). Both run entirely on-device; no image leaves the phone.

The service resolves its frame source at start, preferring an already-streaming AR session — ARCore
holds the camera exclusively, so the camera plugin could not open it in any case. Recognised text is
matched against known landmarks by `landmark_matcher.dart`, which tightens the plain edit-distance
tolerance originally specified: room codes differ by single characters, and a tolerant match
confidently reports the wrong room. What is announced, and how often, is separated into
`callout_policy.dart` so it can be tuned without touching detection.

---

## 4.1.9 Implementation of the Acoustic Digital Signal Processing Pipeline

The pipeline emits a linear FMCW up-sweep and analyses the return to characterise the space. This is
the project's Digital Signal Processing contribution.

**Signal parameters as implemented** (`chirp_params.dart`) differ from §3.11.2, deliberately:

| Parameter | Specified | Implemented | Reason |
|---|---|---|---|
| Band | 2–8 kHz | **13–19 kHz** | Speech, footsteps and HVAC put almost all energy below ~8 kHz. Above that band, ambient noise contributes little to the correlation, so the noise floor *falls* in a crowded room rather than rising. The band is also faint or inaudible to most listeners. Bandwidth is unchanged at 6 kHz, so range resolution is unaffected. |
| Duration | 40 ms | **120 ms** | Matched-filter gain follows the time–bandwidth product. At 6 kHz, 40 ms gives TB = 240 (≈24 dB); 120 ms gives TB = 720 (≈28.6 dB). The compressed pulse stays equally sharp, since width is set by bandwidth, not duration. |
| Sample rate | 44.1 kHz | 44.1 kHz | Unchanged; keeps the band below Nyquist with margin for microphone roll-off. |

**Feature extraction** (`reverb_analyzer.dart`) derives four quantities from the energy decay curve:
**RT60** (extrapolated from a reliable portion of the decay rather than a full 60 dB), **early decay
time** (the same slope over the first 10 dB, scaled), **fit quality r²** (a real decay in dB is close
to linear; when this is low, what was measured was noise), and **usable decay range in dB** (an RT60
extrapolated from 8 dB is a weaker claim than one from 25 dB). The last two act as a gate: an estimate
from noise, or from a capture too short to contain a decay, is rejected rather than classified.

**Classification** (`room_classifier.dart`) applies interpretable rules. The EDT/RT60 ratio is the key
discriminator: in a diffuse room energy arrives from all directions and decays at one rate throughout,
so early and late decay agree; in a corridor, strong parallel reflections make early decay much
shorter. That ratio separates corridors from rooms in a way neither value achieves alone.

```dart
final rt60 = features.rt60Seconds;
final ratio = rt60 <= 0 ? 1.0 : features.earlyDecayTimeSeconds / rt60;

// Decay SHAPE is tested first. A corridor can share an RT60 with a room, so
// duration alone cannot separate them; a markedly non-diffuse decay can only
// come from strongly directional geometry.
if (rt60 >= minCorridorRt60 && ratio < maxDiffuseRatio) {
  return RoomClassification(
    type: RoomType.corridor,
    confidence: _confidence(maxDiffuseRatio - ratio, maxDiffuseRatio),
    features: features,
    reason: 'non-diffuse decay (EDT/RT60 ${ratio.toStringAsFixed(2)}) — '
            'strong early reflections off parallel surfaces',
  );
}
if (rt60 <= smallRoomMaxRt60) { /* small room */ }
```

| Threshold | Value | Meaning |
|---|---|---|
| `smallRoomMaxRt60` | 0.6 s | At or below, a small, well-absorbing space |
| `hallMinRt60` | 1.2 s | At or above, a large, lightly absorbing volume |
| `maxDiffuseRatio` | 0.8 | Below, the field is non-diffuse — a corridor |
| `minCorridorRt60` | 0.4 s | Floor below which a corridor reading is not believed |

**Justification for rules over a learned model.** Chapter Three specified a TensorFlow Lite
classifier; rules were implemented instead, and this is argued rather than conceded. Sabine's relation
ties reverberation time to volume and absorption, so room classes genuinely separate along RT60 for
physical reasons, and every decision the classifier makes can be defended from room acoustics. A small
network trained on the handful of samples obtainable in a twelve-week project carries an unquantified
generalisation risk and demands a data-collection exercise buying little additional separation. Every
classification also returns a `reason` string, so a wrong answer can be diagnosed rather than merely
observed. The interface is unchanged, so a learned classifier can replace it later without disturbing
anything upstream, and the thresholds are constructor parameters precisely so §4.3 can re-fit them.

[Insert Figure 4.x: a captured sweep, its correlation, and the fitted decay curve]

---

## 4.1.10 Implementation of the Accessibility and Motion Services

Guidance is delivered as synthesised speech and haptic patterns, so the system is usable with the
phone in a pocket and the screen dark.

**Audio arbitration.** A single `AudioArbiter` mediates every use of microphone and speaker, because
the voice interface and the acoustic pipeline want the same hardware and would otherwise collide.

**Step counting.** `StepService` wraps Android's hardware `TYPE_STEP_COUNTER` rather than deriving
steps from raw accelerometer data, so the count survives the phone being held still while a walker
reads a sign.

**Stride calibration.** Distances are stored in metres by the contributor but spoken to the walker in
their own paces. `StrideCalibrationCubit` measures an individual's step length; an uncalibrated user
falls back to a documented default rather than being blocked.

**Distance is a measurement, never a decision.** Where ARCore is available it measures along-leg
progress better than counting footfalls against an estimated stride, and that number is reported to
the guidance engine. It can never advance a leg, end a route or move a walker onto another one —
landmarks do all of that, and a distance disagreeing with a sign is the distance that is wrong. This
is what keeps the route working unchanged on phones with no ARCore and no step counter.

---

# 4.2 TESTING

Verification is by automated test at unit and widget level, supported by walked trials on physical
hardware for anything involving the camera, microphone, step counter or ARCore.

| Measure | Value |
|---|---|
| Test files | 57 |
| Test cases | 840 |
| Lines of test code | 16,498 |
| Ratio of test to production code | approximately 1 : 2.2 |

## 4.2.1 UI Testing

Widget tests render principal screens against fake repositories and assert that each state branch
produces the right interface, in both themes. Covered screens include the plan editor, room trace,
navigation, room navigate and the room-plan probe, together with the shared painters and views
(`floor_plan_painter_test.dart`, `route_map_view_test.dart`, `room_plan_view_test.dart`).

Tests assert behaviour a user would notice — that the room sheet refuses to add a room before a
category is chosen, that a route is drawn in both themes, that an error state shows a readable message
rather than an exception.

## 4.2.2 DB Testing

Persistence is tested at the repository boundary: caching behaviour (`repository_mixin_test.dart`),
draft isolation from published plans, and JSON round-tripping (`room_plan_repository_test.dart`,
`route_repository_test.dart`, `building_repository_test.dart`, `settings_repository_test.dart`).

The round-trip tests matter more than they appear to. A plan must survive encoding to JSON, storage in
Postgres and decoding back with its nested geometry intact; a silent change in that path would corrupt
plans rather than fail loudly, so the tests pin the exact shape.

## 4.2.3 Integration Testing

Integration is tested by substituting fakes at the service boundary, so a Bloc's behaviour under a
stream of frames, steps or poses is exercised without a device. `guidance_bloc_test.dart`,
`ar_guidance_cubit_test.dart` and `floor_map_bloc_test.dart` cover the paths where several components
must agree — that a confirmed landmark advances a leg, that a reported distance refines but never
overrides it, that losing the walker triggers recovery rather than silence.

Pure cross-module pipelines are tested end to end without mocks at all: traced geometry through
cleanup, graph derivation, routing and direction generation (`room_plan_bridge_test.dart`,
`room_directions_test.dart`, `graph_route_path_test.dart`, `route_registration_test.dart`).

## 4.2.4 System Testing

System testing was carried out by walking routes in real buildings on a physical Android device, since
camera, microphone, step counting and AR tracking cannot be exercised in a host test environment. Both
navigation modes were walked against floors traced by the team.

The procedure for characterising augmented-reality guidance — odometry scale, yaw drift and off-route
distance — is documented in `docs/ar-navigation-accuracy.md`.

[Insert: device specification and the buildings and routes walked]

---

# 4.3 RESULTS

## 4.3.1 Functional results

The system delivers end to end: a contributor traces a floor plan and publishes it; another user loads
it, chooses a destination, and is guided there turn by turn.

| Objective (revised Ch. 1) | Outcome |
|---|---|
| 1. Human-in-the-loop plan authoring | Delivered — metrically scaled plans, draft-protected |
| 2. Navigable graph from traced geometry | Delivered |
| 3. Graph-based route planning (A*) | Delivered — door-to-door, with spoken instructions |
| 4. Map-and-sound guidance | **Delivered — walked trials reached the destination** |
| 5. AR route registration and arrow | Delivered — with landmark re-anchoring; heading accuracy is the open issue |
| 6. On-device semantic detection | Delivered — obstacle alerts and sign reading |
| 7. Acoustic room classification (DSP) | Delivered — awaiting threshold re-fitting against measured rooms |
| 8. Crowdsourced repository, local-first | Delivered |

## 4.3.2 The two navigation modes

EchoLocate presents a planned route in two ways, and they are **co-equal features serving different
users and different hardware**, not a primary mode and a fallback.

**Map-and-sound guidance** draws the route over the floor plan and speaks the walk turn by turn, with
haptic cues and step counting. It needs no camera and no ARCore, runs on any Android phone, and is the
mode a blind or low-vision user walks in — where a camera overlay would be of no use at all.

**Augmented-reality guidance** adds a registered arrow laid into the building itself, for a sighted
walker who wants to see where to go rather than hear it.

Both are driven by the same `GuidanceBloc` over the same A* route; the AR layer only mirrors the
current leg into the camera and can be toggled off mid-walk. The route, the instructions and the
arrival logic are identical in both.

This division is a design position, not a limitation. ARCore certification is a property of the
handset, and the phones most widely owned in the setting this project targets are not certified for
it. A system whose navigation depended on ARCore would be unavailable to most of the people it is
meant to serve. Map-and-sound guidance is therefore expected to be the **more used** of the two, and
was built to that standard rather than as a degraded alternative.

## 4.3.3 Walked trial results

Routes were walked in real buildings against traced floors, in both modes.

**Map-and-sound guidance: successful.** Following the spoken guidance, a walker arrives at the
intended destination. The instructions name the right rooms and doors in the right order, and arrival
is announced at the destination.

**Augmented-reality guidance: functional, with heading inaccuracy.** The arrow appears, registers into
the room and re-anchors at landmarks, but its heading is not consistently accurate over a full route.
The registration solves rotation from a single observed heading at the start of the walk (§4.1.7), so
an error there propagates until the first confirmed landmark corrects it.

One contributing factor was identified and corrected during preparation of this chapter: the minimum
leg length for wall-grid voting had been reduced from 2.5 m to 0.5 m, which allowed route segments
far too short to indicate a building's orientation — a doorway hop rather than a corridor — to
influence the grid estimate that sets the arrow's yaw. The threshold has been restored; see §4.3.4.
The walked trials reported above predate that correction, so the heading behaviour should be
re-observed before the figures in §4.3.5 are collected.

**Interpretation.** The mode that must work for the project's primary users — eyes-free, on
uncertified hardware — is the mode that works. The mode with an open accuracy problem is the optional
visual overlay on top of it. That is the right way round, and it is the direct consequence of the
architecture in §4.1.10: distance and pose are treated as measurements that refine guidance, while
landmarks decide it, so an inaccurate arrow cannot mislead the underlying route.

[Insert: table of routes walked — building, floor, start, destination, mode, outcome]

## 4.3.4 Test results

All **840 tests pass**.

One defect was found and fixed during the preparation of this chapter, and is worth reporting
because it illustrates what the test suite is for. `route_registration_test.dart` — *"a path with no
leg long enough has no grid"* — was failing, expecting `null` and receiving `0.0`. The cause was a
reduction of the minimum grid-voting leg length from 2.5 m to 0.5 m, which admitted legs far too
short to indicate a building's orientation.

The consequence was not cosmetic. That path is the corridor centreline measured door to door, so its
shortest legs are the hop from a doorway onto the centreline — roughly a corridor's width. Allowing
those to vote meant a doorway jink could rotate the estimated grid, and that grid sets the augmented
arrow's yaw. The threshold has been restored, and the test passes.

## 4.3.5 Outstanding

Quantitative measurement has not yet been carried out. The walked trials establish that guidance
works; they do not yet put numbers on how well.

Three measurements remain:

1. **Dimensional accuracy** of traced plans against a calibrated tape measure, across at least three
   indoor environments (a small room, a corridor, an open hall).
2. **Acoustic classification accuracy** across room types, which will also re-fit the thresholds in
   §4.1.9.
3. **Navigation success rate** over repeated runs in both modes, for sighted and eyes-free users.

Automated testing establishes that instructions are generated consistently from geometry; it cannot
establish that an instruction is correct *in the building*. The walked trials in §4.3.3 are the first
evidence that it is, and quantifying that is the next step.

---


# PART C — CROSS-CUTTING

## C.1 Figure checklist

Chapter 4 marks roughly a dozen figure slots. Screenshots are the cheapest to produce and every
screen exists in both themes, so they cost minutes. Two diagrams are worth real effort.

| Figure | What | Effort |
|---|---|---|
| 4.1 | Implemented layered architecture — redraw of Figure 3.1 | Medium |
| 4.2–4.6 | Screenshots of principal screens, light and dark | Low |
| 4.x | Tracing a plan: photograph, scale, completed floor | Low |
| 4.x | A planned route drawn over a traced floor | Low |
| 4.x | **Registration geometry** — plan frame, ARCore frame, the one point and one direction | **High — do this one properly** |
| 4.x | The AR arrow in a corridor | Low |
| 4.x | A captured sweep, its correlation, and the fitted decay curve | Medium |
| 4.x | Revised entity-relationship diagram — replaces Figure 3.32 | Medium |

The registration diagram is the one to spend time on. It is the most novel idea in the project, it is
the thing least likely to be understood from prose alone, and it is what distinguishes this work from
an application assembled out of plugins.

Figure 3.32 (the old Drift ER diagram) must be redrawn regardless — it describes a database that does
not exist. `supabase/migrations/` is the authoritative source.

---

## C.2 Limitations

`docs/limitations-draft.md` holds the full treatment — eight sections, each traceable to code, now
reconciled with the revised chapters. It is written for Chapter 5 but §4.3.5 draws on it.

The eight, in brief:

1. **Acoustic ranging is not usable at obstacle-aid distances** — approximately 0.6 m floor on
   uncalibrated hardware. Why acoustics does classification, not ranging.
2. **Room classification is functional but unvalidated** — thresholds are physically motivated but
   not yet fitted against measured rooms.
3. **The camera–sound hand-off was designed but not integrated** — `DepthReliability` and
   `AcousticFallbackService` are both implemented and unit-tested, and nothing consumes them. Stated
   plainly rather than described as working.
4. **Mapping a whole building exceeds one contributor** — roughly twenty minutes per floor. This is
   the direct justification for the crowdsourced architecture: the unit of contribution is a floor.
5. **Traced plans carry a residual scale error** — perspective distortion from photographing a board.
6. **Instruction correctness cannot be established by testing** — tests prove instructions are
   generated consistently from geometry, not that the door named is the door seen.
7. **AR guidance is Android-only, and optional** — navigation itself is unaffected.
8. **Measurement is not yet quantified** — the walked trials show it works; numbers are outstanding.

Sections 3 and 8 are the two a reviewer is most likely to press on. Both are stated honestly, which
is the only position that survives a question.

---

## C.3 Open decisions

1. **Title.** Recommended, the shorter alternative, or one of your own. This is the single highest-
   impact change in the document.
2. **Re-walk a route before collecting figures.** The wall-grid threshold that was skewing the
   arrow's yaw has been corrected (§4.3.3), but the walked trials on record predate the fix. Whether
   the heading is now acceptable is an observation nobody has made yet, and it changes what §4.3.3
   should say.

---

## C.4 Settled — do not reopen

These were decided during the cleanup and are reflected consistently throughout Parts A and B. They
are listed so that nobody reintroduces them from an older draft:

- **Capture is out**, in both senses — depth-based room capture and recorded-walk capture. Removed
  from the code, the tests, the native layer and every document. Floor plans are authored by tracing.
- **The evaluation screen is out.** Removed from the code.
- **Map-and-sound guidance is a co-equal navigation mode**, with its own objective (Part A §3,
  Objective 4). Not a fallback, not graceful degradation.
- **Riverpod and Drift were never used.** Bloc and hive_ce. Any sentence naming the former is wrong.
- **The classifier is rule-based, and this is an argued strength**, not a shortfall against the
  TensorFlow Lite the proposal named.
- **PDF export is descoped.** Out of Scope in Part A §4, removed from Deliverable 5 and from both
  tools tables, listed as future work. Sharing happens through the repository, which is the mechanism
  the system is built around. Do not reinstate it in the deliverables without building it.

---

## C.5 What to hand over, and in what order

The supervisor reviews documentation for internal consistency and completeness, and the meeting is
first contact and scored. So the order matters:

1. **The revision note** (Part A §13) — one page, read first, explaining what changed and why.
2. **Revised Chapters 1–3.**
3. **Chapter 4.**
4. **The demonstration**, opened by restating the one-paragraph description above.

Lead with the delta rather than letting it be discovered. A documented change reads as control of the
project; a mismatch found during the demo reads as drift.

---

## C.6 Verification state of the codebase

Anything claimed in Chapter 4 can be checked by running these:

| Check | Command | Result at time of writing |
|---|---|---|
| Static analysis | `flutter analyze` | Clean — 12 issues, no errors |
| Test suite | `flutter test` | 840 pass, none failing |
| Android build | `flutter build apk --debug` | Builds |

The suite is green. Anything a reviewer runs should match the table above; if it does not, the table
is what needs correcting, not the claim.
