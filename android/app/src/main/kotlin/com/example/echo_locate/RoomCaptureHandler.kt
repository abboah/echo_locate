package com.example.echo_locate

import android.app.Activity
import android.content.pm.PackageManager
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
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

    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var eglConfig: EGLConfig? = null
    private var cameraTextureId: Int = 0

    /** The Flutter-side texture the camera is drawn into. */
    private var surfaceProducer: TextureRegistry.SurfaceProducer? = null

    private val renderer = CameraBackgroundRenderer()
    private val hitTester = SurfaceHitTester()

    @Volatile
    private var running = false

    /**
     * Set when the window surface has gone and drawing must stop.
     *
     * Tracking deliberately keeps running: a session that survives a moment
     * without a surface comes back with its anchors and its map intact, and
     * tearing it down would lose a half-captured room over a transient.
     */
    private var canDraw = false

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

        surfaceProducer?.setSize(width, height)

        // Session and GL surface are both thread-affine, so both go to the
        // thread that owns them.
        renderHandler?.post {
            try {
                session?.setDisplayGeometry(displayRotation, viewWidth, viewHeight)
            } catch (e: Exception) {
                Log.w(TAG, "setDisplayGeometry failed: $e")
            }
            rebindWindowSurface()
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
            result.success(mapOf("textureId" to (surfaceProducer?.id() ?: -1L)))
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
            val producer = textures.createSurfaceProducer()
            producer.setSize(viewWidth, viewHeight)
            surfaceProducer = producer
            val textureId = producer.id()

            val thread = HandlerThread("arcore-capture").also { it.start() }
            renderThread = thread
            renderHandler = Handler(thread.looper)
            running = true
            hitTester.reset()
            lastEmitted = null

            renderHandler?.post {
                try {
                    createEglContext(producer.surface)
                    if (!renderer.prepare()) {
                        // A driver that will not compile a textured quad is a
                        // black preview and nothing worse — tracking, hit-tests
                        // and the plan all still work — so this is logged and
                        // carried rather than failed.
                        Log.e(TAG, "Camera background renderer unavailable")
                    }
                    cameraTextureId = createExternalTexture()
                    newSession.setCameraTextureName(cameraTextureId)
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
                        releaseProducer()
                        result.error("camera", "Camera not available: ${e.message}", null)
                    }
                } catch (e: Exception) {
                    running = false
                    mainHandler.post {
                        releaseProducer()
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
        canDraw = false
        ArCoreSessionOwner.releaseIfHeld(::stop)

        val handler = renderHandler
        val thread = renderThread
        renderHandler = null
        renderThread = null
        lastEmitted = null

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
            destroyEglContext()
            thread?.quitSafely()
            // The producer belongs to Flutter and is released on its thread,
            // after the GL surface built on it has gone — the other order
            // leaves the context drawing into a surface that was handed back.
            mainHandler.post { releaseProducer() }
        } ?: run {
            session = null
            thread?.quitSafely()
            releaseProducer()
        }
    }

    private fun releaseProducer() {
        surfaceProducer?.release()
        surfaceProducer = null
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
        if (!canDraw || !renderer.isReady) return
        renderer.draw(frame, cameraTextureId, viewWidth, viewHeight)
        if (!EGL14.eglSwapBuffers(eglDisplay, eglSurface)) {
            // The surface went away underneath us — the app is going to the
            // background, or Flutter recreated it. Stop drawing; tracking keeps
            // running so a half-captured room survives, and the surface is
            // rebound on the next viewport update or session restart.
            Log.w(TAG, "eglSwapBuffers failed; preview paused")
            canDraw = false
        }
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

    // --- EGL ----------------------------------------------------------------

    /**
     * A window surface on the texture Flutter composites.
     *
     * `Session.update()` requires a current GL context with a camera texture
     * bound — ARCore is a renderer API, not a headless sensor API. The earlier
     * version satisfied that with a 1x1 pbuffer, because nothing was drawn and
     * the camera reached Flutter as JPEG bytes instead. Drawing into the
     * producer's surface is what lets those bytes go away: the camera image
     * stays on the GPU from ARCore's texture to Flutter's compositor.
     */
    private fun createEglContext(surface: Surface) {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(eglDisplay != EGL14.EGL_NO_DISPLAY) { "No EGL display" }
        val version = IntArray(2)
        check(EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) { "eglInitialize failed" }

        val configAttributes = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            // WINDOW, not PBUFFER: this context draws into a real surface now.
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT,
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            // Flutter composites this texture with the widgets drawn over it,
            // so the buffer needs an alpha channel to be a valid layer.
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val configCount = IntArray(1)
        check(
            EGL14.eglChooseConfig(
                eglDisplay, configAttributes, 0, configs, 0, 1, configCount, 0,
            ) && configCount[0] > 0
        ) { "No suitable EGL config" }
        eglConfig = configs[0]

        eglContext = EGL14.eglCreateContext(
            eglDisplay,
            configs[0],
            EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
            0,
        )
        check(eglContext != EGL14.EGL_NO_CONTEXT) { "eglCreateContext failed" }

        bindWindowSurface(surface)
    }

    /**
     * Makes [surface] the draw target, replacing whatever was current.
     *
     * A window surface belongs to one `Surface`, so a resize — which hands back
     * a new one — needs this rather than a reconfiguration. The context and the
     * compiled program survive; only the surface is rebuilt.
     */
    private fun bindWindowSurface(surface: Surface) {
        if (eglSurface != EGL14.EGL_NO_SURFACE) {
            EGL14.eglMakeCurrent(
                eglDisplay,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_CONTEXT,
            )
            EGL14.eglDestroySurface(eglDisplay, eglSurface)
            eglSurface = EGL14.EGL_NO_SURFACE
        }

        eglSurface = EGL14.eglCreateWindowSurface(
            eglDisplay,
            eglConfig,
            surface,
            intArrayOf(EGL14.EGL_NONE),
            0,
        )
        check(eglSurface != EGL14.EGL_NO_SURFACE) { "eglCreateWindowSurface failed" }
        check(EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
            "eglMakeCurrent failed"
        }
        renderer.invalidateGeometry()
        canDraw = true
    }

    /** Rebuilds the draw target after a resize or a lost surface. */
    private fun rebindWindowSurface() {
        val producer = surfaceProducer ?: return
        if (eglContext == EGL14.EGL_NO_CONTEXT) return
        try {
            bindWindowSurface(producer.surface)
        } catch (e: Exception) {
            Log.w(TAG, "Could not rebind the preview surface: $e")
            canDraw = false
        }
    }

    private fun createExternalTexture(): Int {
        val textures = IntArray(1)
        GLES20.glGenTextures(1, textures, 0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textures[0])
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MIN_FILTER,
            GLES20.GL_LINEAR,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_MAG_FILTER,
            GLES20.GL_LINEAR,
        )
        // The camera image does not tile, and a driver sampling past its edge
        // with the default REPEAT wraps the far side of the frame into it.
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_S,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        GLES20.glTexParameteri(
            GLES11Ext.GL_TEXTURE_EXTERNAL_OES,
            GLES20.GL_TEXTURE_WRAP_T,
            GLES20.GL_CLAMP_TO_EDGE,
        )
        return textures[0]
    }

    private fun destroyEglContext() {
        if (eglDisplay == EGL14.EGL_NO_DISPLAY) return
        EGL14.eglMakeCurrent(
            eglDisplay,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_CONTEXT,
        )
        if (eglSurface != EGL14.EGL_NO_SURFACE) {
            EGL14.eglDestroySurface(eglDisplay, eglSurface)
        }
        if (eglContext != EGL14.EGL_NO_CONTEXT) {
            EGL14.eglDestroyContext(eglDisplay, eglContext)
        }
        EGL14.eglTerminate(eglDisplay)
        eglDisplay = EGL14.EGL_NO_DISPLAY
        eglContext = EGL14.EGL_NO_CONTEXT
        eglSurface = EGL14.EGL_NO_SURFACE
        eglConfig = null
    }
}
