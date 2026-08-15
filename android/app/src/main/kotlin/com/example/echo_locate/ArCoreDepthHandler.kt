package com.example.echo_locate

import android.app.Activity
import android.content.pm.PackageManager
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
import com.google.ar.core.ArCoreApk
import com.google.ar.core.Config
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.core.exceptions.CameraNotAvailableException
import com.google.ar.core.exceptions.UnavailableException
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.nio.ByteOrder
import java.nio.ShortBuffer

/**
 * M0 spike: ARCore depth + camera pose, pushed to Flutter over a platform
 * channel.
 *
 * Two channels, deliberately: a [MethodChannel] for control (which is
 * request/response — "can this device do it", "start", "stop") and an
 * [EventChannel] for the frame stream (which is push, at camera rate). Forcing
 * the stream through method calls would mean Dart polling a native loop.
 *
 * Runs its own GL context. ARCore's `Session.update()` requires a current
 * OpenGL context with a camera texture bound, and throws
 * `MissingGlContextException` without one — it is a renderer API, not a
 * headless sensor API. Since this spike renders nothing (it only reads depth
 * numbers), it creates a 1x1 offscreen pbuffer context on a dedicated thread
 * rather than borrowing Flutter's surface. That keeps the whole ARCore
 * lifecycle off the platform thread and out of the Flutter render path.
 */
class ArCoreDepthHandler(private val activity: Activity) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        const val METHOD_CHANNEL = "echo_locate/arcore_depth"
        const val EVENT_CHANNEL = "echo_locate/arcore_depth/frames"
        private const val TAG = "ArCoreDepth"

        /**
         * Depth is reported on a coarse grid rather than at full resolution.
         * A depth image is ~160x120; shipping all 19k values per frame over
         * the channel at camera rate would dominate the bridge for no benefit
         * to M0, whose acceptance check is "live depth numbers print". M3
         * accumulates a real point cloud and will read the full image natively
         * instead of marshalling it.
         */
        private const val GRID_COLUMNS = 16
        private const val GRID_ROWS = 12
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

    @Volatile
    private var running = false

    // --- MethodChannel ------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "checkAvailability" -> result.success(availabilityString())
            "isDepthSupported" -> result.success(isDepthSupported())
            "start" -> start(result)
            "stop" -> {
                stop()
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    /**
     * Maps ARCore's availability enum to a stable string for Dart.
     *
     * This is the single most important call in the spike: it is what lets an
     * uncertified device (which is most budget hardware) be told apart from a
     * supported one that merely needs an ARCore update, without either
     * crashing or silently pretending to scan.
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
     * Whether this device can produce depth at all. Being ARCore-certified and
     * supporting the Depth API are different things — the Depth API is
     * depth-from-motion and needs a device Google has validated for it, so a
     * device can pass [availabilityString] and still return false here.
     * Creating a throwaway session is the only way to ask.
     */
    private fun isDepthSupported(): Boolean {
        // Session is AutoCloseable but not Closeable, so `use` does not apply —
        // closing explicitly, and always, matters here because a leaked probe
        // session holds the camera and makes the next start() fail.
        var probe: Session? = null
        return try {
            probe = Session(activity)
            probe.isDepthModeSupported(Config.DepthMode.AUTOMATIC)
        } catch (e: Exception) {
            Log.w(TAG, "Depth support probe failed: $e")
            false
        } finally {
            try {
                probe?.close()
            } catch (e: Exception) {
                Log.w(TAG, "Depth probe close failed: $e")
            }
        }
    }

    private fun start(result: MethodChannel.Result) {
        if (running) {
            result.success(null)
            return
        }
        if (ContextCompat.checkSelfPermission(activity, android.Manifest.permission.CAMERA)
            != PackageManager.PERMISSION_GRANTED
        ) {
            // Requesting is Dart's job (permission_handler already owns the
            // camera primer flow); native only reports the fact.
            result.error("permission", "Camera permission not granted", null)
            return
        }

        val availability = availabilityString()
        if (availability != "supported") {
            result.error("unavailable", "ARCore not available: $availability", null)
            return
        }

        // ARCore holds the camera exclusively and room capture wants it too.
        // Claiming stops whoever had it, so navigating between the two screens
        // does not leave the second failing to start.
        ArCoreSessionOwner.claim(::stop)

        try {
            val newSession = Session(activity)
            if (!newSession.isDepthModeSupported(Config.DepthMode.AUTOMATIC)) {
                newSession.close()
                result.error(
                    "depthUnsupported",
                    "Device is ARCore-capable but has no Depth API support",
                    null,
                )
                return
            }
            newSession.configure(
                newSession.config.apply {
                    depthMode = Config.DepthMode.AUTOMATIC
                    // Depth-from-motion needs the pose to keep up with the
                    // frames; LATEST_CAMERA_IMAGE avoids blocking the loop on
                    // a frame that has already been superseded.
                    updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                    focusMode = Config.FocusMode.AUTO
                }
            )
            session = newSession

            val thread = HandlerThread("arcore-depth").also { it.start() }
            renderThread = thread
            renderHandler = Handler(thread.looper)
            running = true

            renderHandler?.post {
                try {
                    createEglContext()
                    cameraTextureId = createExternalTexture()
                    newSession.setCameraTextureName(cameraTextureId)
                    newSession.resume()
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

        // Tear down on the thread that owns the GL context and the session —
        // both are thread-affine, and closing them from the platform thread is
        // undefined behaviour.
        handler?.post {
            try {
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

    // --- Frame loop ---------------------------------------------------------

    /**
     * Drives `session.update()` continuously. ARCore is a pull API — it
     * delivers a frame only when asked — so this loop, not a callback, is what
     * makes depth arrive.
     */
    private fun pumpFrames() {
        val current = session ?: return
        if (!running) return

        try {
            val frame = current.update()
            val camera = frame.camera

            if (camera.trackingState == TrackingState.TRACKING) {
                // acquireDepthImage16Bits throws while depth is still
                // converging (depth-from-motion needs parallax — the user has
                // to move the phone before the first image exists). That is
                // normal, not an error, so it is caught per-frame below.
                frame.acquireDepthImage16Bits().use { depth ->
                    emit(buildPayload(depth, camera.pose, camera.trackingState))
                }
            } else {
                emit(
                    mapOf(
                        "trackingState" to camera.trackingState.name,
                        "hasDepth" to false,
                    )
                )
            }
        } catch (e: Exception) {
            // Includes NotYetAvailableException (depth still converging) and
            // DeadlineExceededException (frame already superseded). Both are
            // expected during normal operation; only stop on a session that
            // has genuinely gone away.
            if (e is CameraNotAvailableException) {
                Log.w(TAG, "Camera lost, stopping: $e")
                mainHandler.post { stop() }
                return
            }
        }

        renderHandler?.post { pumpFrames() }
    }

    /** Coarse depth grid + pose. See [GRID_COLUMNS] for why it's downsampled. */
    private fun buildPayload(depth: Image, pose: com.google.ar.core.Pose, state: TrackingState):
        Map<String, Any> {
        val width = depth.width
        val height = depth.height
        val plane = depth.planes[0]
        val buffer: ShortBuffer = plane.buffer.order(ByteOrder.nativeOrder()).asShortBuffer()
        // Row stride is in bytes and is NOT always width*2 — the hardware may
        // pad rows. Indexing by width alone shears the image on such devices.
        val rowStrideShorts = plane.rowStride / 2

        val grid = IntArray(GRID_COLUMNS * GRID_ROWS)
        var min = Int.MAX_VALUE
        var max = 0
        var sum = 0L
        var valid = 0

        for (row in 0 until GRID_ROWS) {
            val y = row * height / GRID_ROWS
            for (col in 0 until GRID_COLUMNS) {
                val x = col * width / GRID_COLUMNS
                val raw = buffer.get(y * rowStrideShorts + x).toInt()
                // DEPTH16 packs a confidence value in the top 3 bits; the
                // distance in millimetres is the low 13. Masking is a no-op
                // where confidence is unset, and prevents a garbage reading
                // of tens of metres where it is not.
                val millimeters = raw and 0x1FFF
                grid[row * GRID_COLUMNS + col] = millimeters
                // 0 means "no depth here", not "zero distance away" — it must
                // not be allowed to win the minimum.
                if (millimeters != 0) {
                    if (millimeters < min) min = millimeters
                    if (millimeters > max) max = millimeters
                    sum += millimeters
                    valid++
                }
            }
        }

        val translation = FloatArray(3)
        pose.getTranslation(translation, 0)
        val rotation = FloatArray(4)
        pose.getRotationQuaternion(rotation, 0)

        return mapOf(
            "hasDepth" to true,
            "trackingState" to state.name,
            "width" to width,
            "height" to height,
            "gridColumns" to GRID_COLUMNS,
            "gridRows" to GRID_ROWS,
            "grid" to grid.toList(),
            "minMillimeters" to if (valid == 0) 0 else min,
            "maxMillimeters" to max,
            "meanMillimeters" to if (valid == 0) 0 else (sum / valid).toInt(),
            "validSamples" to valid,
            "timestampNs" to depth.timestamp,
            "translation" to translation.toList(),
            "rotation" to rotation.toList(),
        )
    }

    private fun emit(payload: Map<String, Any>) {
        // EventSink is main-thread-only; the frame loop is not on it.
        mainHandler.post { eventSink?.success(payload) }
    }

    // --- EventChannel -------------------------------------------------------

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    // --- GL plumbing --------------------------------------------------------

    private fun createEglContext() {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(eglDisplay != EGL14.EGL_NO_DISPLAY) { "No EGL display" }
        val version = IntArray(2)
        check(EGL14.eglInitialize(eglDisplay, version, 0, version, 1)) { "eglInitialize failed" }

        val configAttribs = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        check(
            EGL14.eglChooseConfig(eglDisplay, configAttribs, 0, configs, 0, 1, numConfigs, 0) &&
                numConfigs[0] > 0
        ) { "No suitable EGL config" }

        eglContext = EGL14.eglCreateContext(
            eglDisplay,
            configs[0],
            EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
            0,
        )
        check(eglContext != EGL14.EGL_NO_CONTEXT) { "eglCreateContext failed" }

        // 1x1: nothing is ever drawn into it. The context exists only because
        // ARCore requires one to hand the camera texture to.
        eglSurface = EGL14.eglCreatePbufferSurface(
            eglDisplay,
            configs[0],
            intArrayOf(EGL14.EGL_WIDTH, 1, EGL14.EGL_HEIGHT, 1, EGL14.EGL_NONE),
            0,
        )
        check(eglSurface != EGL14.EGL_NO_SURFACE) { "eglCreatePbufferSurface failed" }
        check(EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext)) {
            "eglMakeCurrent failed"
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
        if (eglSurface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(eglDisplay, eglSurface)
        if (eglContext != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(eglDisplay, eglContext)
        EGL14.eglTerminate(eglDisplay)
        eglDisplay = EGL14.EGL_NO_DISPLAY
        eglContext = EGL14.EGL_NO_CONTEXT
        eglSurface = EGL14.EGL_NO_SURFACE
    }
}
