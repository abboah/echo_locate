# Assist Mode — How Detection, Direction & Speech Work

Plain-language notes on the "see obstacle → say it out loud" feature.
Written 2026-07-24. Files referenced are current as of that date.

---

## 1. The big picture (one paragraph)

The phone's back camera streams frames. Each frame is handed to **Google ML Kit's
on-device object detector** (a pre-trained model that ships inside the app — no
internet, no server). ML Kit returns, for every object it sees, a **bounding box**
(a rectangle around the object) and a rough **category label**. We do NOT train
any model ourselves. Everything "smart" after that — which side the obstacle is
on, how close it is, when to speak — is ordinary math and rules written by us.
Finally `flutter_tts` (the phone's built-in text-to-speech engine) says the
sentence out loud.

```
Camera frame ──► ML Kit detector ──► DetectedObstacle(s) ──► CalloutPolicy ──► AssistCallout ──► SpeechService (TTS)
   (hardware)      (Google's model)     (our data class)       (our rules)       (the sentence)      (phone speaks)
                                                                                        │
                                                                                        └──► AssistBloc state ──► UI card
```

## 2. File structure — who does what

| File | Role |
|---|---|
| `lib/services/sensing/detection_service.dart` | Owns the camera + ML Kit detector. Converts raw detections into our `DetectedObstacle` objects and pushes them onto a stream. |
| `lib/services/sensing/detected_obstacle.dart` | Tiny data class: label, confidence, heightFraction (proximity proxy), position (left/center/right). |
| `lib/services/sensing/callout_policy.dart` | The "when do we actually speak" rules: pick nearest, ignore far things, cooldowns so TTS doesn't babble. Produces `AssistCallout`. |
| `lib/services/speech/speech_service.dart` | Thin wrapper over `flutter_tts`. `speak(text, interrupt: bool)`. |
| `lib/features/assist/bloc/assist_bloc.dart` (+ event/state) | The brain. Starts the camera, listens to the obstacle stream, runs the policy, triggers speech, emits UI state. Falls back to a scripted demo loop when no camera. |
| `lib/ui/pages/assist/assist_page.dart` | The screen: camera preview + callout card + voice toggle. Pure display; no logic. |
| `lib/services/injection_container.dart` | GetIt wiring: `DetectionService` & `SpeechService` are singletons; `AssistBloc` is a fresh factory per screen visit. |

## 3. The detector (DetectionService)

- Package: `google_mlkit_object_detection`. Options: `DetectionMode.stream`
  (optimized for live video), `classifyObjects: true`, `multipleObjects: true`.
- The **base model** only knows 5 coarse categories: Home good, Fashion good,
  Food, Plant, Place. `_wordFor()` maps them to friendly words
  ("furniture", "plant", "doorway"...). Anything unrecognized → "obstacle".
  A custom TFLite classifier can be swapped in later (Phase 3) for finer labels
  without changing anything downstream.
- **Throttling:** a `_busy` flag means only one frame is analyzed at a time.
  While ML Kit is chewing on a frame, new frames are simply skipped. Slow phone
  = fewer analyzed frames, never a queue building up.
- **Rotation:** camera sensors deliver images sideways. `_currentRotation()`
  computes the correction from sensor orientation + device orientation so
  ML Kit's boxes come back in upright coordinates. When rotated 90°/270°, the
  frame's width/height are swapped before doing the direction math.
- **Debugging:** every analyzed frame logs one `ASSIST-FRAME` line (raw boxes +
  what the policy will see). Grep the logs for `ASSIST-FRAME`.

## 4. Direction — how "on your left" is computed

Take the horizontal center of the bounding box, divide by frame width →
a number from 0 (far left) to 1 (far right):

```
centerX = box.center.dx / frameWidth
< 0.35          → LEFT
0.35 … 0.65     → CENTER ("ahead")
> 0.65          → RIGHT
```

That's the entire direction system: which third of the picture the object is in.

## 5. Distance — the heightFraction trick

Phones can't measure true distance from a single camera. Proxy instead:
**close things look big.** `heightFraction = boxHeight / frameHeight` (0–1).

| heightFraction | Meaning | Spoken as |
|---|---|---|
| < 0.15 | too small/far — ignore, stay quiet | (nothing) |
| 0.15 – 0.30 | far-ish | "a few steps ahead" |
| 0.30 – 0.55 | close | "close" |
| ≥ 0.55 | fills most of the frame | "very close" + **urgent** |

Known limitation (worth stating in the report): a tall-but-far object (a door
across the room) can look "closer" than a short-but-near one (a stool at your
feet). Acceptable trade-off for a single-camera approach.

## 6. CalloutPolicy — from noisy detections to useful speech

The camera produces detections several times per second. Speaking all of them
would be "furniture, furniture, furniture..." — unusable. Rules, in order:

1. **Nearest wins:** of all obstacles in the frame, take the one with the
   largest heightFraction. One announcement per frame, max.
2. **Silence floor:** below 0.15 heightFraction, say nothing.
3. **Cooldown:** identity = `"label:position"` (e.g. `furniture:on your left`).
   Same identity is not repeated within **5 s** (normal) / **2 s** (urgent).
   Moving obstacle → identity changes (left→center) → announces again immediately.
4. **Urgency:** ≥ 0.55 marks the callout `urgent`, which (a) shortens its
   cooldown and (b) makes speech *interrupt* whatever is currently being said.

Output is an `AssistCallout`: `title` ("Furniture on your left"),
`detail` ("very close"), `urgent`, and `spoken` = "title, detail".

## 7. Speech (SpeechService)

- `flutter_tts` = the OS's built-in TTS engine (Google TTS on Android). No
  cloud, no API key.
- Rate set to 0.5 (slower, clearer). `awaitSpeakCompletion(false)` = fire and
  forget, never blocks the pipeline.
- `speak(text, interrupt: true)` calls `stop()` first — urgent callouts cut off
  the current sentence.
- Every call is try/caught: on an emulator with no TTS engine the visual card
  still works.

## 8. AssistBloc — the conductor

- `AssistStarted` → `detection.start()`.
  - Success → status **live**, subscribe to the obstacle stream, announce
    "Assistance started...".
  - Failure (no permission / no camera / emulator) → status **demo**: a 4-second
    timer cycles 4 scripted callouts so the feature is always demonstrable.
- Each stream batch → internal `_ObstaclesArrived` event → policy → if a callout
  survives, emit it (UI card updates) and speak it.
- `AssistVoiceToggled` mutes/unmutes (mute also stops mid-sentence).
- `close()` tears everything down: timer, subscription, camera, TTS, cooldowns.

## 9. Why it's structured this way

- **Services own hardware, Bloc owns decisions, UI owns pixels.** You can unit
  test `CalloutPolicy` with fake obstacles, no camera needed.
- The Bloc subscribes to a GetIt-registered stream (the repo's live-sensing
  pattern from CLAUDE.md).
- Swapping in a smarter model later (custom TFLite labels) touches only
  `DetectionService._wordFor` / detector options — policy, speech, UI unchanged.
