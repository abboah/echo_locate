package com.example.echo_locate

import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.util.Log
import android.view.Surface
import io.flutter.view.TextureRegistry

/**
 * The GL context an ARCore session draws through, and the Flutter texture it
 * draws into.
 *
 * ## Why this is its own class
 *
 * Two screens now run an ARCore session behind a camera preview —
 * [ArGuidanceHandler] — which needs exactly this:
 * an `EGL_WINDOW_BIT` context, a window surface on a
 * [TextureRegistry.SurfaceProducer], an external texture for ARCore to write
 * the camera into, and the discipline to rebuild the surface when Flutter
 * hands back a new one.
 *
 * None of that is feature logic and all of it is the kind of code that is
 * subtly wrong in one copy and right in the other. The lifecycle bug that cost
 * an afternoon — a `Texture` widget pointing at a released id, drawing a blank
 * rectangle with no crash and nothing in the log — lived in exactly this
 * layer, so there is now one of it.
 *
 * ## Thread affinity
 *
 * Everything except [createProducer] and [releaseProducer] must run on the
 * thread that owns the GL context — the session's render thread. The two
 * exceptions belong to Flutter's platform thread, which is where the texture
 * registry expects to be called, and they are named so the difference is
 * visible at the call site.
 */
class ArGlSurface(private val textures: TextureRegistry) {

    companion object {
        private const val TAG = "ArGlSurface"
    }

    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var context: EGLContext = EGL14.EGL_NO_CONTEXT
    private var surface: EGLSurface = EGL14.EGL_NO_SURFACE
    private var config: EGLConfig? = null

    /** The external texture ARCore writes the camera image into. */
    var cameraTextureId: Int = 0
        private set

    private var producer: TextureRegistry.SurfaceProducer? = null

    /**
     * Whether there is a live window surface to draw into.
     *
     * False while the app is between surfaces. **Tracking deliberately keeps
     * running when this is false**: a session that survives a moment without a
     * surface comes back with its anchors and its map intact, and tearing it
     * down would lose a half-captured room over a transient.
     */
    var canDraw = false
        private set

    /**
     * Called whenever the window surface is replaced.
     *
     * Renderers cache geometry derived from the viewport — ARCore's
     * `hasDisplayGeometryChanged` is about ARCore's view of the world and knows
     * nothing about the surface being swapped underneath it, so without this
     * the first frames after a surface loss are drawn with coordinates for a
     * viewport that has gone.
     */
    var onSurfaceRebound: (() -> Unit)? = null

    /** Platform thread. The id Flutter's `Texture` widget renders. */
    fun createProducer(width: Int, height: Int): Long {
        val created = textures.createSurfaceProducer()
        created.setSize(width, height)
        producer = created
        return created.id()
    }

    /** Platform thread. Resizes the buffer Flutter composites. */
    fun resizeProducer(width: Int, height: Int) {
        producer?.setSize(width, height)
    }

    /**
     * Platform thread, and **after** the GL surface built on it has gone: the
     * other order leaves the context drawing into a surface that was handed
     * back.
     */
    fun releaseProducer() {
        producer?.release()
        producer = null
    }

    val producerSurface: Surface? get() = producer?.surface

    /**
     * Builds the context and binds it to the producer's surface.
     *
     * `Session.update()` requires a current GL context with a camera texture
     * bound — ARCore is a renderer API, not a headless sensor API. An earlier
     * version of the capture screen satisfied that with a 1x1 pbuffer, because
     * nothing was drawn and the camera reached Flutter as JPEG bytes instead.
     * Drawing into the producer's surface is what lets those bytes go away: the
     * camera image stays on the GPU from ARCore's texture to Flutter's
     * compositor.
     */
    fun createContext() {
        val target = producer?.surface ?: error("No producer surface")

        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(display != EGL14.EGL_NO_DISPLAY) { "No EGL display" }
        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize failed" }

        val configAttributes = intArrayOf(
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            // WINDOW, not PBUFFER: this context draws into a real surface.
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
                display, configAttributes, 0, configs, 0, 1, configCount, 0,
            ) && configCount[0] > 0
        ) { "No suitable EGL config" }
        config = configs[0]

        context = EGL14.eglCreateContext(
            display,
            configs[0],
            EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE),
            0,
        )
        check(context != EGL14.EGL_NO_CONTEXT) { "eglCreateContext failed" }

        bind(target)
        cameraTextureId = createExternalTexture()
    }

    /**
     * Makes [target] the draw target, replacing whatever was current.
     *
     * A window surface belongs to one `Surface`, so a resize — which hands back
     * a new one — needs this rather than a reconfiguration. The context and any
     * compiled programs survive; only the surface is rebuilt.
     */
    private fun bind(target: Surface) {
        if (surface != EGL14.EGL_NO_SURFACE) {
            EGL14.eglMakeCurrent(
                display,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_SURFACE,
                EGL14.EGL_NO_CONTEXT,
            )
            EGL14.eglDestroySurface(display, surface)
            surface = EGL14.EGL_NO_SURFACE
        }

        surface = EGL14.eglCreateWindowSurface(
            display,
            config,
            target,
            intArrayOf(EGL14.EGL_NONE),
            0,
        )
        check(surface != EGL14.EGL_NO_SURFACE) { "eglCreateWindowSurface failed" }
        check(EGL14.eglMakeCurrent(display, surface, surface, context)) {
            "eglMakeCurrent failed"
        }
        onSurfaceRebound?.invoke()
        canDraw = true
    }

    /** Rebuilds the draw target after a resize or a lost surface. */
    fun rebind() {
        val target = producer?.surface ?: return
        if (context == EGL14.EGL_NO_CONTEXT) return
        try {
            bind(target)
        } catch (e: Exception) {
            Log.w(TAG, "Could not rebind the preview surface: $e")
            canDraw = false
        }
    }

    /**
     * Presents the frame. False means the surface went away underneath us — the
     * app is going to the background, or Flutter recreated it — and drawing
     * stops until the next viewport update or session restart.
     */
    fun swapBuffers(): Boolean {
        if (EGL14.eglSwapBuffers(display, surface)) return true
        Log.w(TAG, "eglSwapBuffers failed; preview paused")
        canDraw = false
        return false
    }

    fun destroy() {
        canDraw = false
        cameraTextureId = 0
        if (display == EGL14.EGL_NO_DISPLAY) return
        EGL14.eglMakeCurrent(
            display,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_CONTEXT,
        )
        if (surface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(display, surface)
        if (context != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(display, context)
        EGL14.eglTerminate(display)
        display = EGL14.EGL_NO_DISPLAY
        context = EGL14.EGL_NO_CONTEXT
        surface = EGL14.EGL_NO_SURFACE
        config = null
    }

    private fun createExternalTexture(): Int {
        val ids = IntArray(1)
        GLES20.glGenTextures(1, ids, 0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, ids[0])
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
        return ids[0]
    }
}
