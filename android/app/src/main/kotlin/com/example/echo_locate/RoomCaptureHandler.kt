package com.example.echo_locate

import android.app.Activity
import android.content.pm.PackageManager
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.util.Log
import android.view.Surface
import androidx.core.content.ContextCompat
import com.google.ar.core.Anchor
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry

/**
 * Capturing room corners in AR — floorplan spec §2.
 *
 * ## How the camera reaches the screen
 *
 * ARCore renders the camera into an external GL texture on this handler's own
 * thread; [CameraBackgroundRenderer] blits that texture into a
 * [TextureRegistry.SurfaceProducer] surface, and Flutter composites it with a
 * `Texture` widget. **No camera pixels cross the platform channel.** The event
 * channel carries only tracking state, which changes a handful of times a
 * minute rather than sixty times a second.
 *
 * The first version did stream the camera to Flutter, as throttled JPEG frames
 * drawn with `Image.memory`, on the reasoning that a tapping interface needs
 * only enough frames to aim with. On a phone that was wrong twice over: ten
 * frames a second does not read as a camera, and the per-frame subsample,
 * software JPEG encode and Dart-side decode cost so much — most of it on the
 * same thread as `session.update()` — that it degraded the tracking the whole
 * screen depends on. The lag was not the throttle; the throttle was there
 * because of the cost. Removing the cost removes both.
 *
 * ## Status on this project's hardware
 *
 * The ARCore path has now been run on a phone, which is how the preview
 * problem above surfaced. [availabilityString] is what tells a certified
 * device from an uncertified one at runtime, and the UI renders "this device
 * cannot scan" as a normal state rather than an error.
 */
/**
 * Whoever currently holds the camera through ARCore.
 *
 * ARCore takes the camera **exclusively**, and this app has two things that
 * want it: the depth spike and room capture. Navigating from one screen to the
 * other left the first session running, so the second failed to start with a
 * `CameraNotAvailableException` — and to the user that reads as the feature
 * being broken on their phone rather than as two screens disagreeing.
 *
 * Claiming stops whoever held it before. Deliberately a single global: there is
 * one camera, so there is one holder, and modelling it as anything else invites
 * the same bug back in a third place.
 */
object ArCoreSessionOwner {
    private var current: (() -> Unit)? = null

    /** Releases the previous holder and records [release] as the new one. */
    @Synchronized
    fun claim(release: () -> Unit) {
        val previous = current
        current = release
        previous?.invoke()
    }

    @Synchronized
    fun releaseIfHeld(release: () -> Unit) {
        if (current === release) current = null
    }
}

class RoomCaptureHandler(
    private val activity: Activity,
    private val textures: TextureRegistry,
) : MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "echo_locate/arcore_capture"
        const val EVENT_CHANNEL = "echo_locate/arcore_capture/frames"
        private const val TAG = "RoomCapture"

        /** How often [logPlanes] prints, in milliseconds. */
        private const val PLANE_LOG_INTERVAL_MS = 2000L
    }

    private var session: Session? = null
    private var eventSink: EventChannel.EventSink? = null

    private var renderThread: HandlerThread? = null
    private var renderHandler: Handler? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    /** The GL context, the camera texture and the surface Flutter composites. */
    private val gl = ArGlSurface(textures)

    /** The texture id handed to Dart, so a second `start` answers the same one. */
    private var startedTextureId: Long = -1L

    private val renderer = CameraBackgroundRenderer()
    private val markers = AnchorMarkerRenderer()
    private val hitTester = SurfaceHitTester()

    /**
     * Which anchors to draw, as Dart last described them.
     *
     * Dart decides rather than native inferring it from [anchors], because
     * native holds every anchor that has ever been created this session and
     * only Dart knows which of them are still the current draft, which became
     * a door, and in **what order** the outline runs. Volatile immutable lists:
     * written from the platform thread on each tap, read from the render thread
     * every frame, and a torn read here would draw a wall to a corner that is
     * no longer there.
     */
    @Volatile
    private var cornerMarkerIds: List<String> = emptyList()

    @Volatile
    private var doorMarkerIds: List<String> = emptyList()

    /** Refilled every frame from the anchors above — see [WorldPoints]. */
    private val cornerPoints = WorldPoints()
    private val doorPoints = WorldPoints()

    @Volatile
    private var running = false

    /**
     * The last state pushed to Dart, so identical ones are not pushed again.
     *
     * The pump runs at camera rate and tracking state changes a handful of
     * times a minute. Emitting every frame meant a `Cubit` state per frame and
     * therefore a full rebuild of the capture screen — segmented buttons,
     * floor picker, warnings and all — sixty times a second, for information
     * that had not changed. Nulled in [onListen] so a fresh listener still gets
     * the current state rather than waiting for it to change.
     */
    private var lastEmitted: Map<String, Any?>? = null

    /** Throttle for [logPlanes]. */
    private var lastPlaneLog = 0L

    /**
     * A tap waiting for the next frame.
     *
     * Hit-testing needs a live [Frame], and a Frame is only valid until the
     * next `update()`. Rather than hold one across the channel boundary — which
     * would be a use-after-free the moment the pump ran — a request is parked
     * here and serviced on the render thread immediately after the next update.
     *
     * Guarded by [hitLock] because it is written from the platform thread and
     * read from the render thread. Unsynchronised, a tap is occasionally
     * dropped or answered twice, intermittently and unreproducibly — the worst
     * shape a bug can have in something a person is standing in a corridor
     * using.
     */
    private val hitLock = Any()
    private var pendingHit: PendingHit? = null

    /**
     * The Flutter view ARCore is told it is drawing into, and the space taps
     * arrive in.
     *
     * **Handing these to `setDisplayGeometry` is what makes hit-testing
     * correct**, and it removes a whole class of bug rather than working
     * around it. ARCore takes the *display rotation* and the *view size* and
     * does the camera-to-view mapping itself — sensor orientation, aspect
     * mismatch and all.
     *
     * The same geometry drives the preview: [CameraBackgroundRenderer] asks
     * ARCore for its texture coordinates rather than deriving them, so the
     * picture and the taps are mapped by one calculation and cannot disagree.
     * The old JPEG path rotated the image from `SENSOR_ORIENTATION`
     * separately, which is two calculations that only happened to agree.
     */
    private var viewWidth = 0
    private var viewHeight = 0
    private var displayRotation = 0

    /**
     * Which way up the display currently is, as `Surface.ROTATION_*`.
     *
     * Read here rather than passed in from Dart. Flutter has no portable way to
     * report Android's display rotation, so the Dart side sent a hardcoded
     * zero — correct only while the phone is held portrait, and this app locks
     * no orientation. Turning the phone sideways therefore left ARCore mapping
     * every tap through a portrait viewport, which lands corners a long way
     * from the finger with nothing on screen to suggest why. The activity knows
     * the answer; asking it is both shorter and always right.
     */
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

    /**
     * Anchors for the corners of the room being captured, by the id Dart knows
     * them as.
     *
     * Held natively rather than handed over because an `Anchor` is a live
     * ARCore object, not a value — it keeps being corrected as the session
     * learns more about the room. Dart holds ids and the positions as they
     * were at the moment of tapping; [resolveAnchors] is what turns those back
     * into positions ARCore currently believes in.
     */
    private val anchors = mutableMapOf<String, Anchor>()
    private var nextAnchorId = 1

    private data class PendingHit(
        val u: Float,
        val v: Float,
        /** False for door taps — see [SurfaceHitTester.hit]. */
        val lockToSurface: Boolean,
        val result: MethodChannel.Result,
    )

    // --- MethodChannel ------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkAvailability" -> result.success(availabilityString())
            "start" -> start(call, result)
            "stop" -> {
                stop()
                result.success(null)
            }
            "hitTest" -> queueHitTest(call, result)
            "setViewport" -> {
                applyViewport(call)
                result.success(null)
            }
            "resolveAnchors" -> resolveAnchors(call, result)
            "setMarkers" -> {
                setMarkers(call)
                result.success(null)
            }
            "releaseAnchors" -> {
                releaseAnchors(call.argument<List<String>>("ids") ?: emptyList())
                result.success(null)
            }
            "resetPlaneLock" -> {
                // Posted to the render thread: the tester is read there on
                // every tap, and clearing it from the platform thread is a data
                // race that shows up as one corner landing on the old surface.
                renderHandler?.post { hitTester.reset() }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Maps ARCore's availability enum to a stable string for Dart.
     *
     * Same mapping as [ArCoreDepthHandler] on purpose — it is what tells an
     * uncertified device apart from a supported one that merely needs an ARCore
     * update, and that distinction decides whether the UI offers scanning at
     * all or sends the user to photo tracing.
     */
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

    /**
     * Records the view ARCore is drawing into and tells it, and Flutter, and
     * the GL surface.
     *
     * Called on start and again whenever the Flutter view changes size or the
     * device rotates. Three things have to move together: ARCore's display
     * geometry (or taps land against a viewport that no longer exists), the
     * producer's buffer size (or the preview is stretched), and the EGL window
     * surface (which is bound to the producer's `Surface` and does not follow
     * it across a resize).
     */
    private fun applyViewport(call: MethodCall) {
        val width = (call.argument<Int>("width") ?: 0).coerceAtLeast(1)
        val height = (call.argument<Int>("height") ?: 0).coerceAtLeast(1)
        val rotation = currentDisplayRotation()
        if (width == viewWidth && height == viewHeight && rotation == displayRotation) {
            return
        }

        viewWidth = width
        viewHeight = height
        displayRotation = rotation

        gl.resizeProducer(width, height)

        // Session and GL surface are both thread-affine, so both go to the
        // thread that owns them.
        renderHandler?.post {
            try {
                session?.setDisplayGeometry(displayRotation, viewWidth, viewHeight)
            } catch (e: Exception) {
                Log.w(TAG, "setDisplayGeometry failed: $e")
            }
            gl.rebind()
        }
    }

    /**
     * Current positions of the named anchors, as ARCore believes them **now**.
     *
     * The whole point of anchoring. Between the first corner of a room and the
     * last, ARCore may have lost tracking and relocalised, shifting its idea of
     * where the world origin is. The positions Dart recorded at tap time are
     * then in a frame that no longer exists, and the room comes out the wrong
     * shape with nothing to indicate it. Re-reading at close returns every
     * corner in one consistent frame.
     *
     * An anchor whose tracking state has gone is omitted rather than guessed
     * at — the caller keeps its tapped position, which is the best that is
     * left, and knows the corner is less trustworthy.
     */
    private fun resolveAnchors(call: MethodCall, result: MethodChannel.Result) {
        val ids = call.argument<List<String>>("ids") ?: emptyList()
        val handler = renderHandler
        if (handler == null) {
            result.success(emptyMap<String, Any?>())
            return
        }

        // On the render thread: anchor poses are session state, and reading
        // them from the platform thread races the pump.
        handler.post {
            val resolved = mutableMapOf<String, Map<String, Any?>>()
            for (id in ids) {
                val anchor = anchors[id] ?: continue
                if (anchor.trackingState != TrackingState.TRACKING) continue
                val translation = anchor.pose.translation
                resolved[id] = mapOf(
                    "x" to translation[0].toDouble(),
                    "z" to translation[2].toDouble(),
                )
            }
            mainHandler.post { result.success(resolved) }
        }
    }

    /**
     * Records which anchors the preview should draw, and in which order.
     *
     * Cheap and idempotent: two lists of short strings, sent when a corner is
     * placed, undone or closed — a handful of times per room, not per frame.
     * Ids naming an anchor that has since been detached are ignored rather than
     * rejected, so a release racing a redraw is a marker that stops being drawn
     * rather than an error crossing the channel.
     */
    private fun setMarkers(call: MethodCall) {
        cornerMarkerIds = call.argument<List<String>>("corners")?.toList() ?: emptyList()
        doorMarkerIds = call.argument<List<String>>("doors")?.toList() ?: emptyList()
    }

    /** Detaches anchors that are no longer needed. */
    private fun releaseAnchors(ids: List<String>) {
        renderHandler?.post {
            for (id in ids) {
                // Anchors cost ARCore tracking work on every frame. A session
                // that never releases them gets slower the longer a building is
                // walked, which is exactly the session that matters most.
                anchors.remove(id)?.detach()
            }
        } ?: ids.forEach { anchors.remove(it) }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        if (running) {
            result.success(mapOf("textureId" to startedTextureId))
            return
        }
        // Recorded before the session exists so `setDisplayGeometry` can be
        // called the moment it resumes, rather than from inside the frame loop
        // where a first frame that throws left it never called at all.
        viewWidth = (call.argument<Int>("width") ?: 0).coerceAtLeast(1)
        viewHeight = (call.argument<Int>("height") ?: 0).coerceAtLeast(1)
        displayRotation = currentDisplayRotation()
        if (ContextCompat.checkSelfPermission(
                activity,
                android.Manifest.permission.CAMERA,
            ) != PackageManager.PERMISSION_GRANTED
        ) {
            // Requesting is Dart's job — the camera primer flow owns that — so
            // native only reports the fact.
            result.error("permission", "Camera permission not granted", null)
            return
        }

        val availability = availabilityString()
        if (availability != "supported") {
            result.error("unavailable", "ARCore not available: $availability", null)
            return
        }

        // Whoever else had the camera gets it taken off them, rather than this
        // session failing because they never let go.
        ArCoreSessionOwner.claim(::stop)

        try {
            val newSession = Session(activity)
            newSession.configure(
                newSession.config.apply {
                    // HORIZONTAL covers both facings: floors and ceilings are
                    // both legitimate targets. See SurfaceHitTester for why
                    // walls are never hit-tested.
                    planeFindingMode = Config.PlaneFindingMode.HORIZONTAL
                    updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    focusMode = Config.FocusMode.AUTO
                    // Depth is a bonus, not a requirement: capture needs planes
                    // and pose, both of which work without it. Enabling it when
                    // present improves hit-test quality at no cost, and its
                    // absence must not gate a device out of scanning.
                    if (newSession.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                        depthMode = Config.DepthMode.AUTOMATIC
                    }
                }
            )
            session = newSession

            // Created on the platform thread, which is where Flutter's texture
            // registry expects to be called.
            val textureId = gl.createProducer(viewWidth, viewHeight)
            startedTextureId = textureId
            gl.onSurfaceRebound = { renderer.invalidateGeometry() }

            val thread = HandlerThread("arcore-capture").also { it.start() }
            renderThread = thread
            renderHandler = Handler(thread.looper)
            running = true
            hitTester.reset()
            lastEmitted = null
            // A restarted session has no anchors, and ids from the last one
            // would name anchors this one never created.
            cornerMarkerIds = emptyList()
            doorMarkerIds = emptyList()

            renderHandler?.post {
                try {
                    gl.createContext()
                    if (!renderer.prepare()) {
                        // A driver that will not compile a textured quad is a
                        // black preview and nothing worse — tracking, hit-tests
                        // and the plan all still work — so this is logged and
                        // carried rather than failed.
                        Log.e(TAG, "Camera background renderer unavailable")
                    }
                    if (!markers.prepare()) {
                        // Same bargain, one step smaller: no markers means the
                        // corner count and the plan preview are the only
                        // feedback, which is what this screen shipped with.
                        Log.e(TAG, "Anchor marker renderer unavailable")
                    }
                    newSession.setCameraTextureName(gl.cameraTextureId)
                    newSession.resume()
                    // Before the first frame, unconditionally. Doing this
                    // inside the pump meant a first frame that threw — which
                    // `NotYetAvailableException` makes routine — left the
                    // geometry unset and every hit-test resolving to the
                    // top-left pixel.
                    newSession.setDisplayGeometry(
                        displayRotation,
                        viewWidth,
                        viewHeight,
                    )
                    mainHandler.post { result.success(mapOf("textureId" to textureId)) }
                    pumpFrames()
                } catch (e: CameraNotAvailableException) {
                    running = false
                    mainHandler.post {
                        gl.releaseProducer()
                        result.error("camera", "Camera not available: ${e.message}", null)
                    }
                } catch (e: Exception) {
                    running = false
                    mainHandler.post {
                        gl.releaseProducer()
                        result.error("start", "ARCore start failed: ${e.message}", null)
                    }
                }
            }
        } catch (e: UnavailableException) {
            result.error("unavailable", "ARCore unavailable: ${e.message}", null)
        } catch (e: Exception) {
            result.error("start", "ARCore session creation failed: ${e.message}", null)
        }
    }

    fun stop() {
        if (!running) return
        running = false
        startedTextureId = -1L
        ArCoreSessionOwner.releaseIfHeld(::stop)

        val handler = renderHandler
        val thread = renderThread
        renderHandler = null
        renderThread = null
        lastEmitted = null
        cornerMarkerIds = emptyList()
        doorMarkerIds = emptyList()

        // A tap still waiting when the session goes away would otherwise leave
        // its Dart future hanging forever.
        synchronized(hitLock) {
            pendingHit?.let { pending ->
                mainHandler.post { pending.result.success(null) }
            }
            pendingHit = null
        }

        handler?.post {
            try {
                for (anchor in anchors.values) anchor.detach()
                anchors.clear()
                session?.pause()
                session?.close()
            } catch (e: Exception) {
                Log.w(TAG, "Session teardown failed: $e")
            }
            session = null
            renderer.release()
            markers.release()
            gl.destroy()
            thread?.quitSafely()
            // The producer belongs to Flutter and is released on its thread,
            // after the GL surface built on it has gone — the other order
            // leaves the context drawing into a surface that was handed back.
            mainHandler.post { gl.releaseProducer() }
        } ?: run {
            session = null
            thread?.quitSafely()
            gl.releaseProducer()
        }
    }

    /**
     * Parks a tap for the next frame.
     *
     * [u] and [v] arrive normalised to 0..1 rather than in pixels, so Dart never
     * has to know the size of the view it is laid out in — and a preview widget
     * at any size maps onto the same point. They are scaled here into the
     * geometry ARCore was configured with.
     */
    private fun queueHitTest(call: MethodCall, result: MethodChannel.Result) {
        if (!running) {
            result.error("notRunning", "Capture session is not running", null)
            return
        }
        val u = (call.argument<Double>("u") ?: 0.0).toFloat()
        val v = (call.argument<Double>("v") ?: 0.0).toFloat()
        val lock = call.argument<Boolean>("lock") ?: true

        val previous = synchronized(hitLock) {
            val was = pendingHit
            pendingHit = PendingHit(u, v, lock, result)
            was
        }
        // Two taps inside one frame interval: the earlier one is answered null
        // rather than dropped, so its future always completes.
        previous?.result?.success(null)
    }

    // --- Frame loop ---------------------------------------------------------

    /**
     * Drives `session.update()`, draws the camera, and services taps.
     *
     * ARCore is a pull API — it produces a frame only when asked — so this loop,
     * not a callback, is what makes tracking and planes exist at all.
     *
     * The loop is paced by `eglSwapBuffers`, which blocks until the display is
     * ready for the next frame. That is a feature: the previous version had
     * nothing to block on and re-posted itself as fast as the CPU allowed,
     * burning a core to produce frames nobody was going to see.
     */
    private fun pumpFrames() {
        val current = session ?: return
        if (!running) return

        try {
            val frame = current.update()
            servicePendingHit(frame)
            drawFrame(frame)
            emitState(frame)
            logPlanes(current)
        } catch (e: Exception) {
            if (e is CameraNotAvailableException) {
                Log.w(TAG, "Camera lost, stopping: $e")
                mainHandler.post { stop() }
                return
            }
            // Everything else — a frame already superseded, an image not yet
            // available — is expected during normal operation.
        }

        renderHandler?.post { pumpFrames() }
    }

    /**
     * What ARCore has actually found, by plane type, a few times a minute.
     *
     * The one question the UI cannot answer for itself: "aim at the ceiling"
     * is useless advice if ARCore never fits a ceiling plane, and from inside
     * the app a ceiling it has not found is indistinguishable from a ceiling
     * the user has not pointed at. Cheap — a list walk every two seconds — and
     * it is the first thing worth reading when a surface refuses to lock.
     */
    private fun logPlanes(session: Session) {
        val now = System.currentTimeMillis()
        if (now - lastPlaneLog < PLANE_LOG_INTERVAL_MS) return
        lastPlaneLog = now

        var floor = 0
        var ceiling = 0
        var vertical = 0
        var tracked = 0
        val planes = session.getAllTrackables(Plane::class.java)
        for (plane in planes) {
            if (plane.trackingState != TrackingState.TRACKING) continue
            tracked++
            when (plane.type) {
                Plane.Type.HORIZONTAL_UPWARD_FACING -> floor++
                Plane.Type.HORIZONTAL_DOWNWARD_FACING -> ceiling++
                Plane.Type.VERTICAL -> vertical++
                else -> {}
            }
        }
        Log.i(
            TAG,
            "planes tracked=$tracked of ${planes.count()} " +
                "floor=$floor ceiling=$ceiling vertical=$vertical",
        )
    }

    private fun drawFrame(frame: Frame) {
        if (!gl.canDraw || !renderer.isReady) return
        renderer.draw(frame, gl.cameraTextureId, viewWidth, viewHeight)
        drawMarkers(frame)
        // A failed swap means the surface went away underneath us — the app is
        // going to the background, or Flutter recreated it. Drawing stops there;
        // tracking keeps running so a half-captured room survives, and the
        // surface is rebound on the next viewport update or session restart.
        gl.swapBuffers()
    }

    /**
     * Draws the corners placed so far on top of the camera image.
     *
     * Reading the anchors here, in the same frame that drew the camera, is the
     * whole point: an anchor's pose is corrected as ARCore learns the room, so
     * a marker follows its corner through a relocalisation instead of sitting
     * where the world used to be. See [AnchorMarkerRenderer].
     *
     * An anchor that has stopped tracking is skipped rather than drawn at its
     * last known pose. A marker frozen a metre from its corner is a worse lie
     * than no marker: it is exactly the picture a bad hit-test makes.
     */
    private fun drawMarkers(frame: Frame) {
        if (!markers.isReady) return

        cornerPoints.clear()
        for (id in cornerMarkerIds) {
            val anchor = anchors[id] ?: continue
            if (anchor.trackingState != TrackingState.TRACKING) continue
            cornerPoints.add(anchor.pose)
        }

        doorPoints.clear()
        for (id in doorMarkerIds) {
            val anchor = anchors[id] ?: continue
            if (anchor.trackingState != TrackingState.TRACKING) continue
            doorPoints.add(anchor.pose)
        }

        markers.draw(frame, cornerPoints, doorPoints, viewWidth, viewHeight)
    }

    private fun servicePendingHit(frame: Frame) {
        val pending = synchronized(hitLock) {
            val waiting = pendingHit
            pendingHit = null
            waiting
        } ?: return

        // Taps arrive normalised across the Flutter view and are scaled into
        // that same view's pixels — the space `setDisplayGeometry` was told
        // about, and therefore the space ARCore expects.
        val hit = try {
            hitTester.hit(
                frame,
                pending.u * viewWidth,
                pending.v * viewHeight,
                lockToSurface = pending.lockToSurface,
            )
        } catch (e: Exception) {
            Log.w(TAG, "Hit test failed: $e")
            null
        }

        val payload = hit?.let {
            val id = "anchor-${nextAnchorId++}"
            anchors[id] = it.anchor
            mapOf(
                "id" to id,
                "x" to it.x.toDouble(),
                "z" to it.z.toDouble(),
                "confidence" to it.confidence.toDouble(),
                "surface" to it.surface.wireName,
            )
        }

        mainHandler.post { pending.result.success(payload) }
    }

    /**
     * Pushes tracking state to Dart, but only when it has changed.
     *
     * See [lastEmitted]. What is here is what the screen actually renders: can
     * the user tap, what should they be told to do, and which surface this room
     * is being traced against.
     */
    private fun emitState(frame: Frame) {
        val camera = frame.camera

        val payload = mutableMapOf<String, Any?>(
            "trackingState" to camera.trackingState.name,
            "planeLocked" to hitTester.hasLock,
            "surface" to hitTester.lockedSurface?.wireName,
        )
        if (camera.trackingState == TrackingState.PAUSED) {
            // What to tell the user to *do*: point at texture, move slower,
            // turn a light on. A bare "paused" is not actionable.
            payload["failureReason"] = camera.trackingFailureReason.name
        }

        if (payload == lastEmitted) return
        lastEmitted = payload
        mainHandler.post { eventSink?.success(payload) }
    }

    // --- EventChannel -------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
        // A listener attaching mid-session would otherwise sit blank until
        // tracking next changed, which on a phone held still is a long time.
        renderHandler?.post { lastEmitted = null }
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

}
