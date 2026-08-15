package com.example.echo_locate

import android.app.Activity
import android.content.pm.PackageManager
import android.graphics.ImageFormat
import android.graphics.Rect
import android.graphics.YuvImage
import android.media.Image
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
import androidx.core.content.ContextCompat
import com.google.ar.core.Anchor
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

/**
 * Capturing room corners in AR — floorplan spec §2.
 *
 * ## Why there is no OpenGL renderer here
 *
 * The spec says to fork `hello_ar_java` for its `BackgroundRenderer` and
 * `PlaneRenderer`, and warns that writing that from scratch is a week. Both
 * are true, and both are avoidable: [ArCoreDepthHandler] in this same package
 * already proved out the pattern that makes them unnecessary — run ARCore on a
 * **1x1 offscreen pbuffer context** on its own thread, drive `session.update()`
 * in a pump loop, and marshal what is needed to Flutter.
 *
 * So this handler streams the camera image as JPEG frames and does the drawing
 * in Flutter, where the design system, the theme and the accessibility work
 * already live. It costs some latency and buys the entire renderer.
 *
 * **Tuning point.** [FRAME_INTERVAL_MS] and [PREVIEW_JPEG_QUALITY] set that
 * trade. A tapping interface does not need sixty frames a second — it needs
 * enough to aim — so the defaults are deliberately modest. If the preview feels
 * laggy on a real device, lower the interval before reaching for anything
 * cleverer. The proper fix, if it is ever needed, is rendering into a Flutter
 * external texture via `SurfaceTexture`; that is a contained change to this
 * file and nothing in Dart would have to move.
 *
 * ## Status on this project's hardware
 *
 * The team's daily device is not ARCore-certified, so **none of the AR path
 * below has been run on a phone.** It is written to be tuned once a certified
 * device is in hand, and everything it produces — a `RoomPlan` — is already
 * exercised end to end by the photo-tracing path. [availabilityString] is what
 * tells the two situations apart at runtime, and the UI renders "this device
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

class RoomCaptureHandler(private val activity: Activity) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "echo_locate/arcore_capture"
        const val EVENT_CHANNEL = "echo_locate/arcore_capture/frames"
        private const val TAG = "RoomCapture"

        /**
         * Milliseconds between preview frames pushed to Flutter.
         *
         * ARCore itself is still updated every pump — pose and plane tracking
         * need every frame, and starving them degrades the hit-tests this whole
         * screen exists for. Only the *preview* is throttled. **Tuning point.**
         */
        private const val FRAME_INTERVAL_MS = 100L

        /** **Tuning point.** Lower if the bridge is the bottleneck. */
        private const val PREVIEW_JPEG_QUALITY = 55

        /**
         * Longest edge of the streamed preview, in pixels.
         *
         * The camera image is far larger than anything worth sending frame by
         * frame. Downscaling happens by cropping the JPEG compressor's input
         * rectangle rather than by resampling, which is cheap and good enough
         * to aim a finger with. **Tuning point.**
         */
        private const val PREVIEW_MAX_EDGE = 720
    }

    private var session: Session? = null
    private var eventSink: EventChannel.EventSink? = null

    private var renderThread: HandlerThread? = null
    private var renderHandler: Handler? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var cameraTextureId: Int = 0

    private val hitTester = FloorHitTester()

    @Volatile
    private var running = false

    private var lastFrameSentAt = 0L

    /**
     * The Flutter view ARCore is told it is drawing into, and the space taps
     * arrive in.
     *
     * **Handing these to `setDisplayGeometry` is what makes hit-testing
     * correct**, and it removes a whole class of bug rather than working
     * around it. ARCore takes the *display rotation* and the *view size* and
     * does the camera-to-view mapping itself — sensor orientation, aspect
     * mismatch and all — so nothing on the Dart side has to reason about how a
     * landscape sensor image lands in a portrait widget. The first version
     * passed the camera image's own dimensions and rotation 0, which is right
     * only on a device holding its phone sideways with a square screen.
     *
     * ARCore's mapping assumes the view shows the camera filling it and
     * cropping the overflow — the same thing Google's own `BackgroundRenderer`
     * draws, and the reason the Flutter preview uses `BoxFit.cover`. Change one
     * and the other has to change with it.
     */
    private var viewWidth = 0
    private var viewHeight = 0
    private var displayRotation = 0

    /** Degrees the camera image must be turned to appear upright in the view. */
    private var imageRotation = 90

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
                // race that shows up as one corner landing on the old floor.
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
     * Records the view ARCore is drawing into and tells it immediately.
     *
     * Called on start and again whenever the Flutter view changes size or the
     * device rotates. Cheap, and skipping it is what leaves ARCore mapping taps
     * against a viewport that no longer exists.
     */
    private fun applyViewport(call: MethodCall) {
        viewWidth = (call.argument<Int>("width") ?: 0).coerceAtLeast(1)
        viewHeight = (call.argument<Int>("height") ?: 0).coerceAtLeast(1)
        displayRotation = call.argument<Int>("rotation") ?: 0

        // Session-affine, so it goes to the thread that owns it.
        renderHandler?.post {
            try {
                session?.setDisplayGeometry(displayRotation, viewWidth, viewHeight)
            } catch (e: Exception) {
                Log.w(TAG, "setDisplayGeometry failed: $e")
            }
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

    /**
     * How far the camera image has to be turned to look upright in the view.
     *
     * The preview is a JPEG of the raw sensor image, which on essentially every
     * phone is landscape while the phone is held portrait. Flutter turns it by
     * this much. Hit-testing does **not** depend on it — that goes through
     * ARCore's own view geometry — so a wrong value here makes the picture look
     * odd without moving where the corners land.
     */
    private fun computeImageRotation(session: Session): Int = try {
        val manager =
            activity.getSystemService(android.content.Context.CAMERA_SERVICE)
                as android.hardware.camera2.CameraManager
        val sensor = manager
            .getCameraCharacteristics(session.cameraConfig.cameraId)
            .get(android.hardware.camera2.CameraCharacteristics.SENSOR_ORIENTATION)
            ?: 90
        val displayDegrees = when (displayRotation) {
            1 -> 90
            2 -> 180
            3 -> 270
            else -> 0
        }
        // Back camera. A front camera would mirror as well, and capture never
        // uses one — you cannot trace a room you are standing behind.
        (sensor - displayDegrees + 360) % 360
    } catch (e: Exception) {
        Log.w(TAG, "Sensor orientation unavailable, assuming 90: $e")
        90
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        if (running) {
            result.success(null)
            return
        }
        // Recorded before the session exists so `setDisplayGeometry` can be
        // called the moment it resumes, rather than from inside the frame loop
        // where a first frame that throws left it never called at all.
        viewWidth = (call.argument<Int>("width") ?: 0).coerceAtLeast(1)
        viewHeight = (call.argument<Int>("height") ?: 0).coerceAtLeast(1)
        displayRotation = call.argument<Int>("rotation") ?: 0
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
                    // HORIZONTAL only. Walls are never hit-tested — see
                    // FloorHitTester for why the interaction is built on the
                    // floor instead.
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

            val thread = HandlerThread("arcore-capture").also { it.start() }
            renderThread = thread
            renderHandler = Handler(thread.looper)
            running = true
            hitTester.reset()

            renderHandler?.post {
                try {
                    createEglContext()
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
                    imageRotation = computeImageRotation(newSession)
                    mainHandler.post { result.success(null) }
                    pumpFrames()
                } catch (e: CameraNotAvailableException) {
                    running = false
                    mainHandler.post {
                        result.error("camera", "Camera not available: ${e.message}", null)
                    }
                } catch (e: Exception) {
                    running = false
                    mainHandler.post {
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
        ArCoreSessionOwner.releaseIfHeld(::stop)

        val handler = renderHandler
        val thread = renderThread
        renderHandler = null
        renderThread = null

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
            destroyEglContext()
            thread?.quitSafely()
        } ?: run {
            session = null
            thread?.quitSafely()
        }
    }

    /**
     * Parks a tap for the next frame.
     *
     * [u] and [v] arrive normalised to 0..1 rather than in pixels, so Dart never
     * has to know the size of the image being streamed — and a preview widget
     * laid out at any size maps onto the same point. They are scaled here into
     * the geometry ARCore was configured with.
     */
    private fun queueHitTest(call: MethodCall, result: MethodChannel.Result) {
        if (!running) {
            result.error("notRunning", "Capture session is not running", null)
            return
        }
        val u = (call.argument<Double>("u") ?: 0.0).toFloat()
        val v = (call.argument<Double>("v") ?: 0.0).toFloat()

        val previous = synchronized(hitLock) {
            val was = pendingHit
            pendingHit = PendingHit(u, v, result)
            was
        }
        // Two taps inside one frame interval: the earlier one is answered null
        // rather than dropped, so its future always completes.
        previous?.result?.success(null)
    }

    // --- Frame loop ---------------------------------------------------------

    /**
     * Drives `session.update()` continuously.
     *
     * ARCore is a pull API — it produces a frame only when asked — so this loop,
     * not a callback, is what makes tracking and planes exist at all.
     */
    private fun pumpFrames() {
        val current = session ?: return
        if (!running) return

        try {
            val frame = current.update()
            servicePendingHit(frame)
            emitState(frame)
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
            )
        }

        mainHandler.post { pending.result.success(payload) }
    }

    private fun emitState(frame: Frame) {
        val camera = frame.camera
        val now = System.currentTimeMillis()
        val sendPreview = now - lastFrameSentAt >= FRAME_INTERVAL_MS

        var jpeg: ByteArray? = null
        if (sendPreview) {
            jpeg = try {
                frame.acquireCameraImage().use { image -> toJpeg(image) }
            } catch (e: Exception) {
                // NotYetAvailableException on the first frames is normal, and
                // no longer takes the display geometry down with it — that is
                // set once at resume.
                null
            }
            if (jpeg != null) lastFrameSentAt = now
        }

        val payload = mutableMapOf<String, Any?>(
            "trackingState" to camera.trackingState.name,
            "planeLocked" to hitTester.hasLock,
            "imageRotation" to imageRotation,
        )
        if (camera.trackingState == TrackingState.PAUSED) {
            // What to tell the user to *do*: point at texture, move slower,
            // turn a light on. A bare "paused" is not actionable.
            payload["failureReason"] = camera.trackingFailureReason.name
        }
        if (jpeg != null) payload["jpeg"] = jpeg

        emit(payload)
    }

    /**
     * YUV_420_888 to JPEG.
     *
     * Row and pixel strides are honoured rather than assumed. The hardware pads
     * rows on plenty of devices, and indexing by width alone shears the image —
     * the same class of bug the depth handler documents for its row stride.
     */
    private fun toJpeg(image: Image): ByteArray? {
        if (image.format != ImageFormat.YUV_420_888) return null

        // Integer subsample factor. The previous version computed this and then
        // divided the JPEG *quality* by it while compressing the full rect, so
        // PREVIEW_MAX_EDGE did nothing at all except make the picture blockier.
        // Dropping whole pixels is what actually shrinks a frame.
        val step = (maxOf(image.width, image.height) / PREVIEW_MAX_EDGE)
            .coerceAtLeast(1)
        // Even, so the chroma planes subsample in step with the luma one.
        val stride = if (step % 2 == 0 || step == 1) step else step + 1

        val width = (image.width / stride) and 1.inv()
        val height = (image.height / stride) and 1.inv()
        if (width < 2 || height < 2) return null

        val nv21 = ByteArray(width * height * 3 / 2)

        val yPlane = image.planes[0]
        val yBuffer = yPlane.buffer
        val yRowStride = yPlane.rowStride
        val yPixelStride = yPlane.pixelStride
        var offset = 0
        for (row in 0 until height) {
            val sourceRow = row * stride
            for (col in 0 until width) {
                nv21[offset++] =
                    yBuffer.get(sourceRow * yRowStride + col * stride * yPixelStride)
            }
        }

        // NV21 interleaves V then U, which is the order YuvImage expects.
        // Row and pixel strides are honoured rather than assumed: the hardware
        // pads rows on plenty of devices and indexing by width alone shears the
        // image — the same class of bug the depth handler documents.
        val uPlane = image.planes[1]
        val vPlane = image.planes[2]
        val uBuffer = uPlane.buffer
        val vBuffer = vPlane.buffer
        val uvRowStride = uPlane.rowStride
        val uvPixelStride = uPlane.pixelStride

        for (row in 0 until height / 2) {
            val sourceRow = row * stride
            for (col in 0 until width / 2) {
                val index = sourceRow * uvRowStride + col * stride * uvPixelStride
                if (index >= vBuffer.limit() || index >= uBuffer.limit()) continue
                nv21[offset++] = vBuffer.get(index)
                nv21[offset++] = uBuffer.get(index)
            }
        }

        val stream = ByteArrayOutputStream()
        val yuv = YuvImage(nv21, ImageFormat.NV21, width, height, null)
        return if (
            yuv.compressToJpeg(
                Rect(0, 0, width, height),
                PREVIEW_JPEG_QUALITY,
                stream,
            )
        ) {
            stream.toByteArray()
        } else {
            null
        }
    }

    private fun emit(payload: Map<String, Any?>) {
        mainHandler.post { eventSink?.success(payload) }
    }

    // --- EventChannel -------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // --- EGL ----------------------------------------------------------------

    /**
     * A 1x1 offscreen pbuffer context.
     *
     * `Session.update()` throws `MissingGlContextException` without a current
     * GL context and a bound camera texture — ARCore is a renderer API, not a
     * headless sensor API. Since nothing is drawn here, the smallest possible
     * surface satisfies it, on a thread of its own so the whole ARCore lifecycle
     * stays off the platform thread and out of Flutter's render path.
     */
    private fun createEglContext() {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val version = IntArray(2)
        EGL14.eglInitialize(eglDisplay, version, 0, version, 1)

        val configAttributes = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val configCount = IntArray(1)
        EGL14.eglChooseConfig(
            eglDisplay, configAttributes, 0, configs, 0, 1, configCount, 0,
        )

        eglContext = EGL14.eglCreateContext(
            eglDisplay,
            configs[0],
            EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
            0,
        )
        eglSurface = EGL14.eglCreatePbufferSurface(
            eglDisplay,
            configs[0],
            intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE),
            0,
        )
        EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)
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
    }
}
