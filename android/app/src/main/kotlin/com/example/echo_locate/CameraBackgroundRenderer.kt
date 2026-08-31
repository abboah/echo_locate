package com.example.echo_locate

import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.util.Log
import com.google.ar.core.Coordinates2d
import com.google.ar.core.Frame
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * Draws the ARCore camera image straight into the surface Flutter composites.
 *
 * ## Why this exists now, having been avoided before
 *
 * The AR layer used to stream the camera to Flutter as JPEG frames and
 * let `Image.memory` draw them, on the reasoning that a tapping interface needs
 * only enough frames to aim with. On a phone that turned out to be wrong in the
 * way that matters: every frame was subsampled pixel by pixel out of a
 * `ByteBuffer`, JPEG-encoded in software, marshalled across the platform
 * channel, and decoded again in Dart — the better part of a hundred
 * milliseconds of work per frame, most of it on the same thread that drives
 * `session.update()`. So the preview was not merely capped at ten frames a
 * second; the encoding was **stealing the frames tracking needed**, which is
 * why it felt laggy rather than just choppy.
 *
 * Drawing the camera texture directly removes all of it. The image never leaves
 * the GPU: ARCore writes into an external texture, this class blits that
 * texture into a [android.view.Surface] Flutter handed over, and the Flutter
 * side is a `Texture` widget with no bytes crossing anything.
 *
 * ## The whole renderer is one textured quad
 *
 * The floorplan spec warned that forking `hello_ar_java`'s `BackgroundRenderer`
 * was a week of work. It is — if you also want plane grids, point clouds,
 * lighting estimation and anchor models. What this screen needs is the camera
 * on the screen, which is a full-viewport quad and a two-line fragment shader,
 * and the overlay drawing stays in Flutter where the design system and the
 * accessibility work already live.
 *
 * ## Texture coordinates come from ARCore, not from us
 *
 * [Frame.transformCoordinates2d] maps the quad's device coordinates to the
 * right patch of the camera image, accounting for sensor orientation, display
 * rotation and the aspect-ratio crop in one step. **That is the same mapping
 * `setDisplayGeometry` uses for hit-testing**, so the preview and the taps
 * cannot drift apart — which the old path could, since it rotated the JPEG with
 * a `RotatedBox` guess derived separately from `SENSOR_ORIENTATION`.
 */
class CameraBackgroundRenderer {

    companion object {
        private const val TAG = "CameraBackground"

        /** Two floats per corner, four corners, drawn as a triangle strip. */
        private const val COORDS_PER_VERTEX = 2
        private const val VERTEX_COUNT = 4

        /** The full viewport in normalised device coordinates. */
        private val NDC_QUAD = floatArrayOf(
            -1f, -1f,
            +1f, -1f,
            -1f, +1f,
            +1f, +1f,
        )

        private val VERTEX_SHADER = """
            attribute vec4 a_Position;
            attribute vec2 a_TexCoord;
            varying vec2 v_TexCoord;
            void main() {
              gl_Position = a_Position;
              v_TexCoord = a_TexCoord;
            }
        """.trimIndent()

        // The external-image extension has to be declared before anything else
        // in the shader, which is why this string starts where it does.
        private val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            varying vec2 v_TexCoord;
            uniform samplerExternalOES u_Texture;
            void main() {
              gl_FragColor = texture2D(u_Texture, v_TexCoord);
            }
        """.trimIndent()
    }

    private var program = 0
    private var positionAttribute = 0
    private var texCoordAttribute = 0
    private var textureUniform = 0

    private val ndcBuffer: FloatBuffer = allocate(NDC_QUAD)
    private val texCoordBuffer: FloatBuffer = allocate(FloatArray(VERTEX_COUNT * COORDS_PER_VERTEX))

    /** Whether [texCoordBuffer] has been filled for the current geometry. */
    private var hasTexCoords = false

    val isReady: Boolean get() = program != 0

    /**
     * Compiles the program. Must run on the thread holding the GL context.
     *
     * Returns false rather than throwing: a driver that will not compile this
     * is a black preview, and the session behind it still tracks and still
     * hit-tests, so the screen degrades to "no picture" rather than to "the
     * scanner is broken".
     */
    fun prepare(): Boolean {
        val vertex = compile(GLES20.GL_VERTEX_SHADER, VERTEX_SHADER)
        val fragment = compile(GLES20.GL_FRAGMENT_SHADER, FRAGMENT_SHADER)
        if (vertex == 0 || fragment == 0) return false

        program = GLES20.glCreateProgram()
        GLES20.glAttachShader(program, vertex)
        GLES20.glAttachShader(program, fragment)
        GLES20.glLinkProgram(program)

        val linked = IntArray(1)
        GLES20.glGetProgramiv(program, GLES20.GL_LINK_STATUS, linked, 0)
        if (linked[0] == 0) {
            Log.e(TAG, "Program link failed: ${GLES20.glGetProgramInfoLog(program)}")
            GLES20.glDeleteProgram(program)
            program = 0
            return false
        }

        // Attached shaders are reference-counted by the program; deleting the
        // handles here frees them when the program goes.
        GLES20.glDeleteShader(vertex)
        GLES20.glDeleteShader(fragment)

        positionAttribute = GLES20.glGetAttribLocation(program, "a_Position")
        texCoordAttribute = GLES20.glGetAttribLocation(program, "a_TexCoord")
        textureUniform = GLES20.glGetUniformLocation(program, "u_Texture")
        return true
    }

    /**
     * Blits [textureId] over the whole of a [width] x [height] viewport.
     *
     * [frame] is asked for the texture coordinates whenever the display
     * geometry has changed — on rotation, on resize, and on the first frame.
     * Recomputing every frame would also be correct and is simply wasted work.
     */
    fun draw(frame: Frame, textureId: Int, width: Int, height: Int) {
        if (program == 0) return

        if (frame.hasDisplayGeometryChanged() || !hasTexCoords) {
            ndcBuffer.position(0)
            texCoordBuffer.position(0)
            frame.transformCoordinates2d(
                Coordinates2d.OPENGL_NORMALIZED_DEVICE_COORDINATES,
                ndcBuffer,
                Coordinates2d.TEXTURE_NORMALIZED,
                texCoordBuffer,
            )
            hasTexCoords = true
        }

        GLES20.glViewport(0, 0, width, height)
        // The quad covers every pixel, so nothing is ever read back — but a
        // driver that skips the clear can leave the previous buffer visible at
        // the edges during a rotation.
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glDisable(GLES20.GL_BLEND)

        GLES20.glUseProgram(program)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, textureId)
        GLES20.glUniform1i(textureUniform, 0)

        ndcBuffer.position(0)
        GLES20.glVertexAttribPointer(
            positionAttribute, COORDS_PER_VERTEX, GLES20.GL_FLOAT, false, 0, ndcBuffer,
        )
        texCoordBuffer.position(0)
        GLES20.glVertexAttribPointer(
            texCoordAttribute, COORDS_PER_VERTEX, GLES20.GL_FLOAT, false, 0, texCoordBuffer,
        )

        GLES20.glEnableVertexAttribArray(positionAttribute)
        GLES20.glEnableVertexAttribArray(texCoordAttribute)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, VERTEX_COUNT)
        GLES20.glDisableVertexAttribArray(positionAttribute)
        GLES20.glDisableVertexAttribArray(texCoordAttribute)
    }

    /**
     * Forces the texture coordinates to be recomputed on the next draw.
     *
     * Called when the EGL surface is replaced. `hasDisplayGeometryChanged` is
     * about ARCore's view of the world and knows nothing about the surface
     * being swapped underneath it, so without this the first frames after a
     * surface loss are drawn with coordinates for a viewport that has gone.
     */
    fun invalidateGeometry() {
        hasTexCoords = false
    }

    fun release() {
        if (program != 0) {
            GLES20.glDeleteProgram(program)
            program = 0
        }
        hasTexCoords = false
    }

    private fun compile(type: Int, source: String): Int {
        val shader = GLES20.glCreateShader(type)
        GLES20.glShaderSource(shader, source)
        GLES20.glCompileShader(shader)

        val compiled = IntArray(1)
        GLES20.glGetShaderiv(shader, GLES20.GL_COMPILE_STATUS, compiled, 0)
        if (compiled[0] == 0) {
            Log.e(TAG, "Shader compile failed: ${GLES20.glGetShaderInfoLog(shader)}")
            GLES20.glDeleteShader(shader)
            return 0
        }
        return shader
    }

    /** Direct and native-ordered, because ARCore writes into it itself. */
    private fun allocate(values: FloatArray): FloatBuffer =
        ByteBuffer.allocateDirect(values.size * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply {
                put(values)
                position(0)
            }
}
