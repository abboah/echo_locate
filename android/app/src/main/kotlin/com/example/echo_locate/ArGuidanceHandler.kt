package com.example.echo_locate

import android.app.Activity
import android.content.Context
import android.content.pm.PackageManager
import android.hardware.camera2.CameraCharacteristics
import android.hardware.camera2.CameraManager
import android.media.Image
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.core.content.ContextCompat
import com.google.ar.core.Anchor
import com.google.ar.core.ArCoreApk
import com.google.ar.core.CameraConfig
import com.google.ar.core.CameraConfigFilter
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Pose
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.NotYetAvailableException
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.floor
import kotlin.math.min
import kotlin.math.sin

/**
 * AR guidance — the arrow on the floor that says which way to walk.
 *
 * ## Two ways of knowing where to point, and the difference between them
 *
 * **A registered route** ([RegisteredRoute]) is the good one. Dart solves one
 * rotation and one translation between the floor plan and ARCore's world — see
 * `route_registration.dart` — hands the whole path over in world coordinates,
 * and from then on nothing is guessed: the walker's position is a projection
 * onto a known line, the next corner is a known point, and the arrow aims at
 * the place. This is what lets the app walk somebody from one room to another
 * rather than merely pace them down a corridor.
 *
 * **A dead-reckoned leg** ([LegAnchor]) is the fallback, and it runs whenever
 * a route cannot be registered: a walk stitched out of recordings, which has
 * turns and lengths but no coordinates, or a traced plan nobody measured,
 * which has coordinates in no unit. A leg is anchored from the walker's
 * **direction of travel** turned by the leg's `turnDeg`, and it can only ever
 * mean "keep going the way you set off, for so many metres". Each leg is
 * measured from the last, so the first one's error rides through the whole
 * walk and nothing downstream can correct it.
 *
 * The route wins wherever both exist — [drawFrame] and [emitState] check for
 * it first, and [servicePendingRoute] drops the leg when one arrives.
 *
 * ## The walk is handed out in pieces
 *
 * The walker is never sent the whole length of a corridor at once. It is
 * divided into [CHECKPOINT_M] checkpoints, and the ring on the floor is always
 * on the next one — or on the next real corner, where a registered route has
 * one nearby, because a corner is somewhere they can verify they have reached.
 * The arrow aims a little past the ring, so it has something far enough away
 * to point at steadily while the ring marks where to stop.
 *
 * ## Drift, and what bounds it
 *
 * On a leg, drift never accumulates across the walk: every landmark
 * confirmation re-anchors from scratch, so the only error that matters is what
 * accrued over one corridor — a degree or two of heading over twenty metres,
 * which an arrow absorbs without anybody noticing.
 *
 * On a registered route the bound is ARCore's own odometry over the whole
 * walk, which is a few percent of distance. The difference that matters is
 * that this error is *visible*: [RegisteredRoute.offsetM] measures how far the
 * walker is from the line, so a registration that came out wrong announces
 * itself instead of quietly steering somebody into a wall.
 *
 * ## Direction of travel, not the compass and not the camera
 *
 * The heading comes from where the walker has *moved*, not from where the phone
 * is pointing and not from the magnetometer. Indoors the magnetometer is
 * unusable — rebar, steel doorframes, lift motors — and the phone's own
 * bearing swings wildly as somebody sweeps it looking for a sign. Net
 * translation over a couple of metres is stable and is what "forward" actually
 * means to a person walking.
 *
 * When there is no recent motion to read — at the very start of a route, phone
 * in hand, standing still — the camera's bearing is used instead and Dart is
 * told, so the screen can ask for a few steps rather than confidently pointing
 * the wrong way.
 *
 * ## The camera is shared, not taken
 *
 * ARCore holds the camera exclusively, which would leave sign reading and
 * obstacle detection — the things that make guidance work for a blind user —
 * dead while this screen is up. So CPU frames are pulled off the ARCore session
 * and shipped to Dart, where the existing ML Kit pipeline consumes them
 * unchanged. See [FRAME_CHANNEL].
 */
class ArGuidanceHandler(
    private val activity: Activity,
    private val textures: TextureRegistry,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "echo_locate/ar_guidance"
        const val EVENT_CHANNEL = "echo_locate/ar_guidance/state"
        const val FRAME_CHANNEL = "echo_locate/ar_guidance/frames"
        private const val TAG = "ArGuidance"

        // --- Kill switches --------------------------------------------------
        //
        // Two changes made on 29 August 2026 that have never run on a device.
        // Both are improvements on paper and both touch the frame loop, so each
        // has a switch here: flip it to false, rebuild, and this file behaves
        // exactly as the build that came before it. They are compile-time
        // constants rather than settings on purpose — there is no scenario
        // where a walker should be choosing between them mid-route, and a
        // constant is the one kind of switch that cannot be in the wrong state
        // for reasons nobody can reconstruct afterwards.
        //
        // Which line of the log says what a given capture was built with:
        //
        //     AR guidance session: floor=measured anchors=following
        //
        /**
         * Whether the floor height is measured from a fitted plane.
         *
         * False falls back to [EYE_HEIGHT_M] and never turns plane finding on
         * at all. **Turn this off first if the session stutters on entry**:
         * plane fitting costs CPU for the first [FLOOR_SEARCH_MS], and it is
         * competing with the ML Kit frame feed on hardware where the camera
         * path was measured at 60 fps *without* it.
         *
         * The cost of false is cosmetic — the ring sits at an assumed height
         * instead of a measured one.
         */
        private const val MEASURE_FLOOR = true

        /**
         * Whether the route and the leg are pinned to ARCore anchors and
         * rebuilt from them each frame — see [followAnchors].
         *
         * Set to false to keep raw world coordinates fixed in ARCore space,
         * preventing anchor yaw jitter from rotating 20-metre corridor lines into walls.
         */
        private const val FOLLOW_ANCHORS = false

        /**
         * How far below the phone the floor is assumed to be, in metres.
         *
         * **The fallback, not the answer.** [servicePlaneSearch] measures the
         * floor for real in the first few seconds of a session and this is what
         * stands in until it does — or permanently, on a corridor where plane
         * fitting never converges.
         *
         * It is wrong for most people by construction: it is one number for a
         * user who may be 1.5 m or 1.9 m tall, holding the phone at their chest
         * or down by their hip for an eyes-free walk. The ring then sits above
         * or below the floor, and a ring that floats reads as an arrow that is
         * lying — which is why measuring it was worth the plane fitting the
         * session otherwise avoids.
         */
        const val EYE_HEIGHT_M = 1.35f

        /**
         * How long plane finding runs before the session gives up on it.
         *
         * Plane fitting is on for these first seconds and then switched off for
         * good — see [servicePlaneSearch]. The CPU it costs is CPU ML Kit is not
         * getting, and ML Kit is what reads the door plates this app navigates
         * by, so it is borrowed briefly rather than kept.
         *
         * Raised from 9 s once the search acquired a second job. Nine seconds
         * was tuned for a floor, which is underfoot from the first frame; a
         * corridor's *walls* are only fitted once the walker has moved along
         * them far enough to give ARCore parallax, and that is the same three
         * metres [MIN_TRAVEL_FOR_REGISTRATION_M] waits for. A window that shuts
         * before the walker has set off cannot see the thing it is looking for.
         */
        private const val FLOOR_SEARCH_MS = 20000L

        /**
         * How much of a vertical plane has to be fitted before it counts as a
         * wall.
         *
         * Larger than [FLOOR_MIN_AREA_M2] because the things that are vertical
         * and are not walls — a door left ajar, the side of a bookcase, a
         * person standing still — are small, and a wrong bearing here rotates
         * the whole building. A corridor wall gives several square metres
         * within a few paces of walking down it.
         */
        private const val WALL_MIN_AREA_M2 = 0.6f

        /**
         * How far a wall may lean off true vertical and still be believed.
         */
        private const val WALL_MAX_TILT_DEG = 15f

        /**
         * How many walls must agree before the grid they imply is used.
         * A single detected corridor wall provides the physical corridor axis.
         */
        private const val WALL_GRID_MIN_PLANES = 1

        /**
         * How tightly the walls have to agree, in degrees on the folded grid.
         */
        private const val WALL_GRID_MAX_SPREAD_DEG = 15f

        /**
         * How far below the phone a horizontal plane has to be to be the floor.
         *
         * The window exists to rule out the two things that are not the floor
         * and look like it to a plane fitter: a desk or a handrail, which is too
         * close under the phone, and a stairwell's lower landing seen over a
         * banister, which is too far.
         */
        private const val FLOOR_MIN_DROP_M = 0.7f
        private const val FLOOR_MAX_DROP_M = 2.1f

        /**
         * How much of a plane has to have been fitted before it is believed.
         *
         * A square metre — smaller than that and it is as likely to be a chair
         * seat caught at the right height as a corridor.
         */
        private const val FLOOR_MIN_AREA_M2 = 1f

        /** Trajectory sample spacing, in metres. */
        private const val TRAIL_STEP_M = 0.15f

        /**
         * How many samples back the travel direction is measured over.
         *
         * Sized so the ring can still hold [MIN_TRAVEL_FOR_REGISTRATION_M] of
         * *net* displacement with room to spare. At [TRAIL_STEP_M] spacing this
         * is 6 m of path, and a walker who curves a little covers less ground
         * than they walk — a ring sized exactly to the threshold would never
         * reach it on anything but a perfectly straight corridor.
         */
        private const val TRAIL_SAMPLES = 40

        /**
         * Net movement needed before the travel direction is trusted.
         *
         * Below this, the samples describe somebody shuffling on the spot and
         * the direction they imply is noise pointed at a corridor.
         *
         * This is the *leg* threshold, and it is deliberately short: a leg
         * anchored from a rough heading is corrected a few metres later by
         * [refineCameraAnchor], so being early costs little and waiting costs
         * the walker arrows on the first stretch of every corridor.
         */
        private const val MIN_TRAVEL_FOR_HEADING_M = 0.7f

        /**
         * Net movement needed before a heading may be used to *register*.
         *
         * Much longer than [MIN_TRAVEL_FOR_HEADING_M], and the reason is the
         * lever arm. A leg's heading is wrong for one corridor and is fixed at
         * the next landmark; a registration's heading rotates the entire
         * building and nothing downstream can correct it (`recentredAt` keeps
         * the yaw — one point says nothing about rotation). An error of theta
         * puts a ring at distance d off the line by d*sin(theta), so fifteen
         * degrees solved from a doorway lands a ring five metres out at twenty.
         *
         * Matched to `ArGuidanceCubit._departureM`, which measures the plan's
         * departure direction over three metres of route. Both sides of the
         * correspondence now describe the same length of walking; before this
         * they were 3 m of plan against 0.7 m of world, and the mismatch went
         * straight into the yaw.
         */
        private const val MIN_TRAVEL_FOR_REGISTRATION_M = 1.5f

        /**
         * A jump this big between two trajectory samples is not walking.
         *
         * ARCore corrects the pose when it relocalises, and the correction lands
         * as a single enormous step. Averaged into the trail it invents a
         * direction of travel nobody walked, pointing wherever the correction
         * happened to go — so a discontinuity throws the trail away instead.
         */
        private const val MAX_SAMPLE_JUMP_M = 1.2f

        /**
         * How long tracking may drop before the anchored leg is abandoned.
         *
         * A blink — a hand over the lens, a dark doorway — leaves the anchor
         * alone, because re-anchoring costs a leg's worth of accuracy. A real
         * relocalisation moves the world under the arrows, and then they are
         * pointing at a corridor that has moved: better to ask for a fresh
         * anchor than to draw a confident line down the wrong one.
         */
        private const val RELOCALISE_GRACE_MS = 1500L

        /**
         * A leg this near to straight ahead can be re-anchored off motion.
         *
         * See [refineCameraAnchor]. On a straight leg, "the way the walker is
         * moving" and "the way the leg runs" are the same line, so the first
         * few steps can correct a guessed anchor. On a leg with a real turn in
         * it they are not: those steps are already *past* the turn, and turning
         * them again by the same angle would send the arrows round twice.
         */
        private const val STRAIGHT_ENOUGH_DEG = 25

        /** How far into a leg a guessed anchor may still be corrected. */
        private const val REFINE_WINDOW_M = 2.5f

        /**
         * How close a point may be before the arrow stops aiming at it.
         *
         * See [needleBearing]. Standing on a point, the bearing *to* it is
         * whatever direction the last footstep happened to leave it in, so the
         * arrow would spin exactly as the walker reached the thing it was
         * sending them to. Set at a stride and a half.
         */
        private const val NEAR_TARGET_M = 1.5f

        /**
         * How far apart the checkpoints along a leg are, in metres.
         *
         * The unit the walk is handed out in: the ring is on the next one of
         * these, never on the far landmark, so a twenty-metre corridor is
         * walked as seven short hops rather than presented whole. Three metres
         * is about four paces — near enough that the ring is always visibly
         * *there* on the floor ahead, far enough that they do not arrive at one
         * before the last has been understood.
         *
         * Dart keeps the same figure for the spoken cues (`GuidanceBloc`), and
         * both read the same clock — the cumulative metres reported from here —
         * so what is said and what is drawn advance together.
         */
        const val CHECKPOINT_M = 3f

        /** How often the walk is written to the log while a leg is anchored. */
        private const val WALK_LOG_MS = 1000L

        /**
         * A bend in the route sharper than this is a corner, not a wiggle.
         *
         * Decides whether the arrow may aim past the next vertex. A traced
         * corridor is a hand-drawn polyline with a degree or two of jitter in
         * every vertex, and treating those as corners would stop the arrow
         * looking ahead at all — it would sit on each vertex in turn, swinging
         * as the walker reached it. A real corridor junction is nothing like
         * that shallow.
         */
        private const val TURN_IS_A_CORNER_DEG = 35f

        /**
         * Floor on the gap between analysis frames, in milliseconds.
         *
         * Not the rate — the rate is set by how fast ML Kit finishes, which is
         * reported back per frame. This only stops a phone that analyses very
         * quickly from being asked to copy a camera image sixty times a second.
         */
        private const val ANALYSIS_MIN_INTERVAL_MS = 60L

        /**
         * How long to wait for Dart to say it has finished with a frame.
         *
         * The feed is one-frame-at-a-time: a new frame is copied only once the
         * last has been analysed, so nothing is spent on images that would be
         * dropped, and the rate lands wherever the hardware puts it. If the
         * answer never comes — a screen torn down mid-analysis, an exception
         * swallowed somewhere — this is what stops sign reading going silent
         * for the rest of the walk.
         */
        private const val ANALYSIS_ACK_TIMEOUT_MS = 1500L

        /** Heartbeat for the state stream, so the UI never sits stale. */
        private const val STATE_HEARTBEAT_MS = 500L

        /**
         * Fastest the state stream is pushed, in milliseconds.
         *
         * Distance is quantised to a quarter-metre and bearing to five degrees,
         * so past this rate every push carries the same numbers as the last one
         * — and each is a Bloc state and a widget rebuild. Tracking loss still
         * reaches the screen inside a tenth of a second, which is far quicker
         * than anybody can react to it.
         */
        private const val STATE_INTERVAL_MS = 100L

        /** Frame-loop pause when there is no surface to draw into. */
        private const val IDLE_FRAME_MS = 16L

        /**
         * Attempts at `resume()` before giving up on the camera.
         *
         * Coming here from the capture screen hands the camera over between two
         * ARCore sessions, and the old one releases it asynchronously — so the
         * first resume can lose a race that the second one wins.
         */
        private const val CAMERA_ATTEMPTS = 3
        private const val CAMERA_RETRY_MS = 250L
    }

    private var session: Session? = null
    private var eventSink: EventChannel.EventSink? = null

    private var renderThread: HandlerThread? = null
    private var renderHandler: Handler? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private val gl = ArGlSurface(textures)
    private val renderer = CameraBackgroundRenderer()
    private val arrows = ArrowRenderer()

    private var startedTextureId: Long = -1L

    @Volatile
    private var running = false

    // Written on the platform thread, read on the render thread every frame.
    @Volatile
    private var viewWidth = 0

    @Volatile
    private var viewHeight = 0

    @Volatile
    private var displayRotation = 0

    /** Sensor orientation of the camera ARCore chose, for ML Kit's rotation. */
    @Volatile
    private var sensorOrientation = 90

    /**
     * Whether the next analysis frame is for sign reading rather than obstacles.
     *
     * Set from Dart on each acknowledgement — it is the side that decides whose
     * turn it is. False to begin with, so the first frame of a session is a
     * full field of view: obstacles are what a walker can be hurt by.
     */
    @Volatile
    private var analysisWantsText = false

    /**
     * The camera claim, held as one object.
     *
     * [ArCoreSessionOwner] compares holders by identity, and `::stop` builds a
     * fresh bound reference every time it is written — so claiming with one and
     * releasing with another leaves this handler recorded as the owner of a
     * session it has already closed.
     */
    private val releaseSelf: () -> Unit = { stop() }

    // --- Trajectory ---------------------------------------------------------

    private val trailX = FloatArray(TRAIL_SAMPLES)
    private val trailZ = FloatArray(TRAIL_SAMPLES)
    private var trailCount = 0
    private var trailHead = 0

    /** The direction of travel in radians, or null when there is no motion. */
    private var travelHeading: Float? = null

    /**
     * The same direction, withheld until it is worth registering against.
     *
     * Null until the trail carries [MIN_TRAVEL_FOR_REGISTRATION_M] of net
     * displacement, and null again after every [resetTrail] — a heading built
     * from a rebuilt trail describes wherever the walker happens to be going
     * now, which is what the late-registration path in Dart exists to handle.
     */
    private var registrationHeading: Float? = null

    /** Tracking as of the previous frame, for spotting the transitions. */
    @Volatile
    private var wasTracking = false

    /** When tracking was lost, for telling a blink from a relocalisation. */
    private var lostTrackingAt = 0L

    // --- The floor ----------------------------------------------------------

    /**
     * Where the floor actually is in world y, once a plane has been fitted to
     * it. Null until then, and forever on a session that never finds one.
     */
    @Volatile
    private var measuredFloorY: Float? = null

    /** When the session started looking, for giving up on time. */
    private var floorSearchStartedAt = 0L

    /** Whether plane finding is still switched on. */
    private var searchingForFloor = false

    // --- The walls ----------------------------------------------------------

    /**
     * The building's rectilinear grid in world radians, folded to [0, pi/2).
     *
     * This is the one absolute direction ARCore can give that does not come
     * from the walker's own motion, and it is the missing input to the
     * registration. A corridor's walls run along the building; their normals,
     * flattened onto the floor and folded by ninety degrees, all name the same
     * angle whichever wall was seen and whichever way round it faced.
     *
     * Folded rather than absolute because a normal cannot say which side of
     * the wall it is on and a plan cannot say which of its four rectilinear
     * directions is "north". Dart resolves the quarter-turn ambiguity against
     * the travel heading, which only has to be right to within forty-five
     * degrees to pick the right quadrant — and it comfortably is, even at the
     * short baseline. See `Registration.snappedToGrid`.
     *
     * Null until enough walls agree, and on any session where they never do.
     */
    @Volatile
    private var wallGridRad: Float? = null

    // --- The leg ------------------------------------------------------------

    @Volatile
    private var pendingLeg: PendingLeg? = null

    @Volatile
    private var legAnchor: LegAnchor? = null

    /**
     * The ARCore anchor holding the leg's origin in the building — see
     * [followAnchors]. Null when the session refused one, which leaves the leg
     * on the raw coordinates it was built from.
     */
    @Volatile
    private var legAnchorPin: Anchor? = null

    /** The pin's yaw when it was made, so its later yaw is a *change*. */
    private var legAnchorYaw = 0f

    /** The leg's direction in the pin's frame, which does not change. */
    private var legLocalDirX = 0f
    private var legLocalDirZ = 0f

    /** Whether the current leg was anchored off the camera rather than motion. */
    private var anchoredFromCamera = false

    /** How far along the *current anchor* the walker has come. */
    private var walkedM = 0f

    /**
     * Metres walked on this leg before the current anchor existed.
     *
     * A leg can be anchored more than once — ARCore relocalises, or a guessed
     * anchor is corrected off real motion — and each re-anchor starts its own
     * [walkedM] from zero at wherever the walker is standing. Without this,
     * every re-anchor would rewind the leg: the checkpoints would start again
     * from the walker's feet and Dart would hear its progress clock run
     * backwards, re-speaking cues it had already spoken. Added back in, the
     * pair report one number that only ever goes up within a leg.
     */
    private var legWalkedBase = 0f

    /** How far along the whole leg the walker has come. */
    private val legWalkedM: Float get() = legWalkedBase + walkedM

    private var lastWalkLogAt = 0L

    /**
     * The leg [legAnchor] was built from, kept so it can be built again.
     *
     * Only [refineCameraAnchor] uses it: correcting a guessed anchor needs the
     * turn that produced it, and that number lives in Dart otherwise.
     *
     * Volatile because `clearLeg` and [stop] null it from the platform thread
     * while the frame loop is reading it — the same reason [legAnchor] and
     * [pendingLeg] are.
     */
    @Volatile
    private var activeLeg: PendingLeg? = null

    private data class PendingLeg(val turnDeg: Int, val distanceM: Float)

    // --- The registered route -----------------------------------------------

    /**
     * The route in world coordinates, when Dart has managed to register one.
     *
     * Takes precedence over [legAnchor] wherever both exist: a leg is dead
     * reckoning from a guessed heading and this is a known line in a known
     * place, so there is nothing the leg can say that this does not say
     * better. The leg is kept, not deleted, because a route without a scale or
     * without a plan behind it cannot be registered at all and the leg is
     * still the only thing those walks have.
     */
    @Volatile
    private var route: RegisteredRoute? = null

    /** Points waiting for a frame to read the floor height off. */
    @Volatile
    private var pendingRoute: List<Double>? = null

    /**
     * The ARCore anchor the whole route hangs off — see [followAnchors].
     *
     * One anchor for the route rather than one per vertex, deliberately. A
     * route is a rigid thing: the corridors of a building do not move relative
     * to each other, and anchoring each corner separately would let ARCore's
     * per-anchor noise bend the plan into shapes the building does not have.
     */
    @Volatile
    private var routeAnchor: Anchor? = null

    /** The anchor's yaw when it was made, so its later yaw is a *change*. */
    private var routeAnchorYaw = 0f

    /** The route in the anchor's frame — the copy that never changes. */
    private var routeLocalX = FloatArray(0)
    private var routeLocalZ = FloatArray(0)

    /** Scratch for the rebuilt world coordinates, so no frame allocates. */
    private var routeWorldX = FloatArray(0)
    private var routeWorldZ = FloatArray(0)

    private var lastRouteLogAt = 0L

    /**
     * The bearing the arrow was last drawn at, for the state stream to quote.
     *
     * Recomputing it in [emitState] would be the same trigonometry against a
     * pose one frame newer, and the screen's words would disagree with its
     * arrow by however much the phone moved in between. Cheaper and more
     * honest to report what was drawn.
     */
    @Volatile
    private var lastRouteBearingDeg = 0f

    /** Scratch for [RegisteredRoute.pointAt], reused so the frame loop is allocation-free. */
    private val markPoint = FloatArray(2)
    private val aimPoint = FloatArray(2)

    // --- Analysis -----------------------------------------------------------

    @Volatile
    private var analysisEnabled = false
    private var lastAnalysisAt = 0L
    private var nv21 = ByteArray(0)

    /** Whether a frame is with ML Kit and has not been answered for yet. */
    @Volatile
    private var analysisInFlight = false

    private var analysisSentAt = 0L

    private var frameSink: EventChannel.EventSink? = null

    /**
     * Camera frames for ML Kit, on their own channel.
     *
     * Separate from the state channel on purpose: this one carries a few
     * hundred kilobytes several times a second, and the state channel carries a
     * handful of numbers that the screen redraws from. Sharing one channel
     * would put the small, latency-sensitive messages in a queue behind the
     * large ones.
     */
    val frames: EventChannel.StreamHandler = object : EventChannel.StreamHandler {
        override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
            frameSink = events
        }

        override fun onCancel(arguments: Any?) {
            frameSink = null
        }
    }

    // --- MethodChannel ------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkAvailability" -> result.success(availabilityString())
            "requestInstall" -> requestInstall(result)
            "start" -> start(call, result)
            "stop" -> {
                stop()
                result.success(null)
            }
            "setViewport" -> {
                applyViewport(call)
                result.success(null)
            }
            "setLeg" -> {
                // Serviced on the next frame, where there is a live pose to
                // read the walker's direction from. Holding a Frame across the
                // channel boundary would be a use-after-free the moment the
                // pump ran.
                pendingLeg = PendingLeg(
                    turnDeg = call.argument<Int>("turnDeg") ?: 0,
                    distanceM = (call.argument<Double>("distanceM") ?: 0.0).toFloat(),
                )
                // A leg issued from Dart is a new leg — a landmark was
                // confirmed — so the progress clock starts over. This is the
                // only place it may.
                legWalkedBase = 0f
                result.success(null)
            }
            "clearLeg" -> {
                legAnchor = null
                releaseLegAnchorPin()
                pendingLeg = null
                activeLeg = null
                walkedM = 0f
                legWalkedBase = 0f
                result.success(null)
            }
            "setRoute" -> {
                // The whole route at once, already in ARCore's world — Dart
                // solved the registration (`route_registration.dart`) and did
                // the transform, because the plan geometry it needs to do that
                // lives there and the frame conventions are pinned by tests
                // there. Serviced on the next frame for the same reason
                // `setLeg` is: the floor height comes off a live pose.
                val flat = call.argument<List<Double>>("points")
                if (flat == null || flat.size < 4 || flat.size % 2 != 0) {
                    result.error(
                        "badRoute",
                        "setRoute needs at least two (x, z) pairs",
                        null,
                    )
                } else {
                    pendingRoute = flat
                    result.success(null)
                }
            }
            "clearRoute" -> {
                route = null
                releaseRouteAnchor()
                pendingRoute = null
                result.success(null)
            }
            "setAnalysis" -> {
                analysisEnabled = call.argument<Boolean>("enabled") ?: false
                analysisInFlight = false
                result.success(null)
            }
            "analysisDone" -> {
                // ML Kit has finished with the last frame, so the next one is
                // worth copying. This is the whole pacing mechanism: without it
                // the feed is a guess at how fast the phone is, and the guess
                // is either wasteful or slow at reading signs.
                //
                // It also carries what the next frame is *for*. Sign reading
                // wants a magnified crop of the middle and obstacle detection
                // wants the whole field of view, and Dart is the side that
                // knows which is next — see [AnalysisFraming].
                analysisWantsText = call.argument<Boolean>("wantsText") ?: false
                analysisInFlight = false
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Whether the user has already been shown the install prompt this run.
     *
     * ARCore's own contract: ask with `true` once, and if the install is
     * requested the activity is paused while Play does its work. Asking with
     * `true` again on the way back would show the prompt a second time to
     * somebody who has just answered it.
     */
    private var userRequestedInstall = true

    /**
     * Asks Play to install or update ARCore, if that is what is missing.
     *
     * ## Why this has to exist
     *
     * "Supported" and "installed" are different questions, and only the second
     * one lets a session start. A brand new phone off the shelf is
     * `SUPPORTED_NOT_INSTALLED`: ARCore runs on it, and Google Play Services
     * for AR is not on it yet. Without this call the app read that as "no AR
     * here", fell back to voice guidance, and said nothing — a silent failure
     * on hardware that was one Play dialog away from working.
     *
     * The install itself happens outside the app. The caller re-checks
     * availability when the user comes back.
     */
    private fun requestInstall(result: MethodChannel.Result) {
        try {
            when (ArCoreApk.getInstance().requestInstall(activity, userRequestedInstall)) {
                ArCoreApk.InstallStatus.INSTALLED -> {
                    result.success("installed")
                }
                ArCoreApk.InstallStatus.INSTALL_REQUESTED -> {
                    // Play has it now, and this activity is about to be paused.
                    userRequestedInstall = false
                    result.success("requested")
                }
                null -> result.success("unavailable")
            }
        } catch (e: UnavailableException) {
            // A device Google has not certified. Permanent, and not an error:
            // the app is built to walk people around buildings without ARCore.
            Log.i(TAG, "ARCore cannot be installed on this device: $e")
            result.success("unavailable")
        } catch (e: Exception) {
            Log.w(TAG, "ARCore install request failed: $e")
            result.success("unavailable")
        }
    }

    private fun availabilityString(): String =
        when (ArCoreApk.getInstance().checkAvailability(activity)) {
            ArCoreApk.Availability.SUPPORTED_INSTALLED -> "supported"
            ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD -> "supportedApkTooOld"
            ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED -> "supportedNotInstalled"
            ArCoreApk.Availability.UNSUPPORTED_DEVICE_NOT_CAPABLE -> "unsupported"
            ArCoreApk.Availability.UNKNOWN_CHECKING -> "checking"
            ArCoreApk.Availability.UNKNOWN_ERROR -> "error"
            ArCoreApk.Availability.UNKNOWN_TIMED_OUT -> "timedOut"
        }

    private fun currentDisplayRotation(): Int = try {
        @Suppress("DEPRECATION")
        val display = if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.R) {
            activity.display
        } else {
            activity.windowManager.defaultDisplay
        }
        display?.rotation ?: Surface.ROTATION_0
    } catch (e: Exception) {
        Log.w(TAG, "Display rotation unavailable, assuming portrait: $e")
        Surface.ROTATION_0
    }

    private fun applyViewport(call: MethodCall) {
        val width = (call.argument<Int>("width") ?: 0).coerceAtLeast(1)
        val height = (call.argument<Int>("height") ?: 0).coerceAtLeast(1)
        val rotation = currentDisplayRotation()
        if (width == viewWidth && height == viewHeight && rotation == displayRotation) return

        viewWidth = width
        viewHeight = height
        displayRotation = rotation
        gl.resizeProducer(width, height)

        renderHandler?.post {
            try {
                session?.setDisplayGeometry(displayRotation, viewWidth, viewHeight)
            } catch (e: Exception) {
                Log.w(TAG, "setDisplayGeometry failed: $e")
            }
            gl.rebind()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        if (running) {
            result.success(mapOf("textureId" to startedTextureId))
            return
        }
        viewWidth = (call.argument<Int>("width") ?: 0).coerceAtLeast(1)
        viewHeight = (call.argument<Int>("height") ?: 0).coerceAtLeast(1)
        displayRotation = currentDisplayRotation()

        if (ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.CAMERA,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            result.error("permission", "Camera permission not granted", null)
            return
        }

        val availability = availabilityString()
        if (availability != "supported") {
            result.error("unavailable", "ARCore not available: $availability", null)
            return
        }

        ArCoreSessionOwner.claim(releaseSelf)

        try {
            val newSession = Session(activity)
            chooseCameraConfig(newSession)
            newSession.configure(
                newSession.config.apply {
                    // Planes, briefly, for two numbers: where the floor is and
                    // which way the building runs. [servicePlaneSearch]
                    // switches this off again the moment it has both, or after
                    // [FLOOR_SEARCH_MS], because every cycle not spent fitting
                    // planes to a bare corridor floor is a cycle ML Kit can
                    // have — and ML Kit is what reads the signs this app
                    // navigates by.
                    //
                    // Vertical planes were previously off, and the wall grid
                    // is why they are on: it is the only absolute direction
                    // ARCore can supply that does not come from the walker's
                    // own motion, and the registration's yaw — which rotates
                    // the entire building and is never corrected afterwards —
                    // had nothing else to lean on. Walls cost more to fit than
                    // a floor, which is the other half of why the window was
                    // widened rather than the search made permanent.
                    //
                    // Depth stays off. It would buy occlusion, so the arrow
                    // stopped drawing through walls, and it costs more than
                    // plane fitting does; that trade is one to make against
                    // measured frame times, not in advance.
                    planeFindingMode = if (MEASURE_FLOOR) {
                        Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                    } else {
                        Config.PlaneFindingMode.DISABLED
                    }
                    updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    focusMode = Config.FocusMode.AUTO
                }
            )
            session = newSession
            sensorOrientation = readSensorOrientation(newSession)
            // Which build this capture came from. Both switches are compile
            // time, so without this line a log from a walk cannot be read back
            // against the code that produced it.
            Log.i(
                TAG,
                "AR guidance session: " +
                    "floor=${if (MEASURE_FLOOR) "measured" else "assumed"} " +
                    "anchors=${if (FOLLOW_ANCHORS) "following" else "raw"}",
            )

            val textureId = gl.createProducer(viewWidth, viewHeight)
            startedTextureId = textureId
            gl.onSurfaceRebound = { renderer.invalidateGeometry() }

            val thread = HandlerThread("arcore-guidance").also { it.start() }
            renderThread = thread
            renderHandler = Handler(thread.looper)
            running = true
            resetTrail()
            legAnchor = null
            pendingLeg = null
            activeLeg = null
            route = null
            pendingRoute = null
            wasTracking = false
            analysisInFlight = false
            measuredFloorY = null
            wallGridRad = null
            searchingForFloor = MEASURE_FLOOR
            floorSearchStartedAt = System.currentTimeMillis()

            renderHandler?.post {
                try {
                    gl.createContext()
                    if (!renderer.prepare()) Log.e(TAG, "Camera renderer unavailable")
                    if (!arrows.prepare()) Log.e(TAG, "Arrow renderer unavailable")
                    newSession.setCameraTextureName(gl.cameraTextureId)
                    resumeWithRetry(newSession)
                    newSession.setDisplayGeometry(displayRotation, viewWidth, viewHeight)
                    mainHandler.post { result.success(mapOf("textureId" to textureId)) }
                    pumpFrames()
                } catch (e: CameraNotAvailableException) {
                    abandonStart()
                    mainHandler.post {
                        gl.releaseProducer()
                        result.error("camera", "Camera not available: ${e.message}", null)
                    }
                } catch (e: Exception) {
                    abandonStart()
                    mainHandler.post {
                        gl.releaseProducer()
                        result.error("start", "ARCore start failed: ${e.message}", null)
                    }
                }
            }
        } catch (e: UnavailableException) {
            ArCoreSessionOwner.releaseIfHeld(releaseSelf)
            result.error("unavailable", "ARCore unavailable: ${e.message}", null)
        } catch (e: Exception) {
            ArCoreSessionOwner.releaseIfHeld(releaseSelf)
            result.error("start", "ARCore session creation failed: ${e.message}", null)
        }
    }

    /**
     * Resumes, allowing for the camera still being let go of somewhere else.
     *
     * Arriving from the capture screen closes one ARCore session and opens
     * another, and the close is asynchronous: the first attempt can find the
     * camera still held by a session that is halfway through releasing it.
     * Failing the whole screen over a race that resolves in a fifth of a second
     * would put the walker on the plain view for the rest of the route.
     */
    private fun resumeWithRetry(session: Session) {
        var attempt = 1
        while (true) {
            try {
                session.resume()
                return
            } catch (e: CameraNotAvailableException) {
                if (attempt >= CAMERA_ATTEMPTS) throw e
                Log.w(TAG, "Camera busy, retrying ($attempt/$CAMERA_ATTEMPTS)")
                try {
                    Thread.sleep(CAMERA_RETRY_MS)
                } catch (interrupted: InterruptedException) {
                    Thread.currentThread().interrupt()
                    throw e
                }
                attempt++
            }
        }
    }

    /**
     * Unwinds a start that got as far as the render thread and then failed.
     *
     * The camera claim in particular has to go back: leaving this handler
     * recorded as the owner means the *next* screen to want ARCore releases a
     * session that never opened and then believes it has the camera.
     */
    private fun abandonStart() {
        running = false
        startedTextureId = -1L
        ArCoreSessionOwner.releaseIfHeld(releaseSelf)
        try {
            session?.close()
        } catch (e: Exception) {
            Log.w(TAG, "Failed session close after a failed start: $e")
        }
        session = null
        renderer.release()
        arrows.release()
        gl.destroy()
        val thread = renderThread
        renderHandler = null
        renderThread = null
        thread?.quitSafely()
    }

    /**
     * Picks the smallest CPU image ARCore will give us.
     *
     * The CPU image is copied and marshalled to Dart several times a second for
     * ML Kit, so its size is a direct per-frame cost — and OCR on a door plate
     * and coarse obstacle boxes do not need megapixels. The GPU texture size is
     * a separate field on the same config and is used as the tie-break, since
     * that one *is* what the user looks at.
     */
    private fun chooseCameraConfig(session: Session) {
        try {
            val filter = CameraConfigFilter(session)
            val configs: List<CameraConfig> = session.getSupportedCameraConfigs(filter)
            if (configs.isEmpty()) return
            // The CPU image is the only thing ML Kit ever sees, and sign
            // reading is what this app navigates by — so it gets the largest
            // one the frame loop can afford rather than the smallest on offer.
            // See [AnalysisFraming].
            val byOption = LinkedHashMap<CameraOption, CameraConfig>()
            for (config in configs) {
                byOption.putIfAbsent(
                    CameraOption(
                        cpuWidth = config.imageSize.width,
                        cpuHeight = config.imageSize.height,
                        gpuWidth = config.textureSize.width,
                        gpuHeight = config.textureSize.height,
                    ),
                    config,
                )
            }
            val pick = AnalysisFraming.pickCamera(byOption.keys.toList()) ?: return
            val chosen = byOption[pick] ?: return
            session.cameraConfig = chosen
            Log.i(
                TAG,
                "camera config cpu=${chosen.imageSize.width}x${chosen.imageSize.height} " +
                    "gpu=${chosen.textureSize.width}x${chosen.textureSize.height}",
            )
        } catch (e: Exception) {
            // A device that will not enumerate configs keeps the default one,
            // which works — it is only larger than it needs to be.
            Log.w(TAG, "Camera config selection failed: $e")
        }
    }

    private fun readSensorOrientation(session: Session): Int = try {
        val manager = activity.getSystemService(Context.CAMERA_SERVICE) as CameraManager
        manager.getCameraCharacteristics(session.cameraConfig.cameraId)
            .get(CameraCharacteristics.SENSOR_ORIENTATION) ?: 90
    } catch (e: Exception) {
        Log.w(TAG, "Sensor orientation unavailable, assuming 90: $e")
        90
    }

    /**
     * Tears the session down.
     *
     * [notify] tells Dart the session has ended — see the event posted below.
     * Pass false when Dart is going to find out anyway, which means the
     * lifecycle: `onPause` runs *before* Flutter is told the app is inactive,
     * so a notification from here would arrive while the framework still
     * believes it is in the foreground, and be acted on as though the camera
     * had been snatched away mid-walk.
     */
    fun stop(notify: Boolean = true) {
        if (!running) return
        running = false
        startedTextureId = -1L
        legAnchor = null
        pendingLeg = null
        activeLeg = null
        route = null
        pendingRoute = null
        // Before the session goes: an anchor outlives the object holding it,
        // and a session closed with anchors still attached leaks them.
        releaseRouteAnchor()
        releaseLegAnchorPin()
        searchingForFloor = false
        measuredFloorY = null
        analysisEnabled = false
        analysisInFlight = false
        ArCoreSessionOwner.releaseIfHeld(releaseSelf)

        // Said before the stream goes quiet, because this handler can stop on
        // its own initiative — the camera taken by another app, a call coming
        // in — and Dart has no other way to find out. Without it the screen
        // keeps a `Texture` over a session that has gone: a frozen camera
        // image, no arrows, and no reason on screen for either.
        //
        // When Dart asked for the stop it has already cancelled its listener,
        // so this reaches nobody, which is the intent.
        if (notify) {
            eventSink?.let { sink ->
                mainHandler.post {
                    sink.success(mapOf("trackingState" to "STOPPED", "ended" to true))
                }
            }
        }

        val handler = renderHandler
        val thread = renderThread
        renderHandler = null
        renderThread = null
        lastEmitted = null

        handler?.post {
            try {
                session?.pause()
                session?.close()
            } catch (e: Exception) {
                Log.w(TAG, "Session teardown failed: $e")
            }
            session = null
            renderer.release()
            arrows.release()
            gl.destroy()
            thread?.quitSafely()
            mainHandler.post { gl.releaseProducer() }
        } ?: run {
            session = null
            thread?.quitSafely()
            gl.releaseProducer()
        }
    }

    // --- Frame loop ---------------------------------------------------------

    private fun pumpFrames() {
        val current = session ?: return
        if (!running) return

        try {
            val frame = current.update()
            noteTracking(frame)
            trackTrajectory(frame)
            logPose(frame)
            servicePlaneSearch(current, frame)
            servicePendingRoute(frame)
            servicePendingLeg(frame)
            refineCameraAnchor(frame)
            // After everything that can create an anchor and before anything
            // that reads the geometry: this is where ARCore's corrections are
            // carried into the arrows.
            followAnchors()
            drawFrame(frame)
            emitState(frame)
            analyse(frame)
        } catch (e: Exception) {
            if (e is CameraNotAvailableException) {
                Log.w(TAG, "Camera lost, stopping: $e")
                mainHandler.post { stop() }
                return
            }
            // Everything else — a superseded frame, an image not yet available
            // — is expected during normal operation.
        }

        // Normally the loop paces itself: `eglSwapBuffers` blocks once the
        // compositor is a buffer or two behind, which is what holds this at the
        // display's rate. With no surface to swap into — between a resize and
        // its rebind, or after a swap failed — nothing blocks, and reposting
        // immediately spins a core flat while drawing nothing at all.
        if (gl.canDraw) {
            renderHandler?.post { pumpFrames() }
        } else {
            renderHandler?.postDelayed({ pumpFrames() }, IDLE_FRAME_MS)
        }
    }

    private var lastPoseLogAt = 0L

    /**
     * One line a second saying where ARCore believes the phone is.
     *
     * ## What this is for, given that everything else already logs
     *
     * Every other log line in this file reports the app's *conclusions* — how
     * far along the route it thinks the walker has come, where it is pointing
     * them. None of them can be checked against a tape measure, because they
     * are all measured in the same frame that might be wrong.
     *
     * This one is the raw input. Two field tests fall out of it and nothing
     * else in the app can run them:
     *
     *   * **Odometry scale.** Walk a tape-measured straight line. The net
     *     displacement between the first and last of these lines against the
     *     true distance is ARCore's scale error, which is the floor under every
     *     distance the app quotes.
     *   * **Yaw drift.** Walk a closed square back to the start. The gap
     *     between the first and last position is the loop misclosure — the same
     *     measure `FloorGraph` reports for a recorded walk, for the same
     *     reason.
     *
     * `tool/walk_capture.sh report` reads both off a capture.
     */
    private fun logPose(frame: Frame) {
        val now = System.currentTimeMillis()
        if (now - lastPoseLogAt < WALK_LOG_MS) return
        val camera = frame.camera
        if (camera.trackingState != TrackingState.TRACKING) return
        lastPoseLogAt = now

        val t = camera.pose.translation
        val travel = travelHeading
        Log.i(
            TAG,
            "Pose x=${"%.2f".format(t[0])} z=${"%.2f".format(t[2])} " +
                "y=${"%.2f".format(t[1])} " +
                "facing=${"%.0f".format(cameraYaw(frame) * 180f / Math.PI.toFloat())}deg " +
                "travel=" +
                (travel?.let { "${"%.0f".format(it * 180f / Math.PI.toFloat())}deg" } ?: "-") +
                " floor=" + (measuredFloorY?.let { "%.2f".format(it) } ?: "assumed"),
        )
    }

    /**
     * Measures the floor once, then stops paying for the measurement.
     *
     * ## Why this is worth doing at all
     *
     * Everything the walker sees on the floor — the ring on the next
     * checkpoint, the arrow lying flat ahead of it — is drawn at a single y.
     * That y used to be the camera's height less [EYE_HEIGHT_M], one number for
     * every user and every way of holding a phone. A tall walker got a ring
     * sunk into the floor and somebody carrying the phone low got one hovering
     * at their knees, and neither reads as "the arrow is a few centimetres
     * off" — it reads as the arrow being wrong about everything.
     *
     * ## Why it is switched off again
     *
     * Plane fitting competes for exactly the CPU that ML Kit needs to read a
     * door plate, which is the app's actual positioning system. The floor does
     * not move, so the fitting is worth its cost once and never again: the
     * first plane that qualifies ends the search, and so does
     * [FLOOR_SEARCH_MS] passing without one.
     *
     * ## What qualifies
     *
     * The **lowest** upward-facing horizontal plane in the right window below
     * the phone, with enough area fitted to be a floor rather than furniture.
     * Lowest rather than largest, because in a room with a big table the table
     * is the larger plane and the walker is not standing on it.
     */
    private fun servicePlaneSearch(session: Session, frame: Frame) {
        if (!searchingForFloor) return
        val camera = frame.camera
        if (camera.trackingState != TrackingState.TRACKING) {
            // A session that cannot see the room cannot see its floor either,
            // and the clock should not run while it is not looking.
            floorSearchStartedAt = System.currentTimeMillis()
            return
        }

        val cameraY = camera.pose.translation[1]
        var lowest: Float? = null
        // Wall bearings folded onto the 90-degree grid, as unit vectors at
        // *double* the folded angle — see [meanGrid] for why the averaging has
        // to happen there rather than on the angles themselves.
        var gridSin = 0f
        var gridCos = 0f
        var walls = 0

        for (plane in session.getAllTrackables(Plane::class.java)) {
            if (plane.trackingState != TrackingState.TRACKING) continue
            // A plane ARCore has merged into a larger one. Its pose is stale.
            if (plane.subsumedBy != null) continue

            when (plane.type) {
                Plane.Type.HORIZONTAL_UPWARD_FACING -> {
                    if (plane.extentX * plane.extentZ < FLOOR_MIN_AREA_M2) continue
                    val y = plane.centerPose.ty()
                    val drop = cameraY - y
                    if (drop < FLOOR_MIN_DROP_M || drop > FLOOR_MAX_DROP_M) continue
                    if (lowest == null || y < lowest) lowest = y
                }

                Plane.Type.VERTICAL -> {
                    if (plane.extentX * plane.extentZ < WALL_MIN_AREA_M2) continue

                    // A plane's normal is its pose's y axis, whatever the
                    // plane's orientation: ARCore builds the pose so that the
                    // surface lies in x–z and y points out of it.
                    val normal = plane.centerPose.yAxis
                    val nx = normal[0]
                    val ny = normal[1]
                    val nz = normal[2]

                    // A true wall's normal is horizontal, so its y component is
                    // zero. Anything leaning is a bad fit, and its flattened
                    // normal is rotated away from the wall it came from.
                    val tilt = abs(asin(ny.coerceIn(-1f, 1f))) * 180f / Math.PI.toFloat()
                    if (tilt > WALL_MAX_TILT_DEG) continue

                    val flat = kotlin.math.sqrt(nx * nx + nz * nz)
                    if (flat < 1e-3f) continue

                    // The wall's own direction is perpendicular to its normal,
                    // but folding by 90 degrees makes the two the same angle —
                    // so the normal's bearing is taken directly and the fold
                    // does the rest.
                    val bearing = atan2(nx, -nz)
                    // Doubled before averaging: two bearings 90 degrees apart
                    // are the same grid, and doubling maps them onto the same
                    // direction where a vector mean is meaningful.
                    val doubled = 4f * bearing
                    gridSin += sin(doubled)
                    gridCos += cos(doubled)
                    walls++
                }

                else -> continue
            }
        }

        if (walls >= WALL_GRID_MIN_PLANES) {
            // Resultant length says how tightly they agreed. A perfect
            // rectilinear set gives 1; walls pointing every way cancel to 0.
            val resultant = kotlin.math.sqrt(gridSin * gridSin + gridCos * gridCos) / walls
            val spreadDeg = spreadFromResultant(resultant)
            if (walls == 1 || spreadDeg <= WALL_GRID_MAX_SPREAD_DEG) {
                val grid = normaliseGrid(atan2(gridSin, gridCos) / 4f)
                wallGridRad = grid
                Log.i(
                    TAG,
                    "Wall grid measured at " +
                        "${"%.1f".format(grid * 180f / Math.PI.toFloat())}deg " +
                        "from $walls walls, spread " +
                        "${"%.1f".format(spreadDeg)}deg",
                )
            } else {
                Log.i(
                    TAG,
                    "Wall grid rejected: $walls walls disagree by " +
                        "${"%.1f".format(spreadDeg)}deg",
                )
            }
        }

        if (lowest != null && measuredFloorY == null) {
            measuredFloorY = lowest
            Log.i(
                TAG,
                "Floor measured at y=${"%.2f".format(lowest)}, " +
                    "${"%.2f".format(cameraY - lowest)}m below the phone " +
                    "(assumed ${EYE_HEIGHT_M}m)",
            )
            adoptMeasuredFloor(lowest)
        }
    }

    /**
     * Circular spread of the folded wall bearings, in degrees.
     *
     * [resultant] is the mean vector's length on the quadrupled angle, so it
     * runs 1 for perfect agreement down to 0 for none. The inverse of the
     * standard circular-variance relation turns it back into an angle, and the
     * quarter undoes the quadrupling so the number is in the same degrees the
     * threshold is written in.
     */
    private fun spreadFromResultant(resultant: Float): Float {
        val clamped = resultant.coerceIn(1e-6f, 1f)
        val spread = kotlin.math.sqrt(-2f * kotlin.math.ln(clamped))
        return spread * 180f / Math.PI.toFloat() / 4f
    }

    /**
     * Folds an angle onto [0, pi/2), the range a rectilinear grid lives in.
     *
     * The epsilon matches `Registration.foldToQuarter` on the Dart side, and
     * for the same reason: walls square to ARCore's own axes average out a hair
     * either side of zero, and the negative side folds to a hair *under* a
     * quarter turn. Both name the same grid, but a log line reading 89.9deg for
     * a square corridor is one nobody can act on.
     */
    private fun normaliseGrid(angle: Float): Float {
        val quarter = (Math.PI / 2).toFloat()
        var a = angle % quarter
        if (a < 0f) a += quarter
        return if (quarter - a < 1e-5f) 0f else a
    }

    /** Gives the CPU back to ML Kit. */
    private fun stopSearchingForFloor(session: Session) {
        searchingForFloor = false
        try {
            session.configure(
                session.config.apply {
                    planeFindingMode = Config.PlaneFindingMode.DISABLED
                }
            )
        } catch (e: Exception) {
            // Reconfiguring failed, so plane finding stays on. That costs
            // frames and nothing else — the measurement is already taken.
            Log.w(TAG, "Could not switch plane finding off: $e")
        }
    }

    /**
     * Drops whatever is already drawn onto the floor that was just measured.
     *
     * A route registered in the first second of a session was built against the
     * assumed height. Leaving it there would mean the arrows on this walk sit
     * at one height and the ones on the next walk sit at another, for no reason
     * the walker could ever see.
     */
    private fun adoptMeasuredFloor(y: Float) {
        route?.setFloor(y)
        legAnchor?.floorY = y
    }

    /** The floor, measured where it could be and assumed where it could not. */
    private fun floorYFor(cameraY: Float): Float =
        measuredFloorY ?: (cameraY - EYE_HEIGHT_M)

    // --- Anchoring ----------------------------------------------------------

    /**
     * Carries ARCore's own corrections into the route and the leg.
     *
     * ## The problem this exists for
     *
     * A world coordinate in ARCore is not a place in the building. It is a
     * place in ARCore's *current opinion* of the building, and that opinion is
     * revised: when the session recognises somewhere it has been before it
     * closes the loop and moves everything to fit — by a few centimetres
     * usually, by a metre and several degrees after a bad stretch. Raw
     * coordinates do not move with it. The route stays where it was put, the
     * building moves out from under it, and nothing in the app can tell.
     *
     * An [Anchor] is ARCore's answer: a point it undertakes to keep pinned to
     * the same physical place across those revisions. So the route is stored
     * once as offsets from an anchor and rebuilt from the anchor's current pose
     * every frame. When ARCore corrects itself the whole line follows, which is
     * the difference between odometry error that accumulates and odometry error
     * that gets fixed.
     *
     * ## Yaw only
     *
     * A correction is a full six-degree-of-freedom adjustment, and this applies
     * its translation and its rotation about the vertical, discarding pitch and
     * roll. Those two describe the floor tilting, which it does not; carrying
     * them would let a noisy anchor rock the arrows in place.
     */
    private fun followAnchors() {
        if (!FOLLOW_ANCHORS) return
        followRouteAnchor()
        followLegAnchor()
    }

    private fun followRouteAnchor() {
        val anchor = routeAnchor ?: return
        val current = route ?: return
        if (anchor.trackingState != TrackingState.TRACKING) return

        val pose = anchor.pose
        val turned = yawOf(pose) - routeAnchorYaw
        val cos = cos(turned)
        val sin = sin(turned)
        val originX = pose.tx()
        val originZ = pose.tz()

        for (i in routeLocalX.indices) {
            val lx = routeLocalX[i]
            val lz = routeLocalZ[i]
            // Rotation about +y: x' = x cos + z sin, z' = -x sin + z cos.
            routeWorldX[i] = originX + lx * cos + lz * sin
            routeWorldZ[i] = originZ - lx * sin + lz * cos
        }
        current.rebase(routeWorldX, routeWorldZ, pose.ty())
    }

    /**
     * The same for a dead-reckoned leg, which is a line rather than a path.
     *
     * The pin was made at the leg's origin, so the origin is wherever the pin
     * is now, and the direction turns by however much the pin has turned. The
     * walker's progress along the leg is measured by projection onto that line
     * each frame, so it needs nothing carried across.
     *
     * This overlaps with [noteTracking], which throws a leg away entirely after
     * a long enough loss of tracking. Both are wanted. An anchor absorbs the
     * *correction* — the world moving under a leg that is still the right leg —
     * and the re-anchor there handles the other thing that happens across a
     * blind stretch, which is the walker having walked on and possibly turned
     * while the phone could not see.
     */
    private fun followLegAnchor() {
        val pin = legAnchorPin ?: return
        val leg = legAnchor ?: return
        if (pin.trackingState != TrackingState.TRACKING) return

        val pose = pin.pose
        val turned = yawOf(pose) - legAnchorYaw
        val cos = cos(turned)
        val sin = sin(turned)

        leg.startX = pose.tx()
        leg.startZ = pose.tz()
        leg.dirX = legLocalDirX * cos + legLocalDirZ * sin
        leg.dirZ = -legLocalDirX * sin + legLocalDirZ * cos
        leg.floorY = pose.ty()
    }

    /**
     * Which way a pose faces about the vertical, in radians.
     *
     * The quaternion is (x, y, z, w) and this is the standard yaw extraction
     * for a y-up frame. Anything but the yaw is deliberately thrown away — see
     * [followAnchors].
     */
    private fun yawOf(pose: Pose): Float {
        val q = pose.rotationQuaternion
        return atan2(
            2f * (q[3] * q[1] + q[0] * q[2]),
            1f - 2f * (q[1] * q[1] + q[2] * q[2]),
        )
    }

    /**
     * Pins [x], [z] in the world and remembers which way the pin was facing.
     *
     * Returns null when the session will not give an anchor out, which is not
     * fatal: everything still works off the raw coordinates it was given, it
     * simply stops following ARCore's corrections.
     */
    private fun anchorAt(x: Float, y: Float, z: Float): Anchor? = try {
        session?.createAnchor(Pose.makeTranslation(x, y, z))
    } catch (e: Exception) {
        Log.w(TAG, "Could not anchor at ($x, $z): $e")
        null
    }

    /**
     * Pins the leg that was just built, at its own origin.
     *
     * Its origin is where the walker is standing, so the "anchor it where
     * tracking is best" argument in [pinRoute] is satisfied for free here.
     */
    private fun pinLeg() {
        releaseLegAnchorPin()
        if (!FOLLOW_ANCHORS) return
        val leg = legAnchor ?: return

        val pin = anchorAt(leg.startX, leg.floorY, leg.startZ) ?: return
        legAnchorPin = pin
        legAnchorYaw = yawOf(pin.pose)
        legLocalDirX = leg.dirX
        legLocalDirZ = leg.dirZ
    }

    private fun releaseRouteAnchor() {
        try {
            routeAnchor?.detach()
        } catch (e: Exception) {
            Log.w(TAG, "Route anchor would not detach: $e")
        }
        routeAnchor = null
    }

    private fun releaseLegAnchorPin() {
        try {
            legAnchorPin?.detach()
        } catch (e: Exception) {
            Log.w(TAG, "Leg anchor would not detach: $e")
        }
        legAnchorPin = null
    }

    /**
     * Watches tracking come and go, and decides what survives the gap.
     *
     * ARCore does not stop when it loses the room: it stops *reporting*, and
     * when it finds the room again it may correct the pose by a metre or a
     * heading by tens of degrees. Two things cannot survive that correction —
     * a trajectory measured across the gap, which describes a walk nobody took,
     * and a leg anchored before it, which is now nailed to a world that has
     * moved underneath it.
     *
     * A blink is different from a relocalisation, though, and re-anchoring is
     * not free: it costs whatever accuracy the current leg had. So a loss
     * shorter than [RELOCALISE_GRACE_MS] keeps the anchor and only throws away
     * the trail.
     */
    private fun noteTracking(frame: Frame) {
        val tracking = frame.camera.trackingState == TrackingState.TRACKING
        if (tracking == wasTracking) return
        wasTracking = tracking

        if (!tracking) {
            lostTrackingAt = System.currentTimeMillis()
            // Whatever comes back, it will not be continuous with this.
            resetTrail()
            return
        }

        resetTrail()
        val lostFor = System.currentTimeMillis() - lostTrackingAt
        val anchor = legAnchor
        if (anchor != null && lostFor >= RELOCALISE_GRACE_MS) {
            // Re-anchored here rather than by asking Dart for the leg again,
            // and **with no turn**, which is the part that matters: the walker
            // made this leg's turn when the leg began. Applying it a second
            // time halfway down the corridor would send the arrows round a
            // corner that is not there. What is left of the leg runs along
            // whatever direction they are walking now — which is also the
            // right answer if they rounded a corner while the phone was blind.
            val remaining = (anchor.lengthM - walkedM).coerceAtLeast(0.5f)
            Log.i(
                TAG,
                "Tracking recovered after ${lostFor}ms; re-anchoring " +
                    "${"%.1f".format(remaining)}m of leg along the way ahead",
            )
            legAnchor = null
            releaseLegAnchorPin()
            activeLeg = null
            // Carried across the re-anchor: the walker really has walked this
            // much of the leg, whatever the new anchor's origin thinks.
            legWalkedBase += walkedM
            pendingLeg = PendingLeg(turnDeg = 0, distanceM = remaining)
        }
    }

    /**
     * Keeps the recent path, and the direction it implies.
     *
     * Sampled by distance rather than by time, so standing still adds nothing
     * and the window always describes the same length of walking however slowly
     * it was walked. Standing at a sign therefore *preserves* the direction of
     * approach rather than diluting it, which is exactly the moment the next
     * leg is about to be anchored.
     */
    private fun trackTrajectory(frame: Frame) {
        val camera = frame.camera
        if (camera.trackingState != TrackingState.TRACKING) return
        val translation = camera.pose.translation
        val x = translation[0]
        val z = translation[2]

        if (trailCount == 0) {
            push(x, z)
            return
        }
        val lastIndex = (trailHead - 1 + TRAIL_SAMPLES) % TRAIL_SAMPLES
        val dx = x - trailX[lastIndex]
        val dz = z - trailZ[lastIndex]
        val moved = dx * dx + dz * dz
        if (moved < TRAIL_STEP_M * TRAIL_STEP_M) return
        if (moved > MAX_SAMPLE_JUMP_M * MAX_SAMPLE_JUMP_M) {
            // Nobody travels a metre between two frames. This is ARCore
            // correcting itself, and averaging the correction into the trail
            // would hand the next leg a direction the walker never faced.
            resetTrail()
            push(x, z)
            return
        }
        push(x, z)

        // Oldest sample still in the ring, to newest.
        val oldest = if (trailCount < TRAIL_SAMPLES) 0 else trailHead
        val newest = (trailHead - 1 + TRAIL_SAMPLES) % TRAIL_SAMPLES
        val netX = trailX[newest] - trailX[oldest]
        val netZ = trailZ[newest] - trailZ[oldest]
        val netSq = netX * netX + netZ * netZ
        // Yaw measured from -z (ARCore's forward) toward +x, so a positive
        // turn is a turn to the right — the same convention as
        // `PlannedLeg.turnDeg` and `route_layout`'s heading.
        val bearing = atan2(netX, -netZ)

        travelHeading = if (netSq >=
            MIN_TRAVEL_FOR_HEADING_M * MIN_TRAVEL_FOR_HEADING_M
        ) {
            val prev = travelHeading
            if (prev == null) {
                bearing
            } else {
                // Smooth gait sway (EMA filter) so hallway heading is steady
                val sinAvg = 0.7f * sin(prev) + 0.3f * sin(bearing)
                val cosAvg = 0.7f * cos(prev) + 0.3f * cos(bearing)
                atan2(sinAvg, cosAvg)
            }
        } else {
            null
        }

        // The same bearing, released only once it has been earned over a much
        // longer baseline. Separate from [travelHeading] rather than replacing
        // it because the two are asked for different things: a leg wants a
        // direction soon and can be corrected later, a registration wants one
        // right and never gets a second chance. See the note on
        // [MIN_TRAVEL_FOR_REGISTRATION_M].
        registrationHeading = if (netSq >=
            MIN_TRAVEL_FOR_REGISTRATION_M * MIN_TRAVEL_FOR_REGISTRATION_M
        ) {
            bearing
        } else {
            null
        }
    }

    private fun push(x: Float, z: Float) {
        trailX[trailHead] = x
        trailZ[trailHead] = z
        trailHead = (trailHead + 1) % TRAIL_SAMPLES
        if (trailCount < TRAIL_SAMPLES) trailCount++
    }

    private fun resetTrail() {
        trailCount = 0
        trailHead = 0
        travelHeading = null
        registrationHeading = null
    }

    /**
     * Freezes a leg into the world, once, from the pose it is asked at.
     *
     * The turn is applied to the direction the walker was **moving**; when
     * there is none — the first leg of a route, standing still — it falls back
     * to where the phone is pointing and says so, because that assumption is
     * wrong often enough that the screen has to be able to ask for a few steps.
     */
    private fun servicePendingLeg(frame: Frame) {
        val pending = pendingLeg ?: return
        val camera = frame.camera
        if (camera.trackingState != TrackingState.TRACKING) return
        pendingLeg = null

        val pose = camera.pose
        val translation = pose.translation
        val fromMotion = travelHeading
        anchoredFromCamera = fromMotion == null
        val base = fromMotion ?: cameraYaw(frame)
        val heading = base + pending.turnDeg * Math.PI.toFloat() / 180f

        activeLeg = pending
        legAnchor = LegAnchor(
            startX = translation[0],
            startZ = translation[2],
            dirX = sin(heading),
            dirZ = -cos(heading),
            lengthM = pending.distanceM.coerceAtLeast(0.5f),
            floorY = floorYFor(translation[1]),
            cameraX = translation[0],
            cameraZ = translation[2],
        )
        pinLeg()
        walkedM = 0f
        // The one moment worth a log line on a walk: everything the arrow does
        // for the next corridor follows from these four numbers, and none of
        // them is visible on screen. A leg that comes out along the wrong wall
        // is diagnosed here or not at all.
        Log.i(
            TAG,
            "Leg anchored: turn ${pending.turnDeg}deg, ${"%.1f".format(pending.distanceM)}m, " +
                "base ${"%.0f".format(base * 180f / Math.PI.toFloat())}deg " +
                (if (fromMotion == null) "from camera (standing still)" else "from motion") +
                ", heading ${"%.0f".format(heading * 180f / Math.PI.toFloat())}deg",
        )
    }

    /**
     * Replaces a guessed anchor with a measured one, once there is motion.
     *
     * A leg anchored while the walker stood still was anchored off where the
     * phone happened to point, and the screen says as much. The moment they
     * have walked far enough for a direction to exist, that guess can be
     * replaced by the real thing — which is the answer to the hint the screen
     * has been showing, rather than something the walker has to act on twice.
     *
     * Two guards keep this from making things worse. It only applies to legs
     * that run straight ahead, because on a turning leg the walker's first
     * steps are already round the turn (see [STRAIGHT_ENOUGH_DEG]); and it only
     * applies within the first [REFINE_WINDOW_M], because after that they are
     * committed to a corridor and moving the arrows under them is worse than a
     * few degrees of error.
     */
    private fun refineCameraAnchor(frame: Frame) {
        if (!anchoredFromCamera) return
        val anchor = legAnchor ?: return
        val leg = activeLeg ?: return
        if (frame.camera.trackingState != TrackingState.TRACKING) return
        val heading = travelHeading ?: return

        val translation = frame.camera.pose.translation
        val dx = translation[0] - anchor.startX
        val dz = translation[2] - anchor.startZ
        val travelled = kotlin.math.sqrt(dx * dx + dz * dz)
        if (travelled > REFINE_WINDOW_M) return

        // When the walker takes their first steps, their physical travel heading
        // aligns with the physical hallway.
        val corrected = heading
        anchoredFromCamera = false
        legAnchor = LegAnchor(
            startX = translation[0],
            startZ = translation[2],
            dirX = sin(corrected),
            dirZ = -cos(corrected),
            // What is left of the leg from here, not the whole of it again.
            lengthM = (leg.distanceM - travelled).coerceAtLeast(0.5f),
            floorY = floorYFor(translation[1]),
            cameraX = translation[0],
            cameraZ = translation[2],
        )
        pinLeg()
        // Those first steps still happened, so they stay on the leg's clock
        // even though the anchor they were measured against has been replaced.
        // Measured as `travelled` rather than as [walkedM] to match the length
        // the new anchor was given: the two have to add back up to the leg, and
        // the projection onto a direction now known to be a guess does not.
        legWalkedBase += travelled
        walkedM = 0f
        Log.i(TAG, "Guessed anchor corrected after ${"%.1f".format(travelled)}m of walking")
    }

    /** Where the phone is pointing, as a yaw in the same frame as the trail. */
    private fun cameraYaw(frame: Frame): Float {
        // The camera looks down its own -z, so forward in world space is the
        // negated z axis of its pose.
        val zAxis = frame.camera.pose.zAxis
        return atan2(-zAxis[0], zAxis[2])
    }

    private fun drawFrame(frame: Frame) {
        if (!gl.canDraw || !renderer.isReady) return
        renderer.draw(frame, gl.cameraTextureId, viewWidth, viewHeight)

        val camera = frame.camera
        val tracking = camera.trackingState == TrackingState.TRACKING

        val registered = route
        if (registered != null && arrows.isReady && tracking) {
            drawRoute(frame, registered)
            gl.swapBuffers()
            return
        }

        val leg = legAnchor
        if (leg != null && arrows.isReady && tracking) {
            val translation = camera.pose.translation
            leg.cameraX = translation[0]
            leg.cameraZ = translation[2]
            walkedM = walkedAlong(leg, translation[0], translation[2])
            val checkpoint = checkpointAlong(leg)
            val bearing = needleBearing(frame, leg, checkpoint)
            val destX = leg.startX + leg.dirX * leg.lengthM
            val destZ = leg.startZ + leg.dirZ * leg.lengthM
            arrows.drawAt(
                camera = camera,
                ringX = leg.startX + leg.dirX * checkpoint,
                ringY = leg.floorY,
                ringZ = leg.startZ + leg.dirZ * checkpoint,
                ringDirX = leg.dirX,
                ringDirZ = leg.dirZ,
                bearingDeg = bearing,
                destX = destX,
                destY = leg.floorY,
                destZ = destZ,
            )
            logWalk(bearing, checkpoint, leg)
        }

        gl.swapBuffers()
    }

    /**
     * Draws a registered route: the ring on the next place, the arrow at it.
     *
     * The arrow aims a little past the ring so it has something far enough
     * away to be steady — the same reasoning as [needleBearing] — except where
     * the route turns at that point, because aiming past a corner points
     * through the wall on the outside of it. There the arrow aims at the
     * corner itself and turns with the walker as they round it, which is what
     * a person following an arrow round a corner expects it to do.
     */
    private fun drawRoute(frame: Frame, registered: RegisteredRoute) {
        val camera = frame.camera
        val translation = camera.pose.translation
        registered.update(translation[0], translation[2])

        val mark = registered.nextMarkM(CHECKPOINT_M, TURN_IS_A_CORNER_DEG)
        registered.pointAt(mark, markPoint)

        // Where to aim. Past the mark on a straight run; at the mark itself
        // where the route turns there, because aiming past a corner points the
        // walker through the wall on the outside of it. Never past a corner
        // that lies between the two, for the same reason.
        val corner = registered.nextCornerM(TURN_IS_A_CORNER_DEG)
        val aimAt = if (mark >= corner - 0.01f) {
            mark
        } else {
            min(min(mark + CHECKPOINT_M, corner), registered.totalM)
        }
        registered.pointAt(aimAt, aimPoint)

        val bearing = if (registered.remainingM < NEAR_TARGET_M) {
            // Standing on the destination. There is no point ahead to take a
            // bearing to, and the bearing to one you are on top of spins with
            // every footstep, so the arrow lies down the last stretch of the
            // route instead — steady, and at this range still right.
            wrapDegrees(
                (registered.bearingAt(registered.totalM) - cameraYaw(frame)) *
                    180f / Math.PI.toFloat(),
            )
        } else {
            bearingToPoint(frame, aimPoint[0], aimPoint[1])
        }

        val destPoint = FloatArray(2)
        registered.destination(destPoint)

        lastRouteBearingDeg = bearing
        arrows.drawAt(
            camera = camera,
            ringX = markPoint[0],
            ringY = registered.floorY,
            ringZ = markPoint[1],
            ringDirX = sin(registered.bearingAt(mark)),
            ringDirZ = -cos(registered.bearingAt(mark)),
            bearingDeg = bearing,
            destX = destPoint[0],
            destY = registered.floorY,
            destZ = destPoint[1],
            pathXs = registered.xs,
            pathZs = registered.zs,
        )

        logRoute(registered, mark, bearing)
    }

    /**
     * A line a second while a route is being walked.
     *
     * [RegisteredRoute.offsetM] is the number to read this back for. Everything
     * else says what the app believes; that one says whether the belief
     * matches the building. A walk whose offset climbs steadily is a
     * registration that came out rotated, and it is the only symptom that
     * distinguishes it from a walker who simply wandered.
     */
    private fun logRoute(registered: RegisteredRoute, mark: Float, bearingDeg: Float) {
        val now = System.currentTimeMillis()
        if (now - lastRouteLogAt < WALK_LOG_MS) return
        lastRouteLogAt = now
        val corner = registered.nextCornerM(TURN_IS_A_CORNER_DEG)
        Log.i(
            TAG,
            "Route ${"%.1f".format(registered.alongM)}/" +
                "${"%.1f".format(registered.totalM)}m " +
                // Where the ring is and *why* it is there. A mark that is
                // always a fraction of a metre ahead is the ring following
                // arbitrary vertices rather than the plan, which is the one
                // failure that looks identical to no registration at all.
                "mark ${"%.1f".format(mark)}m (+${"%.1f".format(mark - registered.alongM)}) " +
                (if (mark >= corner - 0.01f) "CORNER " else "grid ") +
                "seg ${registered.segment} " +
                "off ${"%.1f".format(registered.offsetM)}m " +
                "bearing ${"%.0f".format(bearingDeg)}deg",
        )
    }

    /**
     * Turns a list of world coordinates into a route, on the render thread.
     *
     * The floor height is the reason this waits for a frame rather than being
     * built where the call arrives: it is the camera's height less an assumed
     * eye height, and there is no camera to ask on the platform thread.
     */
    private fun servicePendingRoute(frame: Frame) {
        val flat = pendingRoute ?: return
        val camera = frame.camera
        if (camera.trackingState != TrackingState.TRACKING) return
        pendingRoute = null

        val count = flat.size / 2
        val xs = FloatArray(count)
        val zs = FloatArray(count)
        for (i in 0 until count) {
            xs[i] = flat[i * 2].toFloat()
            zs[i] = flat[i * 2 + 1].toFloat()
        }

        val floorY = floorYFor(camera.pose.translation[1])
        val previous = route
        val built = try {
            RegisteredRoute(xs, zs, floorY)
        } catch (e: IllegalArgumentException) {
            Log.w(TAG, "Refused a degenerate route: $e")
            return
        }
        // A re-registration of the same walk must not send the walker back to
        // the beginning of it. Dart re-registers on tracking recovery and at
        // confirmed landmarks, and both happen mid-corridor.
        if (previous != null && kotlin.math.abs(previous.totalM - built.totalM) < 0.5f) {
            built.resumeFrom(previous)
        }
        route = built
        pinRoute(xs, zs, floorY, camera.pose)
        // The leg is redundant the moment a route exists, and leaving it
        // behind would leave `emitState` reporting a dead-reckoned distance
        // next to a measured one.
        legAnchor = null
        releaseLegAnchorPin()
        pendingLeg = null
        activeLeg = null

        Log.i(
            TAG,
            "Route registered: $count points, ${"%.1f".format(built.totalM)}m, " +
                "resuming at ${"%.1f".format(built.alongM)}m, " +
                "floor y=${"%.2f".format(floorY)}" +
                (if (measuredFloorY == null) " (assumed)" else " (measured)"),
        )
    }

    /**
     * Hangs the route off a fresh anchor under the walker's feet.
     *
     * ## Where the anchor goes, and why not on the route
     *
     * Under the camera, on the floor — not at the route's first point, which
     * would be the obvious place. An anchor is only as good as ARCore's
     * knowledge of the space around it, and the space ARCore knows best is the
     * one the phone is standing in and looking at. The start of a route is
     * frequently behind the walker by the time the registration solves, and on
     * a re-registration it can be a corridor away.
     *
     * The offsets are taken from the anchor in the world frame as it stands
     * right now, and its yaw is recorded alongside them. From here on the two
     * together *are* the route: [followAnchors] rebuilds the world coordinates
     * from the anchor's current pose every frame, so a relocalisation that
     * moves the world moves the route with it.
     */
    private fun pinRoute(xs: FloatArray, zs: FloatArray, floorY: Float, camera: Pose) {
        releaseRouteAnchor()
        // Not merely unused when the switch is off — an anchor ARCore is
        // maintaining for nobody still costs it work every frame.
        if (!FOLLOW_ANCHORS) return

        val originX = camera.tx()
        val originZ = camera.tz()
        val anchor = anchorAt(originX, floorY, originZ)
        if (anchor == null) {
            // No anchor, so no corrections — the route stays exactly where it
            // was laid, which is what it did before any of this existed.
            routeLocalX = FloatArray(0)
            routeLocalZ = FloatArray(0)
            return
        }

        routeAnchor = anchor
        routeAnchorYaw = yawOf(anchor.pose)
        routeLocalX = FloatArray(xs.size) { xs[it] - originX }
        routeLocalZ = FloatArray(zs.size) { zs[it] - originZ }
        routeWorldX = FloatArray(xs.size)
        routeWorldZ = FloatArray(zs.size)
    }

    /**
     * A line a second while a leg is being walked.
     *
     * Everything the arrow is doing is geometry nobody can check by looking at
     * it — an arrow pointing thirty degrees off looks exactly like an arrow
     * pointing at a door thirty degrees away. This is what a walk gets read
     * back from afterwards, against `SAY` and `ADVANCE` from the Dart side, so
     * the three together say where the walker was, where they were being sent
     * and what they were told.
     *
     * Once a second rather than per frame: sixty of these would push the
     * interesting lines out of the log buffer inside a corridor.
     */
    private fun logWalk(bearingDeg: Float, checkpoint: Float, leg: LegAnchor) {
        val now = System.currentTimeMillis()
        if (now - lastWalkLogAt < WALK_LOG_MS) return
        lastWalkLogAt = now
        Log.i(
            TAG,
            "Walk ${"%.1f".format(legWalkedM)}/${"%.1f".format(legWalkedBase + leg.lengthM)}m " +
                "checkpoint ${"%.1f".format(legWalkedBase + checkpoint)}m " +
                "bearing ${"%.0f".format(bearingDeg)}deg" +
                (if (anchoredFromCamera) " (anchor guessed)" else ""),
        )
    }

    /**
     * How far along the current anchor the next checkpoint is.
     *
     * The leg is walked in [CHECKPOINT_M] pieces rather than in one go: the
     * ring marks the next piece, not the landmark at the far end, so the walker
     * is sent one short hop at a time and the whole corridor is never laid out
     * in front of them at once. The last checkpoint *is* the landmark, so
     * arriving is the same event it always was.
     *
     * Measured on the leg's own clock — cumulative metres, not metres since the
     * last re-anchor — so the checkpoints stay on the same grid after ARCore
     * relocalises instead of restarting under the walker's feet.
     */
    private fun checkpointAlong(leg: LegAnchor): Float {
        val cumulative = legWalkedM
        val next = floor(cumulative / CHECKPOINT_M) * CHECKPOINT_M + CHECKPOINT_M
        val endOfLeg = legWalkedBase + leg.lengthM
        return min(next, endOfLeg) - legWalkedBase
    }

    /**
     * Which way the arrow points, in degrees, positive to the right.
     *
     * Aimed at a *point* rather than along the leg's direction, so that
     * stepping round somebody coming the other way turns the arrow to bring the
     * walker back rather than marching them into a wall parallel to the route.
     *
     * Which point takes some care. The obvious answer — the checkpoint the ring
     * is on — is wrong for the last stride or so before reaching it: the
     * bearing to a point you are nearly standing on swings through a full
     * circle with one footstep, and the arrow would spin just as the walker
     * looked at it. So the aim jumps to the checkpoint *after* the one being
     * walked to as soon as this one is closer than [NEAR_TARGET_M], and at the
     * very end of a leg, where there is no next one, it falls back to the leg's
     * frozen direction, which cannot spin.
     */
    private fun needleBearing(frame: Frame, leg: LegAnchor, checkpoint: Float): Float {
        // **Past the end of the leg, and far enough past to be sure of it.**
        // The landmark is behind them now. Everything below aims at a point
        // ahead, and with nothing left ahead to aim at they all fall through to
        // the leg's direction — which is an arrow pointing confidently down the
        // corridor, telling somebody who has walked past their door to keep
        // walking away from it. Turn the arrow round instead.
        if (walkedM - leg.lengthM > NEAR_TARGET_M) {
            return bearingToPoint(
                frame,
                leg.startX + leg.dirX * leg.lengthM,
                leg.startZ + leg.dirZ * leg.lengthM,
            )
        }

        var aim = checkpoint
        if (aim - walkedM < NEAR_TARGET_M) {
            aim = min(checkpoint + CHECKPOINT_M, leg.lengthM)
        }
        if (aim - walkedM < NEAR_TARGET_M) {
            // Standing on the last checkpoint, or within a stride of it. There
            // is no point far enough away to take a stable bearing to, and the
            // leg's own direction is both steady and, this close, right.
            val along = atan2(leg.dirX, -leg.dirZ)
            return wrapDegrees((along - cameraYaw(frame)) * 180f / Math.PI.toFloat())
        }
        return bearingToPoint(
            frame,
            leg.startX + leg.dirX * aim,
            leg.startZ + leg.dirZ * aim,
        )
    }

    /**
     * How far along the leg the walker has come.
     *
     * Projected onto the leg's own direction rather than measured as a straight
     * line from the start, so stepping round a person coming the other way does
     * not count as progress toward the landmark.
     */
    private fun walkedAlong(leg: LegAnchor, x: Float, z: Float): Float =
        ((x - leg.startX) * leg.dirX + (z - leg.startZ) * leg.dirZ).coerceAtLeast(0f)

    // --- State to Dart ------------------------------------------------------

    private var lastEmitted: Map<String, Any?>? = null
    private var lastEmittedAt = 0L
    private var lastCheckedAt = 0L

    /**
     * Pushes what the screen renders, quantised so it is not a frame stream.
     *
     * Distance to a quarter of a metre and bearing to five degrees: past that
     * resolution nothing on screen changes, and every emission is a Bloc state
     * and a widget rebuild. The heartbeat covers the case where the numbers
     * genuinely have not moved but the screen has just been rebuilt.
     */
    private fun emitState(frame: Frame) {
        val now = System.currentTimeMillis()
        // Checked before the payload is built, not after: assembling a map per
        // frame only to discover it matches the last one is sixty allocations a
        // second on the thread that has to keep the camera moving. Timed from
        // the last *look*, not the last emission, or an unchanging state would
        // go back to building one per frame between heartbeats.
        if (now - lastCheckedAt < STATE_INTERVAL_MS) return
        lastCheckedAt = now

        val camera = frame.camera
        val tracking = camera.trackingState
        val leg = legAnchor

        val registered = route

        val payload = mutableMapOf<String, Any?>(
            "trackingState" to tracking.name,
            "hasLeg" to (leg != null || registered != null),
            "headingReady" to (travelHeading != null),
            "anchoredFromCamera" to anchoredFromCamera,
            "hasRoute" to (registered != null),
        )
        if (tracking == TrackingState.PAUSED) {
            payload["failureReason"] = camera.trackingFailureReason.name
        }

        // The pose and the direction of travel, so Dart can solve the
        // registration. Sent whether or not a route exists, because the moment
        // Dart is waiting for is precisely the one before there is one — it
        // needs a position and a heading in the same breath, and asking for
        // them over the method channel would get two answers a frame apart.
        //
        // Quantised finely: this is the input to a rotation applied across a
        // whole building, where a degree is a third of a metre at twenty. The
        // heading is the expensive one and it only moves when the walker does.
        if (tracking == TrackingState.TRACKING) {
            val translation = camera.pose.translation
            payload["camX"] = quantise(translation[0], 0.05f)
            payload["camZ"] = quantise(translation[2], 0.05f)
            travelHeading?.let {
                payload["travelHeadingDeg"] = quantise(it * 180f / Math.PI.toFloat(), 1f)
            }
            // The long-baseline heading, which is the only one Dart registers
            // against. Sent alongside rather than instead of the short one:
            // the screen's "walk a few steps" hint keys off the short one, and
            // a walker who has moved at all should not be told they haven't.
            registrationHeading?.let {
                payload["registrationHeadingDeg"] =
                    quantise(it * 180f / Math.PI.toFloat(), 0.5f)
            }
            // Quantised finer than any other angle here. It is folded to a
            // quarter turn, so a degree of rounding is a degree of building
            // rotation with no averaging left to absorb it.
            wallGridRad?.let {
                payload["wallGridDeg"] = quantise(it * 180f / Math.PI.toFloat(), 0.25f)
            }
            payload["cameraYawDeg"] = quantise(cameraYaw(frame) * 180f / Math.PI.toFloat(), 0.5f)
        }

        if (registered != null && tracking == TrackingState.TRACKING) {
            // A registered route reports the same three numbers a leg does, so
            // the screen and the guidance clock do not have to know which kind
            // of thing is being walked — but here they are measured against a
            // known line rather than dead-reckoned along a guess.
            payload["walkedM"] = quantise(registered.alongM, 0.25f)
            payload["remainingM"] = quantise(registered.remainingM, 0.25f)
            payload["overshootM"] = 0.0
            payload["routeTotalM"] = quantise(registered.totalM, 0.25f)
            // The one number that says whether any of the rest is true. See
            // the note on [RegisteredRoute.offsetM].
            payload["offRouteM"] = quantise(registered.offsetM, 0.25f)
            payload["segment"] = registered.segment
            payload["arrived"] = registered.arrived
            payload["bearingDeg"] = quantise(
                lastRouteBearingDeg,
                5f,
            ).toInt()
        }
        // Only when there is no route: a registered one has already reported
        // all of this, measured rather than dead-reckoned, and letting the leg
        // overwrite it would put the guess back on the screen.
        if (registered == null && leg != null && tracking == TrackingState.TRACKING) {
            val remaining = (leg.lengthM - walkedM).coerceAtLeast(0f)
            // The leg's own clock, not the current anchor's. Dart paces the
            // spoken cues off this, and a number that restarted every time
            // ARCore relocalised would say "six metres to go" twice.
            payload["walkedM"] = quantise(legWalkedM, 0.25f)
            payload["remainingM"] = quantise(remaining, 0.25f)
            // Quantised coarsely: this only decides whether the screen says the
            // walker has gone too far, and a jittery answer to that is worse
            // than a late one.
            payload["overshootM"] = quantise((walkedM - leg.lengthM).coerceAtLeast(0f), 0.5f)
            // The same angle the arrow is drawn at, not the bearing to the far
            // landmark: the screen's words and the arrow have to agree, and
            // "the way is to your right" under an arrow pointing straight up is
            // the screen arguing with itself.
            payload["bearingDeg"] =
                quantise(needleBearing(frame, leg, checkpointAlong(leg)), 5f).toInt()
        }

        if (payload == lastEmitted && now - lastEmittedAt < STATE_HEARTBEAT_MS) return
        lastEmitted = payload
        lastEmittedAt = now
        mainHandler.post { eventSink?.success(payload) }
    }

    /**
     * Where the destination is relative to where the phone is pointing, in
     * degrees, positive to the right.
     *
     * This is what the arrow points along, and what the screen turns into
     * "the way is to your left" for a walker who has swung too far round.
     */
    private fun bearingToPoint(frame: Frame, x: Float, z: Float): Float {
        val translation = frame.camera.pose.translation
        val toPoint = atan2(x - translation[0], -(z - translation[2]))
        return wrapDegrees((toPoint - cameraYaw(frame)) * 180f / Math.PI.toFloat())
    }

    /** An angle in degrees folded into (-180, 180]. */
    private fun wrapDegrees(degrees: Float): Float {
        var delta = degrees
        while (delta > 180f) delta -= 360f
        while (delta < -180f) delta += 360f
        return delta
    }

    private fun quantise(value: Float, step: Float): Double =
        (Math.round(value / step) * step).toDouble()

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        renderHandler?.post { lastEmitted = null }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // --- ML Kit frames ------------------------------------------------------

    /**
     * Hands a camera frame to Dart for ML Kit, a few times a second.
     *
     * This is the part that lets sign reading and obstacle detection survive an
     * AR screen. The alternative — running ML Kit natively — would split a
     * pipeline whose interesting half (fuzzy landmark matching, the callout
     * policy, the wording) is Dart, tested, and has no business being written
     * twice.
     *
     * The cost is one YUV copy per analysed frame. That is emphatically not the
     * JPEG mistake the capture screen made: there is no encode, no decode, and
     * no per-pixel work in Dart — ML Kit takes these bytes as they are — and it
     * happens five times a second rather than sixty.
     */
    private fun analyse(frame: Frame) {
        if (!analysisEnabled) return
        if (frameSink == null) return
        val now = System.currentTimeMillis()
        if (now - lastAnalysisAt < ANALYSIS_MIN_INTERVAL_MS) return
        if (analysisInFlight) {
            if (now - analysisSentAt < ANALYSIS_ACK_TIMEOUT_MS) return
            Log.w(TAG, "Analysis answer overdue; restarting the feed")
        }
        lastAnalysisAt = now

        var image: Image? = null
        try {
            val acquired = frame.acquireCameraImage()
            image = acquired
            // Cut for whichever analyser is next: a magnified centre crop for
            // sign reading, the whole field of view subsampled for obstacles.
            // Both land on the same pixel count, so the session costs what it
            // always cost however large a sensor image is arriving.
            val framing = AnalysisFraming.framingFor(
                acquired.width,
                acquired.height,
                wantsText = analysisWantsText,
            )
            val width = framing.outWidth
            val height = framing.outHeight
            val length = toNv21(acquired, framing)
            val bytes = nv21.copyOf(length)
            // Back camera: the sensor image is rotated by its mounting, and the
            // display rotation undoes part of that. Same arithmetic the camera
            // plugin path does in Dart, done here because only native knows
            // both numbers.
            val rotation = (sensorOrientation - displayDegrees() + 360) % 360
            analysisInFlight = true
            analysisSentAt = System.currentTimeMillis()
            mainHandler.post {
                // Read again here rather than captured above: a screen that has
                // gone away between the two cancels its listener, and pushing
                // into a dead sink is a platform-channel warning per frame.
                frameSink?.success(
                    mapOf(
                        "bytes" to bytes,
                        "width" to width,
                        "height" to height,
                        "rotation" to rotation,
                    )
                )
            }
        } catch (e: NotYetAvailableException) {
            // Routine on the first frames: the CPU image lags the GPU one.
        } catch (e: Exception) {
            Log.w(TAG, "Analysis frame failed: $e")
        } finally {
            image?.close()
        }
    }

    private fun displayDegrees(): Int = when (displayRotation) {
        Surface.ROTATION_90 -> 90
        Surface.ROTATION_180 -> 180
        Surface.ROTATION_270 -> 270
        else -> 0
    }

    /**
     * YUV_420_888 to NV21, into the reusable buffer. Returns the byte count.
     *
     * Written the slow, obviously-correct way — row by row, honouring both
     * strides — rather than with the semi-planar shortcut that copies the V
     * plane wholesale. That shortcut is right on most devices and produces
     * colour-swapped garbage on the rest, and the whole loop costs a
     * millisecond or two at the resolution [chooseCameraConfig] asks for.
     * ML Kit reads luminance for both text and boxes anyway.
     */
    private fun toNv21(image: Image, framing: Framing): Int {
        val crop = framing.crop
        val step = framing.step
        val width = framing.outWidth
        val height = framing.outHeight
        val needed = width * height * 3 / 2
        if (nv21.size < needed) nv21 = ByteArray(needed)

        val yPlane = image.planes[0]
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]

        var out = 0
        val yBuffer = yPlane.buffer
        val yRowStride = yPlane.rowStride
        val yPixelStride = yPlane.pixelStride
        if (step == 1 && yPixelStride == 1) {
            // The common case, and the fast one: whole rows of the crop copied
            // straight out.
            for (row in 0 until height) {
                yBuffer.position((crop.y + row) * yRowStride + crop.x)
                yBuffer.get(nv21, out, width)
                out += width
            }
        } else {
            for (row in 0 until height) {
                var index = (crop.y + row * step) * yRowStride + crop.x * yPixelStride
                for (col in 0 until width) {
                    nv21[out++] = yBuffer.get(index)
                    index += yPixelStride * step
                }
            }
        }

        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        val uRowStride = uPlane.rowStride
        val vRowStride = vPlane.rowStride
        val uPixelStride = uPlane.pixelStride
        val vPixelStride = vPlane.pixelStride
        // Chroma is subsampled two-by-two, so the crop's offsets and the
        // sampling step both halve here. [AnalysisFraming] guarantees every one
        // of those numbers is even, which is what keeps this from shearing the
        // colour planes against the luma one.
        val chromaX = crop.x / 2
        val chromaY = crop.y / 2
        for (row in 0 until height / 2) {
            val sourceRow = chromaY + row * step
            var uIndex = sourceRow * uRowStride + chromaX * uPixelStride
            var vIndex = sourceRow * vRowStride + chromaX * vPixelStride
            for (col in 0 until width / 2) {
                // NV21 is V then U, which is the ordering that trips people up.
                nv21[out++] = vBuffer.get(vIndex)
                nv21[out++] = uBuffer.get(uIndex)
                uIndex += uPixelStride * step
                vIndex += vPixelStride * step
            }
        }
        return out
    }
}
