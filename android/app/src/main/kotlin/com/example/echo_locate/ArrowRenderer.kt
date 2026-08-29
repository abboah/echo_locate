package com.example.echo_locate

import android.opengl.GLES20
import android.opengl.Matrix
import android.util.Log
import com.google.ar.core.Camera
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * The arrow — the "which way do I go" layer of AR guidance.
 *
 * ## What it draws
 *
 * **One arrow, held in front of the camera**, and a ring on the floor at the
 * next checkpoint. The arrow sits at a fixed distance ahead of the phone, a
 * little below the middle of the screen, and rotates in the plane of the screen
 * to point where the walker is being sent: straight up when that is dead ahead,
 * right when it is off to the right, down when it is behind them. It is a
 * compass needle held up in the corridor, not a decal on the floor.
 *
 * The arrow is a solid — a folded plate with a ridge down its centre — lit from
 * a fixed direction in the viewer's frame. The lighting is what makes it read
 * as an object rather than a sticker, and because the light is fixed while the
 * arrow turns, the facets change brightness as it swings, which is most of the
 * cue that it is pointing *somewhere* rather than just spinning.
 *
 * ## Why it is camera-locked, when the arrows used to be world-locked
 *
 * This replaced a chain of up to eight arrows laid along the leg in world
 * coordinates. Those were more literally *there* — genuinely lying on the floor
 * of the corridor — but they had two costs that a single needle does not:
 *
 * - **They could all be off screen at once.** Turn thirty degrees too far and
 *   the corridor is empty, which is indistinguishable from guidance having
 *   died.
 * - **They rested on a guessed floor.** The floor was assumed to be
 *   [ArGuidanceHandler.EYE_HEIGHT_M] below the phone, so anyone holding it at
 *   chest height walked past arrows sunk into the terrazzo. It is measured now
 *   — `ArGuidanceHandler.serviceFloorSearch` — and that assumption is only the
 *   fallback, but the ring is still the one thing on screen that depends on
 *   getting it right.
 *
 * The needle is always on screen, always the same size, and owes nothing to
 * where the floor is. What it costs is the sense of the route being pinned to
 * the room — which the ring still carries, because that *is* world-locked and
 * does mark a real place.
 *
 * ## The bearing is the only thing that moves
 *
 * The angle comes from [ArGuidanceHandler], measured off the same leg anchor
 * that was frozen when the leg began and the same camera pose the frame was
 * rendered from — so the needle agrees with the distance and the spoken cue to
 * within a frame. Nothing here integrates or smooths anything: if the needle
 * looks wrong, the anchor is wrong, and that is worth seeing rather than
 * hiding.
 *
 * ## No depth buffer, so order is the depth test
 *
 * The EGL config has no depth attachment (see [ArGlSurface]). Everything is
 * submitted far to near — ring, then the arrow's silhouette, then the arrow
 * itself — so the nearer thing simply overlaps. **The arrow's own facets are
 * the exception that has to be designed around**: they never overlap each
 * other, because every one of them faces the viewer. Nothing here is ever seen
 * from behind, which is also why the solid has no back.
 */
class ArrowRenderer {

    companion object {
        private const val TAG = "ArrowRenderer"

        private const val Z_NEAR = 0.05f
        private const val Z_FAR = 100f

        /**
         * How far in front of the camera the arrow floats, in metres.
         *
         * Far enough that it does not read as something stuck to the glass,
         * near enough that it stays big under any lens. Arm's length, roughly.
         */
        private const val HUD_DISTANCE_M = 1.5f

        /**
         * How far below the middle of the screen the arrow sits, in metres at
         * [HUD_DISTANCE_M].
         *
         * Below centre because the instruction lives across the top, and
         * because a walker's eyes are already down the corridor — the needle
         * belongs under that, nearer the floor it refers to.
         */
        private const val HUD_DROP_M = 0.46f

        /**
         * How far the top of the arrow leans away from the viewer, in degrees.
         *
         * Enough to see the top of the solid rather than its outline, which is
         * half of what sells it as an object. Applied about the *screen's*
         * horizontal axis rather than the arrow's own, so the silhouette is
         * equally legible whichever way the needle points — leaning it about
         * its own long axis would foreshorten it when it points up the screen
         * and not when it points sideways.
         */
        private const val LEAN_DEG = 30f

        /**
         * Overall size multiplier on the metre-scale geometry below.
         *
         * Deliberately modest. The arrow is one glance's worth of information
         * in a view whose real content is the corridor behind it, and the
         * earlier draft — half again this size — covered the doorway it was
         * pointing at.
         */
        private const val ARROW_SCALE = 0.62f

        /** How much larger the white silhouette behind the arrow is. */
        private const val OUTLINE_SCALE = 1.14f

        /** Design tokens. Coral is the app's single accent. */
        private val CORAL = floatArrayOf(0.984f, 0.357f, 0.278f)
        private val WHITE = floatArrayOf(1f, 1f, 1f)

        /** How far the centre ridge stands proud of the arrow's edges. */
        private const val RIDGE_M = 0.075f

        // The outline, in the plane of the screen, pointing up (+y), in metres
        // before [ARROW_SCALE]. Blunt on purpose: this is an accessibility aid
        // before it is a game, and a delicate glyph is the wrong answer for a
        // low-vision user in a dim corridor.
        private const val TIP_Y = 0.34f
        private const val BARB_Y = 0.04f
        private const val TAIL_Y = -0.26f
        private const val BARB_X = 0.26f
        private const val SHAFT_X = 0.10f

        /** Segments in the checkpoint ring. */
        private const val RING_SEGMENTS = 28
        private const val RING_INNER_M = 0.34f
        private const val RING_OUTER_M = 0.46f

        private val VERTEX_SHADER = """
            attribute vec3 a_Position;
            attribute vec3 a_Normal;
            uniform mat4 u_Mvp;
            uniform mat4 u_Model;
            uniform float u_Lit;
            varying float v_Shade;
            void main() {
              // The light is fixed in the *viewer's* frame, not the world's, so
              // the arrow lights like a solid held in the hand: turning it
              // moves its facets through the light instead of carrying the
              // light around with them.
              vec3 normal = normalize((u_Model * vec4(a_Normal, 0.0)).xyz);
              float lambert = max(dot(normal, normalize(vec3(-0.35, 0.55, 0.75))), 0.0);
              v_Shade = mix(1.0, 0.45 + 0.55 * lambert, u_Lit);
              gl_Position = u_Mvp * vec4(a_Position, 1.0);
            }
        """.trimIndent()

        private val FRAGMENT_SHADER = """
            precision mediump float;
            uniform vec4 u_Colour;
            varying float v_Shade;
            void main() {
              gl_FragColor = vec4(u_Colour.rgb * v_Shade, u_Colour.a);
            }
        """.trimIndent()
    }

    private var program = 0
    private var positionAttribute = 0
    private var normalAttribute = 0
    private var mvpUniform = 0
    private var modelUniform = 0
    private var litUniform = 0
    private var colourUniform = 0

    private val view = FloatArray(16)
    private val projection = FloatArray(16)
    private val viewProjection = FloatArray(16)
    private val model = FloatArray(16)
    private val mvp = FloatArray(16)

    private val arrowMesh = buildArrow()
    private val arrowPositions: FloatBuffer = allocate(arrowMesh.positions)
    private val arrowNormals: FloatBuffer = allocate(arrowMesh.normals)
    private val arrowVertices = arrowMesh.positions.size / 3

    private val ringData = FloatArray(RING_SEGMENTS * 6 * 3)
    private val ringPositions: FloatBuffer
    private val ringNormals: FloatBuffer

    init {
        buildRing()
        ringPositions = allocate(ringData)
        // Unused — the ring is drawn unlit — but the attribute still has to be
        // fed something, and a buffer shorter than the draw call reads off the
        // end of it on some drivers.
        ringNormals = allocate(FloatArray(ringData.size) { if (it % 3 == 1) 1f else 0f })
    }

    val isReady: Boolean get() = program != 0

    /**
     * Compiles the program. Must run on the thread holding the GL context.
     *
     * Returns false rather than throwing: without the arrow the screen is still
     * a working guidance session — the instruction, the distance and the spoken
     * directions are all unaffected — so a driver that cannot compile this
     * degrades to "no arrow", not to "no guidance".
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

        positionAttribute = GLES20.glGetAttribLocation(program, "a_Position")
        normalAttribute = GLES20.glGetAttribLocation(program, "a_Normal")
        mvpUniform = GLES20.glGetUniformLocation(program, "u_Mvp")
        modelUniform = GLES20.glGetUniformLocation(program, "u_Model")
        litUniform = GLES20.glGetUniformLocation(program, "u_Lit")
        colourUniform = GLES20.glGetUniformLocation(program, "u_Colour")
        return true
    }

    /**
     * Draws the checkpoint ring, then the arrow.
     *
     * [leg] carries the world geometry — where the leg starts, which way it
     * runs, where the floor is — all fixed when the leg was anchored.
     * [ringAlongM] is how far along it the *next checkpoint* is, which is the
     * only place the ring is ever drawn: the far landmark is not shown until it
     * becomes the checkpoint being walked to. [bearingDeg] is where the walker
     * is being aimed, relative to where the phone is pointing, positive to the
     * right — the only thing the arrow needs.
     */
    fun draw(camera: Camera, leg: LegAnchor, bearingDeg: Float, ringAlongM: Float) =
        drawAt(
            camera = camera,
            ringX = leg.startX + leg.dirX * ringAlongM,
            ringY = leg.floorY,
            ringZ = leg.startZ + leg.dirZ * ringAlongM,
            ringDirX = leg.dirX,
            ringDirZ = leg.dirZ,
            bearingDeg = bearingDeg,
        )

    /**
     * The same, for a ring whose position is known outright.
     *
     * A route registered into the room (see `route_registration.dart`) is a
     * polyline, not a single straight leg, and the place the walker is being
     * sent to is a corner or a doorway on it rather than a distance along one
     * direction. There is nothing for the leg form above to interpolate, so
     * the caller works out the point and this draws it.
     */
    fun drawAt(
        camera: Camera,
        ringX: Float,
        ringY: Float,
        ringZ: Float,
        ringDirX: Float,
        ringDirZ: Float,
        bearingDeg: Float,
    ) {
        if (program == 0) return

        camera.getViewMatrix(view, 0)
        camera.getProjectionMatrix(projection, 0, Z_NEAR, Z_FAR)
        Matrix.multiplyMM(viewProjection, 0, projection, 0, view, 0)

        GLES20.glUseProgram(program)
        GLES20.glDisable(GLES20.GL_DEPTH_TEST)
        GLES20.glEnable(GLES20.GL_BLEND)
        GLES20.glBlendFunc(GLES20.GL_SRC_ALPHA, GLES20.GL_ONE_MINUS_SRC_ALPHA)
        GLES20.glEnableVertexAttribArray(positionAttribute)
        GLES20.glEnableVertexAttribArray(normalAttribute)

        // The ring first: it is the farthest thing, and with no depth buffer
        // the draw order is what puts the arrow over it.
        setWorldModel(ringX, ringY, ringZ, ringDirX, ringDirZ)
        submit(ringPositions, ringNormals, ringData.size / 3, WHITE, 0.9f, lit = false)

        // A flat white silhouette behind the solid, slightly larger, so the
        // needle keeps its edge against a corridor that might be any colour at
        // all — including a coral-coloured door at the end of it. Unlit, so it
        // stays a clean outline rather than a second arrow showing through.
        placeArrow(bearingDeg, ARROW_SCALE * OUTLINE_SCALE)
        submit(arrowPositions, arrowNormals, arrowVertices, WHITE, 0.95f, lit = false)
        placeArrow(bearingDeg, ARROW_SCALE)
        submit(arrowPositions, arrowNormals, arrowVertices, CORAL, 1f, lit = true)

        GLES20.glDisableVertexAttribArray(positionAttribute)
        GLES20.glDisableVertexAttribArray(normalAttribute)
        GLES20.glDisable(GLES20.GL_BLEND)
    }

    fun release() {
        if (program != 0) {
            GLES20.glDeleteProgram(program)
            program = 0
        }
    }

    /**
     * Puts the arrow in front of the camera, turned by [bearingDeg].
     *
     * **There is no view matrix here, deliberately.** The arrow is positioned
     * in the camera's own space, and view space is by definition what the view
     * matrix maps the world into — so the projection alone places it, and no
     * camera pose is involved at all. That is also why the needle cannot swim:
     * there is nothing in this matrix for tracking to get wrong.
     *
     * The order below reads backwards from how it applies to a vertex, because
     * [Matrix.translateM] and friends post-multiply. A vertex is scaled, then
     * turned in the plane of the screen, then leaned away from the viewer, then
     * pushed out in front of the camera.
     */
    private fun placeArrow(bearingDeg: Float, scale: Float) {
        Matrix.setIdentityM(model, 0)
        Matrix.translateM(model, 0, 0f, -HUD_DROP_M, -HUD_DISTANCE_M)
        Matrix.rotateM(model, 0, -LEAN_DEG, 1f, 0f, 0f)
        // Negated: the geometry points up the screen, and a target to the right
        // (positive bearing) has to swing it clockwise — which about +z, the
        // axis pointing out of the screen at the viewer, is negative.
        Matrix.rotateM(model, 0, -bearingDeg, 0f, 0f, 1f)
        Matrix.scaleM(model, 0, scale, scale, scale)
        Matrix.multiplyMM(mvp, 0, projection, 0, model, 0)
    }

    /**
     * Model matrix placing world geometry at (x, y, z) facing (dirX, dirZ).
     *
     * Built by hand rather than with [Matrix.rotateM] because the sign of a yaw
     * rotation is the single easiest thing to get backwards here. Columns are:
     * right, up, **backward**, translation — so the geometry's -z is the
     * direction of travel, matching OpenGL's convention and ARCore's camera.
     */
    private fun setWorldModel(x: Float, y: Float, z: Float, dirX: Float, dirZ: Float) {
        // right = forward x up, for forward = (dirX, 0, dirZ) and up = +y.
        val rightX = -dirZ
        val rightZ = dirX

        model[0] = rightX; model[1] = 0f; model[2] = rightZ; model[3] = 0f
        model[4] = 0f; model[5] = 1f; model[6] = 0f; model[7] = 0f
        model[8] = -dirX; model[9] = 0f; model[10] = -dirZ; model[11] = 0f
        model[12] = x; model[13] = y; model[14] = z; model[15] = 1f

        Matrix.multiplyMM(mvp, 0, viewProjection, 0, model, 0)
    }

    private fun submit(
        positions: FloatBuffer,
        normals: FloatBuffer,
        vertexCount: Int,
        colour: FloatArray,
        alpha: Float,
        lit: Boolean,
    ) {
        positions.position(0)
        normals.position(0)
        GLES20.glVertexAttribPointer(
            positionAttribute, 3, GLES20.GL_FLOAT, false, 0, positions,
        )
        GLES20.glVertexAttribPointer(
            normalAttribute, 3, GLES20.GL_FLOAT, false, 0, normals,
        )
        GLES20.glUniformMatrix4fv(mvpUniform, 1, false, mvp, 0)
        GLES20.glUniformMatrix4fv(modelUniform, 1, false, model, 0)
        GLES20.glUniform1f(litUniform, if (lit) 1f else 0f)
        GLES20.glUniform4f(colourUniform, colour[0], colour[1], colour[2], alpha)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLES, 0, vertexCount)
    }

    private class Mesh(val positions: FloatArray, val normals: FloatArray)

    /**
     * The arrow as a solid: a flat outline folded up along its centre line.
     *
     * Half of it is written out and the other half mirrored, rather than both
     * being listed — a hand-typed mirror image is where an asymmetric arrow
     * comes from, and an arrow that is subtly heavier on one side reads as
     * pointing slightly off the direction it is actually pointing.
     */
    private fun buildArrow(): Mesh {
        val tip = floatArrayOf(0f, TIP_Y, RIDGE_M)
        val midCentre = floatArrayOf(0f, BARB_Y, RIDGE_M)
        val tailCentre = floatArrayOf(0f, TAIL_Y, RIDGE_M)
        val barb = floatArrayOf(-BARB_X, BARB_Y, 0f)
        val shoulder = floatArrayOf(-SHAFT_X, BARB_Y, 0f)
        val tail = floatArrayOf(-SHAFT_X, TAIL_Y, 0f)

        // The left half, wound anticlockwise seen from the front.
        val left = listOf(
            arrayOf(tip, barb, midCentre),
            arrayOf(midCentre, barb, shoulder),
            arrayOf(midCentre, shoulder, tail),
            arrayOf(midCentre, tail, tailCentre),
        )

        val positions = ArrayList<Float>(left.size * 2 * 9)
        val normals = ArrayList<Float>(left.size * 2 * 9)

        fun emit(triangle: Array<FloatArray>) {
            val normal = faceNormal(triangle[0], triangle[1], triangle[2])
            for (vertex in triangle) {
                positions.add(vertex[0]); positions.add(vertex[1]); positions.add(vertex[2])
                normals.add(normal[0]); normals.add(normal[1]); normals.add(normal[2])
            }
        }

        for (triangle in left) emit(triangle)
        // Mirrored in x, with the last two vertices swapped so the winding —
        // and therefore the normal — comes out facing the viewer rather than
        // into the screen.
        for (triangle in left) {
            emit(
                arrayOf(
                    mirror(triangle[0]),
                    mirror(triangle[2]),
                    mirror(triangle[1]),
                ),
            )
        }

        return Mesh(positions.toFloatArray(), normals.toFloatArray())
    }

    private fun mirror(vertex: FloatArray) =
        floatArrayOf(-vertex[0], vertex[1], vertex[2])

    private fun faceNormal(
        a: FloatArray,
        b: FloatArray,
        c: FloatArray,
    ): FloatArray {
        val abX = b[0] - a[0]; val abY = b[1] - a[1]; val abZ = b[2] - a[2]
        val acX = c[0] - a[0]; val acY = c[1] - a[1]; val acZ = c[2] - a[2]
        var nX = abY * acZ - abZ * acY
        var nY = abZ * acX - abX * acZ
        var nZ = abX * acY - abY * acX
        val length = kotlin.math.sqrt(nX * nX + nY * nY + nZ * nZ)
        if (length > 1e-6f) {
            nX /= length; nY /= length; nZ /= length
        } else {
            // A degenerate triangle would light as pure black. Face it at the
            // viewer instead, which is invisible rather than wrong.
            nX = 0f; nY = 0f; nZ = 1f
        }
        return floatArrayOf(nX, nY, nZ)
    }

    private fun buildRing() {
        var at = 0
        for (segment in 0 until RING_SEGMENTS) {
            val a0 = (segment.toFloat() / RING_SEGMENTS) * 2f * Math.PI.toFloat()
            val a1 = ((segment + 1).toFloat() / RING_SEGMENTS) * 2f * Math.PI.toFloat()
            val cos0 = kotlin.math.cos(a0)
            val sin0 = kotlin.math.sin(a0)
            val cos1 = kotlin.math.cos(a1)
            val sin1 = kotlin.math.sin(a1)

            fun put(radius: Float, cos: Float, sin: Float) {
                ringData[at++] = cos * radius
                ringData[at++] = 0f
                ringData[at++] = sin * radius
            }

            put(RING_INNER_M, cos0, sin0)
            put(RING_OUTER_M, cos0, sin0)
            put(RING_OUTER_M, cos1, sin1)
            put(RING_INNER_M, cos0, sin0)
            put(RING_OUTER_M, cos1, sin1)
            put(RING_INNER_M, cos1, sin1)
        }
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

    private fun allocate(values: FloatArray): FloatBuffer =
        ByteBuffer.allocateDirect(values.size * Float.SIZE_BYTES)
            .order(ByteOrder.nativeOrder())
            .asFloatBuffer()
            .apply {
                put(values)
                position(0)
            }
}

/**
 * One leg of a route, frozen into ARCore world coordinates.
 *
 * **The whole design rests on this being computed once.** The direction is
 * taken from how the walker was actually moving when the leg began, turned by
 * the angle the route asks for; from then on it is a fixed line in the world
 * that ARCore keeps registered to the room. Recomputing it from a live heading
 * every frame would make the guidance chase the phone, which is precisely the
 * failure mode that makes AR navigation feel untrustworthy.
 *
 * The checkpoints the walker is actually sent to are positions *along* this
 * line — see [ArGuidanceHandler.CHECKPOINT_M] — not separate anchors. One
 * anchor per leg is what keeps them all consistent with each other.
 *
 * [cameraX] and [cameraZ] are refreshed each frame — they are how far along the
 * leg the walker has come, and nothing else here moves.
 */
data class LegAnchor(
    /**
     * Where the leg starts and which way it runs.
     *
     * Mutable, and only one thing may write them: `ArGuidanceHandler`'s
     * per-frame anchor follow, which re-reads them off the ARCore anchor the
     * leg is pinned to so that a relocalisation moves the line with the
     * building. Nothing else may — a leg that is re-aimed mid-corridor is the
     * failure this whole class exists to avoid.
     */
    var startX: Float,
    var startZ: Float,
    var dirX: Float,
    var dirZ: Float,
    val lengthM: Float,
    /** Replaced when the floor is measured rather than assumed. */
    var floorY: Float,
    var cameraX: Float = 0f,
    var cameraZ: Float = 0f,
)
