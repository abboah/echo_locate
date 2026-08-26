package com.example.echo_locate

import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sqrt

/**
 * A whole route laid into ARCore's world, and where the walker is on it.
 *
 * ## What this replaces
 *
 * [LegAnchor] is one straight line, anchored from the direction the walker
 * happened to be moving and turned by an angle Dart supplied. It works without
 * knowing where anybody is, which is why it was built that way — but it also
 * *cannot* know, so it can only ever say "keep going the way you set off, for
 * so many metres". Every leg is measured from the last, so the first one's
 * error rides through the whole walk and nothing can correct it.
 *
 * This is the other half of the answer. Dart solves one rotation and one
 * translation between the floor plan and ARCore's world (see
 * `route_registration.dart`), transforms the whole path, and hands it over as
 * world coordinates. From then on there is no dead reckoning: the walker's
 * position is a projection onto a known line, the next corner is a known
 * point, and the arrow aims at the place rather than down a bearing.
 *
 * ## Progress only ever goes forward
 *
 * [update] takes the maximum of the projection and what has already been
 * reached, so drift, a sidestep round somebody, or a relocalisation that moves
 * the world cannot rewind the walk. Dart's guidance clock refuses to run
 * backwards for the same reason — a cue that has been spoken and acted on must
 * not be spoken again — and the two agree because the number comes from here.
 *
 * ## Where the walker actually is, versus where the line is
 *
 * [offsetM] is how far off the line they are standing. It is the one honest
 * measure of whether the registration is any good: a walker following a
 * corridor the app has registered correctly stays within a metre or so of it,
 * and one whose registration came out rotated walks steadily further away. The
 * screen uses it to stop trusting a bad registration rather than confidently
 * steering somebody into a wall.
 */
class RegisteredRoute(
    private val xs: FloatArray,
    private val zs: FloatArray,
    val floorY: Float,
) {
    companion object {
        /**
         * How far back along the route a projection may land before it is
         * refused.
         *
         * A route that doubles back — out of a room, along a corridor, and
         * back past the door on the other side — puts two very different
         * places within a couple of metres of each other. Projecting onto the
         * whole line and taking the nearest segment would teleport the walker
         * between them. Searching only near where they already are is what
         * keeps a U-shaped route from collapsing.
         */
        private const val BACKTRACK_M = 4f

        /** And how far ahead, for the same reason. */
        private const val LOOKAHEAD_M = 12f

        /**
         * How far ahead the ring must be to be worth marking, in metres.
         *
         * A ring closer than this is under the walker's feet by the time they
         * look up from it, and a mark you have already reached tells you
         * nothing about where to go next. A stride and a half — the same
         * figure `ArGuidanceHandler.NEAR_TARGET_M` uses to stop the arrow
         * spinning as it arrives at a point, and for the same reason.
         */
        private const val MIN_MARK_AHEAD_M = 1.5f
    }

    /** Cumulative distance from the start at each vertex. */
    private val cum = FloatArray(xs.size)

    val totalM: Float

    init {
        require(xs.size == zs.size && xs.size >= 2) { "a route needs two points" }
        var running = 0f
        for (i in 1 until xs.size) {
            running += hypot(xs[i] - xs[i - 1], zs[i] - zs[i - 1])
            cum[i] = running
        }
        totalM = running
    }

    /** How far along the route the walker has come. Never decreases. */
    var alongM = 0f
        private set

    /** How far off the line they are standing. */
    var offsetM = 0f
        private set

    /** Which segment they are on, as an index into the vertex list. */
    var segment = 0
        private set

    val remainingM: Float get() = (totalM - alongM).coerceAtLeast(0f)

    /** Whether the walker is past the end of the route. */
    val arrived: Boolean get() = alongM >= totalM - 0.01f

    /**
     * Projects a world position onto the route.
     *
     * Returns true when the position was matched to the line at all. A walker
     * who has left the building the route is drawn in still projects — every
     * point projects onto some segment — so the answer to "are they on the
     * route" is [offsetM], not this.
     */
    fun update(camX: Float, camZ: Float): Boolean {
        if (xs.size < 2) return false

        var bestAlong = alongM
        var bestOffset = Float.MAX_VALUE
        var bestSegment = segment
        var found = false

        for (i in 0 until xs.size - 1) {
            // Only segments near where they already are — see BACKTRACK_M.
            if (cum[i + 1] < alongM - BACKTRACK_M) continue
            if (cum[i] > alongM + LOOKAHEAD_M) break

            val ax = xs[i]
            val az = zs[i]
            val bx = xs[i + 1]
            val bz = zs[i + 1]
            val dx = bx - ax
            val dz = bz - az
            val lengthSq = dx * dx + dz * dz
            if (lengthSq < 1e-6f) continue

            // Clamped, so a position beyond either end of a segment lands on
            // its endpoint rather than on the infinite line through it.
            val t = (((camX - ax) * dx + (camZ - az) * dz) / lengthSq)
                .coerceIn(0f, 1f)
            val px = ax + dx * t
            val pz = az + dz * t
            val offset = hypot(camX - px, camZ - pz)

            if (offset < bestOffset) {
                bestOffset = offset
                bestAlong = cum[i] + sqrt(lengthSq) * t
                bestSegment = i
                found = true
            }
        }

        if (!found) return false

        offsetM = bestOffset
        // Forward only. See the note on this class.
        if (bestAlong > alongM) {
            alongM = bestAlong
            segment = bestSegment
        }
        return true
    }

    /**
     * Where a given distance along the route falls, as (x, z) into [out].
     *
     * Clamped at both ends, so asking past the destination returns the
     * destination rather than extrapolating the last corridor through the wall
     * behind it.
     */
    fun pointAt(distanceM: Float, out: FloatArray) {
        val d = distanceM.coerceIn(0f, totalM)
        var i = 0
        while (i < xs.size - 2 && cum[i + 1] < d) i++

        val span = cum[i + 1] - cum[i]
        val t = if (span < 1e-6f) 0f else (d - cum[i]) / span
        out[0] = xs[i] + (xs[i + 1] - xs[i]) * t
        out[1] = zs[i] + (zs[i + 1] - zs[i]) * t
    }

    /**
     * The direction the route runs at a given distance along it, as a world
     * bearing — clockwise from −z, matching every other bearing in this app.
     */
    fun bearingAt(distanceM: Float): Float {
        val d = distanceM.coerceIn(0f, totalM)
        var i = 0
        while (i < xs.size - 2 && cum[i + 1] < d) i++
        return atan2(xs[i + 1] - xs[i], -(zs[i + 1] - zs[i]))
    }

    /**
     * How far along the next place worth sending somebody to is.
     *
     * Two kinds of place qualify, and the nearer one wins. A **vertex** is a
     * real feature — a corner of the corridor, the doorway the route turns
     * into — and is worth stopping at because it is somewhere the walker can
     * verify they have reached. A **checkpoint** on the [checkpointM] grid is
     * the filler between them, so that a thirty-metre straight does not leave
     * the ring invisibly far away for half a minute.
     *
     * Snapping to the vertex when one is close avoids the silly case: a ring
     * three metres along and a corner three and a half metres along are two
     * marks on the floor half a stride apart, and the walker cannot tell which
     * one they were meant to stand on.
     */
    fun nextMarkM(checkpointM: Float, minTurnDeg: Float): Float {
        val corner = nextCornerM(minTurnDeg)

        // The first grid multiple that is far enough ahead to stand on. Walking
        // onto a checkpoint would otherwise leave the ring on the walker's
        // feet until they crossed it.
        var grid = (
            Math.floor((alongM / checkpointM).toDouble()).toFloat() + 1f
            ) * checkpointM
        while (grid - alongM < MIN_MARK_AHEAD_M) grid += checkpointM

        // The corner wins when it is the nearer of the two and still far
        // enough away to walk to. A corner closer than that is one the walker
        // is already rounding, and marking it would plant the ring underneath
        // them at exactly the moment they need to see where the route goes
        // next.
        val mark = if (corner - alongM >= MIN_MARK_AHEAD_M && corner < grid) {
            corner
        } else {
            grid
        }
        return min(mark, totalM)
    }

    /**
     * How far along the next vertex the route actually **turns** at is.
     *
     * Not the next vertex — that was the bug this replaced. A route over a
     * traced plan carries a vertex at every waypoint and at every tap somebody
     * made along a corridor's centreline, so "the next vertex" is routinely
     * half a metre ahead and means nothing on the ground. Marking those put the
     * ring on an arbitrary point a step in front of the walker and moved it to
     * the next arbitrary point as they reached it, which is indistinguishable
     * from the ring not following the plan at all.
     *
     * A corner is different: it is a place in the building. The corridor ends,
     * or the route turns into a doorway, and a walker arriving at one can see
     * that they are where they were sent. Everything between corners is paced
     * out on the checkpoint grid instead.
     *
     * Returns [totalM] — the destination, which is always worth marking — when
     * the route runs straight from here to the end.
     */
    fun nextCornerM(minTurnDeg: Float): Float {
        for (i in 1 until xs.size - 1) {
            if (cum[i] <= alongM + MIN_MARK_AHEAD_M * 0.5f) continue
            if (turnAtVertexDeg(i) >= minTurnDeg) return cum[i]
        }
        return totalM
    }

    /**
     * How sharply the route turns at vertex [index], in degrees.
     *
     * Used both to find corners and to decide whether the arrow may aim past
     * the mark: aiming past a right-angle corner points the walker through the
     * wall on the outside of it.
     */
    fun turnAtVertexDeg(index: Int): Float {
        if (index <= 0 || index >= xs.size - 1) return 0f

        val inBearing = atan2(xs[index] - xs[index - 1], -(zs[index] - zs[index - 1]))
        val outBearing = atan2(xs[index + 1] - xs[index], -(zs[index + 1] - zs[index]))
        var delta = (outBearing - inBearing) * 180f / Math.PI.toFloat()
        while (delta > 180f) delta -= 360f
        while (delta < -180f) delta += 360f
        return abs(delta)
    }

    /** The destination, as (x, z) into [out]. */
    fun destination(out: FloatArray) {
        out[0] = xs[xs.size - 1]
        out[1] = zs[zs.size - 1]
    }

    /**
     * The same route shifted so that [alongM] lands on a known world position.
     *
     * What a confirmed landmark buys natively: the walker is standing at a
     * place the route names, so the accumulated drift between ARCore's world
     * and the plan can be taken out in one step rather than left to grow. The
     * shape is untouched — one point cannot say anything about the rotation,
     * and guessing at it from a single correction would make a good
     * registration worse as often as it fixed a bad one.
     */
    fun shiftedTo(camX: Float, camZ: Float, atAlongM: Float): RegisteredRoute {
        val here = FloatArray(2)
        pointAt(atAlongM, here)
        val dx = camX - here[0]
        val dz = camZ - here[1]

        val shifted = RegisteredRoute(
            FloatArray(xs.size) { xs[it] + dx },
            FloatArray(zs.size) { zs[it] + dz },
            floorY,
        )
        shifted.alongM = alongM
        shifted.segment = segment
        return shifted
    }

    private fun hypot(dx: Float, dz: Float): Float = sqrt(dx * dx + dz * dz)

    /** Progress carried across a re-registration that kept the same shape. */
    fun resumeFrom(previous: RegisteredRoute) {
        alongM = max(alongM, min(previous.alongM, totalM))
        segment = previous.segment.coerceIn(0, max(0, xs.size - 2))
    }
}
