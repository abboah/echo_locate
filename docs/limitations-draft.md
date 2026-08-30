# Limitations — draft

Draft for the limitations section. Every claim below is traceable to code in this
repository; file and line references are given so they can be checked and so the
final prose can drop them.

**Convention:** `⟨MEASURE: …⟩` marks a claim that is currently reasoned rather
than measured. Each one needs a number before submission, or the sentence around
it must be softened to describe a design decision rather than a result.

---

## 1. Acoustic ranging is not usable at the distances an obstacle aid needs

The system implements active acoustic ranging in full: a chirp is generated
(`services/dsp/chirp_generator.dart`), emitted through the device speaker and
recorded, and the return is matched-filtered against the transmitted signal
(`services/dsp/cross_correlation_service.dart`) to recover a time of flight
(`services/dsp/tof_calculator.dart`). The approach is standard and the
implementation is complete.

It is nonetheless unusable for its intended purpose, for a reason that is
physical rather than a defect of implementation. The phone's speaker and
microphone are separated by centimetres, and the speaker continues to ring after
the chirp ends. An echo returning from a surface less than roughly 0.6 m away
arrives while the transmitter is still sounding, and the two are not separable
without a per-device clutter profile characterising that ringing.

Building such a profile per handset was rejected as a design decision rather
than overlooked. The system is crowdsourced and intended for ordinary devices;
requiring each contributor to run a calibration procedure before the aid
functions would defeat the premise. The consequence is recorded explicitly in
the code: `AcousticFallbackService.uncalibratedFloorMeters` is set to 0.6 m
(`services/acoustic/acoustic_fallback_service.dart:28`) and a measurement below
it is refused as `RangeRefusal.belowUncalibratedFloor` rather than reported.

The system therefore refuses to answer at precisely the distances at which an
obstacle warning matters. A second constraint compounds this: measurements are
rate-limited by a four-second cooldown (`acoustic_fallback_service.dart:27`) to
avoid the emitted chirps interfering with each other and with speech output,
giving a maximum update rate of 0.25 Hz — far below what a walking user
requires.

The design response was to treat the camera as the primary sense and sound as a
classification instrument rather than a ranging one. Section 3 describes the
integration that this decision left unfinished.

⟨MEASURE: ranging error against a tape measure at 0.5, 1, 2, 3 and 5 m, ten
readings each, reported as mean absolute error and refusal rate per distance.
`tool/analyze_correlation.dart` and `tool/analyze_wav.dart` produce the
underlying figures. Without this table the 0.6 m floor is an assertion.⟩

---

## 2. Room-type classification is functional but unvalidated

Reverberation time is extracted by Schroeder backward integration
(`services/acoustic/reverb_analyzer.dart`), the method specified by ISO 3382.
A direct 60 dB decay measurement would require a source 60 dB above the room's
noise floor, which a phone speaker cannot produce; the implementation therefore
fits a line over the −5 dB to −25 dB span (a T20 estimate) and extrapolates.
Early decay time is taken over the first 10 dB, and the ratio of the two
provides a measure of how diffuse the space is.

Classification from these features is rule-based rather than learned
(`services/acoustic/room_classifier.dart`). This was deliberate: a learned
classifier requires labelled reverberation samples per room type, a data
collection cost the project plan flagged in advance, and thresholds on RT60 are
defensible from room acoustics in a way that a small network trained on a
handful of samples is not. Sabine's relation ties reverberation time to volume
and absorption, so room classes genuinely do separate along it.

The limitation is that the thresholds have never been fitted to measured rooms.
The values in use — 0.6 s below which a space is classed small, 1.2 s above
which it is classed a hall, a 0.8 diffuseness ratio separating corridors, and a
0.4 s floor below which the ratio test is not applied — are published typical
values used as starting points. The classifier's own documentation states that
evaluation should re-fit them. That step was not reached, so reported
classification behaviour reflects literature values applied to this hardware
rather than performance measured on it.

One measurement artifact was identified and guarded during development, and is
worth reporting because it produces a confident wrong answer rather than an
obvious failure. Backward integration always shows the decay curve collapsing at
the end of the capture buffer, because no energy remains to integrate. A capture
that stopped too early therefore exhibits a steep, smooth and entirely fictitious
decay: a 20 ms capture of a space with roughly 1.5 s of reverberation reported
RT60 = 0.033 s across a full 20 dB fit. The analyser now bounds how far into the
capture a fitted stretch may extend, on the reasoning that a real decay completes
well inside its recording while a spurious one only reaches the target level as
the recording ends.

⟨MEASURE: a confusion matrix over at least three instances each of corridor,
small room and hall, with the room type recorded by inspection. Ten captures per
space. This also supplies the data needed to re-fit the four thresholds, which
would convert this limitation into a result.⟩

---

## 3. The camera–sound hand-off was designed but not integrated

The intended relationship between the two senses was a fallback: camera depth
leads, and where it fails the system asks sound for a distance. Camera depth from
ARCore degrades in low light and against featureless or specular surfaces, and
acoustic ranging fails under unrelated conditions, so the two were expected to
cover each other.

Both halves of the interface exist. `DepthReliability`
(`services/vision/depth_reliability.dart`) judges when a depth frame should not
be trusted, and `AcousticFallbackService`
(`services/acoustic/acoustic_fallback_service.dart`) answers a request for a
range or explains its refusal. Both are unit-tested. The result type
`AcousticRange` carries its provenance and a `calibrated` flag precisely so that
a consumer can tell a sound-derived distance from a camera-derived one, on the
reasoning that the two fail in unrelated ways and a fusion rule must know which
it holds.

Neither is resolved at runtime. Both were registered in the dependency injection
container as a pair and are never requested by any consumer, so the hand-off
described above does not occur in the running application.

The reason is the finding in Section 1. A fallback exists to answer when the
primary sense fails, and depth most often fails at close range against a blank
wall — which is the same region in which acoustic ranging refuses to answer.
Integrating the two would have produced a fallback that declines at exactly the
moments it was built for. The work is reported here as designed and unintegrated
rather than removed from the system, because the interface documents the intended
fusion and the taxonomy of refusal reasons is itself the useful outcome: it
records what the sensor cannot be asked.

---

## 4. Mapping a complete building exceeds what one contributor can do

The system offers two ways to produce a floor plan. A contributor may photograph
a posted floor plan and trace it, which takes roughly twenty minutes per floor
and requires that the building has such a board; or they may walk the space and
place corners in ARCore, which takes roughly twenty minutes per capture session
and requires no board.

Neither scales to a whole building in one sitting. A three-storey building with a
basement, of the kind this work targets, is several hours of contributor effort
by either route, and the ARCore path additionally requires that tracking survive
the whole session — a longer walk accumulates drift and a lost session costs
everything captured in it.

This is a limitation of the capture mechanism, and it is the direct justification
for the crowdsourced architecture. The system does not assume one person maps a
building. Plans are stored per floor, published to a shared backend, and
retrieved by anyone; the unit of contribution is a floor, or a room, not a
building. Distributing the effort is the design response to a cost that cannot be
removed.

A second constraint follows from the same per-floor structure. Routing over
traced plans is computed within a single floor: `RoomGraph` builds the graph for
one floor (`services/mapping/room_graph.dart:162`), and a `RoomPlan` is keyed by
building and floor. Staircases are recorded during tracing and become stairway
landmarks, so a route may be told to reach a staircase, but a single route
crossing from one traced floor to another is not computed. The landmark graph
built from recorded walks does represent floor changes, placing the two nodes of
a staircase at the same plan position and describing the stairs rather than
generating a turn instruction (`services/mapping/route_planner.dart:285`), so
the capability is present on that path but not on the traced-plan path.

Evaluation is accordingly reported per floor rather than per building.

⟨MEASURE: actual elapsed time to trace one real floor and to capture one real
room, timed rather than estimated. Two numbers, and they make this section a
measured constraint instead of a projection.⟩

---

## 5. Traced plans carry a residual scale error

Photographing a posted floor plan introduces perspective distortion: the board is
photographed from wherever there is room to stand, so the far edge is
foreshortened, parallel corridors converge, and rectangular rooms become
trapezia. Tracing directly on such a photograph would bake this distortion into
the plan invisibly, because the traced rooms sit perfectly on the photograph —
the photograph being wrong in exactly the same way.

This is corrected by a homography (`services/mapping/board_rectification.dart`).
Four board corners, tapped once, define the projective map from photograph to
plan, and every subsequent tap is transformed through it. Warping the
coordinates achieves the same correction as warping the image at a fraction of
the cost.

The correction is not complete. Recovering a rectangle's true proportions from a
perspective view requires the camera's focal length, which the system does not
have; the aspect ratio is therefore estimated by averaging opposite edge lengths.
This is accurate for a board photographed roughly face-on and degrades as the
angle increases. The residual error is a uniform stretch along one axis, so a
plan may be slightly tall or slightly wide relative to the building.

The consequences are bounded and were considered in the design. Routing is
unaffected, because A* compares edge lengths with one another and a uniform
stretch preserves their ordering. Door ordinals are unaffected, because
"the second door on your left" depends on order along a corridor rather than
distance. Absolute distances are affected — which is why a plan traced from an
unmeasured board carries no metres-per-unit scale, and the guidance layer omits
spoken distances entirely rather than quoting a figure derived from arbitrary
units (`services/mapping/room_directions.dart`). Instructions in that case rely
on doors and landmarks, which remain true regardless of scale.

⟨MEASURE: for one traced floor, compare a handful of traced room dimensions
against tape measurements, and report the topology precision and recall that
`services/evaluation/plan_evaluation.dart` computes against the adjacencies read
off the same board.⟩

---

## 6. Instruction correctness cannot be established by testing

The implementation is supported by 945 automated tests and passes static
analysis without warnings. This establishes internal consistency; it does not
establish that the spoken guidance is correct.

The clearest case is a left/right inversion. Such an error survives every test in
the suite: the geometry remains self-consistent, the generated sentence is
well-formed, the route is traversable, and the instruction is wrong. No amount of
additional unit testing detects it, because the fault lies in the correspondence
between the model and the physical building rather than within the model.

The evaluation design reflects this rather than working around it. Plan topology
is scored automatically, since adjacencies read from a posted board are ground
truth and precision and recall over graph edges are arithmetic. Route instruction
correctness is not scored at all: `auditRoutes` generates the routes to be walked
and a structure in which to record what happened, and computes no figure. The
only instrument that detects an inverted turn is a person walking the route.

⟨MEASURE: walked route audits. This is the one number in the evaluation that
cannot be obtained without leaving the desk, and its absence is the weakest point
of the current results.⟩

---

## 7. Depth capture and augmented guidance are Android-only

All ARCore-dependent capability is gated on the platform and reports itself
unsupported elsewhere (`services/vision/arcore_depth_service.dart:40`,
`arcore_capture_service.dart:197`, `ar_guidance_service.dart:217`). This affects
room capture, the depth readout, and the augmented-reality arrow. Equivalent iOS
support would require a parallel ARKit implementation, which was outside scope.

Platform-independent capability is unaffected: tracing plans from photographed
boards, routing, spoken guidance, obstacle detection and sign reading through
ML Kit, and the crowdsourced backend all operate without ARCore. A device without
ARCore support is therefore able to consume every published plan and be guided by
it, and is unable to contribute plans captured by walking.

---

## 8. Evaluation data (remove this section once collected)

The evaluation instruments are implemented and tested but have not been run
against real buildings. Section 5's topology scoring, Section 2's classification
accuracy, Section 1's ranging error and Section 6's walked route audits are all
currently unpopulated.

This is the largest gap in the present work and it is not a design limitation:
the instruments exist, the ground truth is free — posted floor plans in buildings
that can be walked into — and the data collection is a matter of hours rather
than weeks. Every `⟨MEASURE⟩` marker above identifies a specific table that this
section will otherwise leave empty.
