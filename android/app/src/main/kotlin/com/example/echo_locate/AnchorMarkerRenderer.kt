package com.example.echo_locate

import android.opengl.GLES20
import android.opengl.Matrix
import android.util.Log
import com.google.ar.core.Frame
import com.google.ar.core.Pose
import com.google.ar.core.TrackingState
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * World-space points, reused frame to frame.
 *
 * The frame loop runs at camera rate, so anything it allocates it allocates
 * sixty times a second — and a GC pause in this loop is a stutter in the
 * viewfinder somebody is aiming with. [Pose.getTranslation] writes into a
 * caller's array precisely so this can be a buffer that grows once and is then
 * refilled forever. (`Anchor.getPose` still allocates a [Pose] per marker per
 * frame; that is ARCore's API and there is no variant that fills one in place.)
 */
class WorldPoints {

    var values: FloatArray = FloatArray(3 * INITIAL_CAPACITY)
        private set

    /** Number of points held — [values] has three floats each. */
    var count: Int = 0
        private set

    fun clear() {
        count = 0
    }

    fun add(pose: Pose) {
        if ((count + 1) * 3 > values.size) {
            values = values.copyOf(maxOf(values.size * 2, (count + 1) * 3))
        }
        pose.getTranslation(values, count * 3)
        count++
    }

    private companion object {
        const val INITIAL_CAPACITY = 8
    }
}

/**
 * Draws the corners already placed, in place, over the camera.
 *
 * ## Why this is worth a second GL pass
 *
 * Until now the capture screen showed a crosshair and a count: "4 corners
 * placed". That tells you a tap was accepted and nothing at all about **where
 * it landed** — and where it landed is the one thing the whole feature turns
 * on. A hit-test that is a metre out produces the same crosshair, the same
 * count, the same encouraging hint, and a floor plan that is quietly the wrong
 * shape. Drawing each anchor where ARCore believes it is makes that visible
 * immediately: the marker either sits on the corner you tapped or it does not.
 *
 * It is also what turns the plan preview from a check you perform afterwards
 * into feedback you get while walking, which matters most in the case the
 * feature exists for — a contributor mapping an unfamiliar building, who has no
 * second chance at the walk.
 *
 * ## Why native GL rather than a Flutter overlay
 *
 * The obvious alternative is to project the anchors here, ship screen positions
 * over the event channel, and paint them in Flutter with the design tokens. It
 * would look better and it would be wrong in a specific way: those positions
 * describe the camera frame they were computed from, and Flutter would paint
 * them over whichever camera frame the compositor has by then. While the phone
 * is moving — which is all of the time, since the user is walking around a
 * room — the markers would lag the image and **swim off the corners they are
 * marking**, which is exactly the error they exist to reveal. Drawing them into
 * the same buffer as the camera image, from the same frame's matrices, locks
 * them to it by construction.
 *
 * That also keeps the event channel carrying state changes a few times a minute
 * instead of geometry sixty times a second — the property that made the current
 * preview fast (see [CameraBackgroundRenderer]).
 *
 * ## What is drawn
 *
 * The draft polygon as coral discs joined by coral edges, with the closing edge
 * faint until the room is closed, and the first corner larger because it is the
 * point the polygon closes onto. Doors are white discs with a coral ring — a
 * different mark, because a door is an independent point rather than part of
 * the outline, and because seeing which doorways are already tagged is what
 * stops the same one being tapped twice.
 *
 * Occlusion is not attempted: a marker on the far side of a wall still draws.
 * Depth-testing against the ARCore depth image would fix that and would also
 * hide markers behind furniture ARCore mis-measures, which for a scanning aid
 * is the worse failure — a corner you cannot see reads as a corner that was not
 * recorded.
 */
class AnchorMarkerRenderer {

    companion object {
        private const val TAG = "AnchorMarkers"

        /**
         * Clip planes for the projection matrix.
         *
         * Near is tight because markers are routinely a step away — a
         * contributor tapping the corner they are standing in — and anything
         * nearer than this plane is culled.
         */
        private const val Z_NEAR = 0.05f
        private const val Z_FAR = 100f

        /**
         * Marker diameter as a fraction of the shorter viewport edge.
         *
         * A fraction rather than a pixel count: this draws in device pixels,
         * and the same 30 px is a fingertip on a 720p phone and a speck on a
         * 1440p one. The clamps keep it sane at both extremes.
         */
        private const val MARKER_FRACTION = 0.036f
        private const val MARKER_MIN_PX = 16f
        private const val MARKER_MAX_PX = 64f

        /** The first corner is drawn larger: it is what the polygon closes onto. */
        private const val FIRST_CORNER_SCALE = 1.4f

        /** Edge thickness relative to a marker's diameter. */
        private const val EDGE_WIDTH_RATIO = 0.22f

        /** Design tokens, as GL wants them. Coral is the app's single accent. */
        private val CORAL = floatArrayOf(0.984f, 0.357f, 0.278f, 1f)
        private val WHITE = floatArrayOf(1f, 1f, 1f, 1f)

        /** The edge back to the first corner, before the room is closed. */
        private val CORAL_FAINT = floatArrayOf(0.984f, 0.357f, 0.278f, 0.35f)

        private val VERTEX_SHADER = """
            attribute vec2 a_Ndc;
            uniform float u_PointSize;
            void main() {
              gl_Position = vec4(a_Ndc, 0.0, 1.0);
              gl_PointSize = u_PointSize;
            }
        """.trimIndent()

        // One program draws both marks. The branch is on a uniform, so it is
        // uniform across the draw call and costs nothing worth a second program
        // and a second set of attribute bindings.
        private val FRAGMENT_SHADER = """
            precision mediump float;
            uniform vec4 u_Fill;
            uniform vec4 u_Ring;
            uniform float u_Sprite;
            void main() {
              if (u_Sprite < 0.5) {
                gl_FragColor = u_Fill;
                return;
              }
              // Radial coordinate: 0 at the centre of the point, 1 at its edge.
              float r = length(gl_PointCoord - vec2(0.5)) * 2.0;
              if (r > 1.0) discard;
              vec4 colour = r > 0.66 ? u_Ring : u_Fill;
              // Feathered rather than stepped, or a 20 px disc reads as a
              // jagged blob against a moving camera image.
              gl_FragColor = vec4(colour.rgb, colour.a * (1.0 - smoothstep(0.82, 1.0, r)));
            }
        """.trimIndent()

        /** Two floats per vertex, and six vertices make one edge quad. */
        private const val FLOATS_PER_VERTEX = 2
        private const val VERTICES_PER_EDGE = 6
    }

    private var program = 0
    private var ndcAttribute = 0
    private var pointSizeUniform = 0
    private var fillUniform = 0
    private var ringUniform = 0
    private var spriteUniform = 0

    /** The largest point this driver will rasterise, from GL. */
    private var maxPointSize = MARKER_MAX_PX

    private val view = FloatArray(16)
    private val projection = FloatArray(16)
    private val viewProjection = FloatArray(16)
    private val world = floatArrayOf(0f, 0f, 0f, 1f)
    private val clip = FloatArray(4)

    private var cornerNdc = FloatArray(0)
    private var cornerVisible = BooleanArray(0)
    private var doorNdc = FloatArray(0)
    private var doorVisible = BooleanArray(0)

    private var vertexData = FloatArray(0)
    private var vertexBuffer: FloatBuffer? = null

    val isReady: Boolean get() = program != 0

    /**
     * Compiles the program. Must run on the thread holding the GL context.
     *
     * Returns false rather than throwing, for the same reason
     * [CameraBackgroundRenderer.prepare] does: markers are an aid to aiming,
     * and a driver that will not compile them leaves a screen that still
     * tracks, still hit-tests and still produces a correct plan.
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

        GLES20.glDeleteShader(vertex)
        GLES20.glDeleteShader(fragment)

        ndcAttribute = GLES20.glGetAttribLocation(program, "a_Ndc")
        pointSizeUniform = GLES20.glGetUniformLocation(program, "u_PointSize")
        fillUniform = GLES20.glGetUniformLocation(program, "u_Fill")
        ringUniform = GLES20.glGetUniformLocation(program, "u_Ring")
        spriteUniform = GLES20.glGetUniformLocation(program, "u_Sprite")

        // GLES2 guarantees only that a driver supports a point size of 1, and
        // asking for more than it allows is silently clamped on some drivers
        // and an error on others. Reading the range makes it neither.
        val range = FloatArray(2)
        GLES20.glGetFloatv(GLES20.GL_ALIASED_POINT_SIZE_RANGE, range, 0)
        if (range[1] > 1f) maxPointSize = range[1]

        return true
    }

    /**
     * Draws [corners] as an outline and [doors] as separate marks, over
     * whatever is already in the [width] x [height] viewport.
     *
     * Points arrive as world positions rather than as anchors so this class
     * stays a renderer: which anchors are worth drawing, and whether ARCore
     * still tracks them, is [RoomCaptureHandler]'s question.
     *
     * The matrices come from [frame], not from the last frame or from a cached
     * pose, which is what keeps the markers registered to the camera image
     * being drawn underneath them.
     */
    fun draw(
        frame: Frame,
        corners: WorldPoints,
        doors: WorldPoints,
        width: Int,
        height: Int,
    ) {
        if (program == 0 || width <= 0 || height <= 0) return
        if (corners.count == 0 && doors.count == 0) return
        // A camera that is not tracking has no meaningful pose, so its matrices
        // would scatter the markers across the view rather than leave them
        // where they were. Nothing is drawn until it relocalises.
        if (frame.camera.trackingState != TrackingState.TRACKING) return

        frame.camera.getViewMatrix(view, 0)
        frame.camera.getProjectionMatrix(projection, 0, Z_NEAR, Z_FAR)
        Matrix.multiplyMM(viewProjection, 0, projection, 0, view, 0)

        cornerNdc = ensureFloats(cornerNdc, corners.count * 2)
        cornerVisible = ensureFlags(cornerVisible, corners.count)
        doorNdc = ensureFloats(doorNdc, doors.count * 2)
        doorVisible = ensureFlags(doorVisible, doors.count)
        project(corners, cornerNdc, cornerVisible)
        project(doors, doorNdc, doorVisible)

        val markerPx = (MARKER_FRACTION * minOf(width, height))
            .coerceIn(MARKER_MIN_PX, minOf(MARKER_MAX_PX, maxPointSize))
        val edgePx = markerPx * EDGE_WIDTH_RATIO

        GLES20.glUseProgram(program)
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glEnableVertexAttribArray(ndcAttribute)

        drawEdges(corners.count, edgePx, width, height)

        // Markers after edges, so an edge never draws across the disc it ends
        // at — with the closing edge faint, that would read as a scratch.
        drawMarkers(cornerNdc, cornerVisible, corners.count, markerPx, CORAL, WHITE, skipFirst = true)
        if (corners.count > 0 && cornerVisible[0]) {
            drawPoint(cornerNdc[0], cornerNdc[1], markerPx * FIRST_CORNER_SCALE, CORAL, WHITE)
        }
        // Inverted colours rather than a different shape: a door is not part of
        // the outline, and at fingertip size a square and a circle are the same
        // blob while two colours are not.
        drawMarkers(doorNdc, doorVisible, doors.count, markerPx, WHITE, CORAL, skipFirst = false)

        GLES20.glDisableVertexAttribArray(ndcAttribute)
        // Left as the camera pass expects to find it: that pass disables
        // blending itself, but leaving global state changed from a helper is
        // how the next renderer added here inherits a bug nobody can find.
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    fun release() {
        if (program != 0) {
            GLES20.glDeleteProgram(program)
            program = 0
        }
    }

    /**
     * World positions to normalised device coordinates, marking the ones that
     * cannot be drawn.
     *
     * The check that matters is `w > 0`: a point **behind the camera** still
     * divides through to a perfectly plausible pair of coordinates, mirrored
     * into the view. Without this a corner behind the contributor's shoulder
     * draws in front of them, on top of the room they are looking at.
     */
    private fun project(points: WorldPoints, ndcOut: FloatArray, visibleOut: BooleanArray) {
        for (i in 0 until points.count) {
            world[0] = points.values[i * 3]
            world[1] = points.values[i * 3 + 1]
            world[2] = points.values[i * 3 + 2]
            world[3] = 1f

            Matrix.multiplyMV(clip, 0, viewProjection, 0, world, 0)
            val w = clip[3]
            if (w <= 0.0001f) {
                visibleOut[i] = false
                continue
            }
            ndcOut[i * 2] = clip[0] / w
            ndcOut[i * 2 + 1] = clip[1] / w
            // Off-screen points are still drawn: the edge leading to one is
            // what tells the user which way to turn to find it.
            visibleOut[i] = true
        }
    }

    /**
     * The walls placed so far, plus a faint one back to the start.
     *
     * Lines are built as triangles rather than drawn with `GL_LINES`, because
     * GLES2 requires a driver to support a line width of exactly 1 and many
     * honour nothing else. A one-pixel outline over a moving camera image on a
     * high-density screen is very close to invisible.
     */
    private fun drawEdges(cornerCount: Int, widthPx: Float, viewWidth: Int, viewHeight: Int) {
        if (cornerCount < 2) return

        val halfWidth = widthPx / 2f
        var vertices = 0
        ensureVertexCapacity((cornerCount - 1) * VERTICES_PER_EDGE * FLOATS_PER_VERTEX)

        for (i in 0 until cornerCount - 1) {
            if (!cornerVisible[i] || !cornerVisible[i + 1]) continue
            vertices += appendEdge(
                cornerNdc[i * 2], cornerNdc[i * 2 + 1],
                cornerNdc[(i + 1) * 2], cornerNdc[(i + 1) * 2 + 1],
                halfWidth, viewWidth, viewHeight, vertices,
            )
        }
        if (vertices > 0) {
            setColour(CORAL, CORAL, sprite = false)
            submit(vertices)
        }

        // The closing wall is drawn faint from three corners on, because that
        // is the moment the shape becomes a room you could close — and showing
        // it solid would make a half-traced L look like a finished triangle.
        if (cornerCount < 3) return
        val last = cornerCount - 1
        if (!cornerVisible[last] || !cornerVisible[0]) return

        ensureVertexCapacity(VERTICES_PER_EDGE * FLOATS_PER_VERTEX)
        val closing = appendEdge(
            cornerNdc[last * 2], cornerNdc[last * 2 + 1],
            cornerNdc[0], cornerNdc[1],
            halfWidth, viewWidth, viewHeight, 0,
        )
        if (closing > 0) {
            setColour(CORAL_FAINT, CORAL_FAINT, sprite = false)
            submit(closing)
        }
    }

    /**
     * One edge as two triangles, written into [vertexData] at [atVertex].
     *
     * The perpendicular is taken in **pixels, not in NDC**. In NDC a step of
     * 0.01 is a different number of pixels horizontally than vertically on any
     * viewport that is not square, so a naive offset gives a line whose
     * thickness changes with its angle.
     */
    private fun appendEdge(
        x0: Float, y0: Float,
        x1: Float, y1: Float,
        halfWidthPx: Float,
        viewWidth: Int, viewHeight: Int,
        atVertex: Int,
    ): Int {
        val halfW = viewWidth / 2f
        val halfH = viewHeight / 2f
        val px0 = x0 * halfW
        val py0 = y0 * halfH
        val px1 = x1 * halfW
        val py1 = y1 * halfH

        val dx = px1 - px0
        val dy = py1 - py0
        val length = kotlin.math.sqrt(dx * dx + dy * dy)
        if (length < 0.5f) return 0

        val nx = -dy / length * halfWidthPx
        val ny = dx / length * halfWidthPx

        var at = atVertex * FLOATS_PER_VERTEX
        fun put(px: Float, py: Float) {
            vertexData[at++] = px / halfW
            vertexData[at++] = py / halfH
        }

        put(px0 + nx, py0 + ny)
        put(px0 - nx, py0 - ny)
        put(px1 + nx, py1 + ny)
        put(px0 - nx, py0 - ny)
        put(px1 - nx, py1 - ny)
        put(px1 + nx, py1 + ny)
        return VERTICES_PER_EDGE
    }

    private fun drawMarkers(
        ndc: FloatArray,
        visible: BooleanArray,
        count: Int,
        sizePx: Float,
        fill: FloatArray,
        ring: FloatArray,
        skipFirst: Boolean,
    ) {
        val from = if (skipFirst) 1 else 0
        if (count <= from) return

        ensureVertexCapacity(count * FLOATS_PER_VERTEX)
        var vertices = 0
        for (i in from until count) {
            if (!visible[i]) continue
            vertexData[vertices * FLOATS_PER_VERTEX] = ndc[i * 2]
            vertexData[vertices * FLOATS_PER_VERTEX + 1] = ndc[i * 2 + 1]
            vertices++
        }
        if (vertices == 0) return

        setColour(fill, ring, sprite = true)
        GLES20.glUniform1f(pointSizeUniform, sizePx)
        submit(vertices, GLES20.GL_POINTS)
    }

    private fun drawPoint(
        x: Float,
        y: Float,
        sizePx: Float,
        fill: FloatArray,
        ring: FloatArray,
    ) {
        ensureVertexCapacity(FLOATS_PER_VERTEX)
        vertexData[0] = x
        vertexData[1] = y
        setColour(fill, ring, sprite = true)
        GLES20.glUniform1f(pointSizeUniform, sizePx.coerceAtMost(maxPointSize))
        submit(1, GLES20.GL_POINTS)
    }

    private fun setColour(fill: FloatArray, ring: FloatArray, sprite: Boolean) {
        GLES20.glUniform4fv(fillUniform, 1, fill, 0)
        GLES20.glUniform4fv(ringUniform, 1, ring, 0)
        GLES20.glUniform1f(spriteUniform, if (sprite) 1f else 0f)
    }

    private fun submit(vertexCount: Int, mode: Int = GLES20.GL_TRIANGLES) {
        val buffer = vertexBuffer ?: return
        buffer.position(0)
        buffer.put(vertexData, 0, vertexCount * FLOATS_PER_VERTEX)
        buffer.position(0)
        GLES20.glVertexAttribPointer(
            ndcAttribute, FLOATS_PER_VERTEX, GLES20.GL_FLOAT, false, 0, buffer,
        )
        GLES20.glDrawArrays(mode, 0, vertexCount)
    }

    private fun ensureFloats(array: FloatArray, floats: Int): FloatArray =
        if (array.size >= floats) array else FloatArray(maxOf(floats, 32))

    /**
     * Grows the vertex array **and the direct buffer it is copied into**.
     *
     * They grow together deliberately: a vertex array larger than its buffer
     * overflows at the exact moment somebody traces an unusually complicated
     * room, which is the least reproducible bug this file could have.
     */
    private fun ensureVertexCapacity(floats: Int) {
        if (vertexData.size >= floats && vertexBuffer != null) return
        val size = maxOf(floats, 32, vertexData.size)
        vertexData = FloatArray(size)
        vertexBuffer = ByteBuffer.allocateDirect(size * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
    }

    private fun ensureFlags(array: BooleanArray, count: Int): BooleanArray =
        if (array.size >= count) array else BooleanArray(maxOf(count, 16))

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
}
