package com.example.echo_locate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * The route laid into the room, checked on the desk.
 *
 * Everything here is the geometry that decides where the ring lands, and every
 * failure it guards against looks the same on a phone: an arrow that seems not
 * to be following the plan. Telling "the registration is wrong", "the mark rule
 * is wrong" and "there is no registration at all" apart in a corridor means
 * walking the corridor again. Here it takes a second.
 *
 * World coordinates throughout: x to the right, z toward the viewer, so a route
 * running "straight ahead" runs along −z.
 */
class RegisteredRouteTest {

    private val checkpoint = 3f
    private val corner = 35f

    /**
     * A straight 30 m run along −z, sampled every 1.7 m.
     *
     * The spacing is deliberately not a factor of [checkpoint]: a vertex that
     * happens to land on a grid multiple cannot tell the two rules apart, and
     * telling them apart is the whole point of these tests.
     */
    private fun denselySampledStraight(): RegisteredRoute {
        val count = 19
        val xs = FloatArray(count) { 0f }
        val zs = FloatArray(count) { -1.7f * it }
        return RegisteredRoute(xs, zs, floorY = -1.35f)
    }

    /** Walks [route] to [alongM] in steps small enough to track, as a walker does. */
    private fun walkTo(route: RegisteredRoute, alongM: Float) {
        val out = FloatArray(2)
        var d = 0f
        while (d < alongM) {
            d = minOf(d + 0.5f, alongM)
            route.pointAt(d, out)
            route.update(out[0], out[1])
        }
    }

    /** 20 m along −z, then a right-angle left turn and 12 m along −x. */
    private fun lShaped(): RegisteredRoute = RegisteredRoute(
        floatArrayOf(0f, 0f, -12f),
        floatArrayOf(0f, -20f, -20f),
        floorY = -1.35f,
    )

    @Test
    fun `a route measures its own length`() {
        assertEquals(32f, lShaped().totalM, 1e-4f)
        // Eighteen segments of 1.7 m.
        assertEquals(30.6f, denselySampledStraight().totalM, 1e-4f)
    }

    @Test
    fun `walking down the line advances the walk and stays on it`() {
        val route = lShaped()
        route.update(0f, -8f)

        assertEquals(8f, route.alongM, 1e-3f)
        assertEquals(0f, route.offsetM, 1e-3f)
    }

    @Test
    fun `stepping aside is measured as offset, not as progress`() {
        val route = lShaped()
        route.update(2f, -8f)

        assertEquals(8f, route.alongM, 1e-3f)
        assertEquals(2f, route.offsetM, 1e-3f)
    }

    @Test
    fun `progress never runs backwards`() {
        val route = lShaped()
        route.update(0f, -10f)
        route.update(0f, -4f)

        // ARCore relocalising, or a walker stepping back to read a sign. The
        // guidance clock upstairs refuses to run backwards and re-speak cues
        // it has already spoken, and it can only do that if this does.
        assertEquals(10f, route.alongM, 1e-3f)
    }

    /**
     * The bug this file was written for.
     *
     * A route over a traced plan carries a vertex at every waypoint and at
     * every tap somebody made along a corridor's centreline. Marking "the next
     * vertex" put the ring wherever the nearest of those happened to be —
     * routinely half a metre ahead — and moved it to the next one as the walker
     * reached it. On a phone that is indistinguishable from the ring ignoring
     * the plan entirely, which is exactly how it was reported.
     */
    @Test
    fun `a densely sampled straight is marked on the grid, not on its vertices`() {
        val route = denselySampledStraight()
        walkTo(route, 4f) // Vertices at 3.4 m and 5.1 m; grid at 6 m.

        val mark = route.nextMarkM(checkpoint, corner)

        // The old rule marked 5.1 — a tap somebody made while tracing the
        // corridor's centreline, a metre ahead, meaning nothing on the ground.
        assertEquals(6f, mark, 1e-3f)
    }

    @Test
    fun `a mark too close to stand on is skipped rather than planted`() {
        val route = denselySampledStraight()
        walkTo(route, 5f) // The 6 m grid point is only a metre ahead.

        // Rather than mark something they are about to step on, the ring goes
        // to the checkpoint after it.
        assertEquals(9f, route.nextMarkM(checkpoint, corner), 1e-3f)
    }

    @Test
    fun `every mark on a long straight stays a walkable distance ahead`() {
        val route = denselySampledStraight()
        val out = FloatArray(2)

        var d = 0f
        while (d < 26f) {
            d += 0.4f
            route.pointAt(d, out)
            route.update(out[0], out[1])

            val ahead = route.nextMarkM(checkpoint, corner) - route.alongM
            // Never underfoot, and never so far that the walker has nothing to
            // aim at between here and it.
            assertTrue("mark only ${ahead}m ahead at ${route.alongM}m", ahead >= 1.5f)
            assertTrue("mark ${ahead}m ahead is too far at ${route.alongM}m", ahead <= 6f)
        }
    }

    @Test
    fun `a real corner is found and marked in preference to the grid`() {
        val route = lShaped()
        walkTo(route, 18f) // Two metres short of the turn.

        assertEquals(20f, route.nextCornerM(corner), 1e-3f)
        // The grid would say 21; the corner at 20 is nearer and is a place in
        // the building the walker can recognise having reached.
        assertEquals(20f, route.nextMarkM(checkpoint, corner), 1e-3f)
    }

    @Test
    fun `a gentle wiggle is not a corner`() {
        // Ten degrees off straight — a hand-traced centreline, not a junction.
        val route = RegisteredRoute(
            floatArrayOf(0f, 0f, 2f),
            floatArrayOf(0f, -10f, -21f),
            floorY = -1.35f,
        )
        walkTo(route, 4f)

        // No corner before the end, so the destination is the only vertex worth
        // marking and everything before it is paced on the grid.
        assertEquals(route.totalM, route.nextCornerM(corner), 1e-3f)
        assertEquals(6f, route.nextMarkM(checkpoint, corner), 1e-3f)
    }

    @Test
    fun `the destination is always worth marking`() {
        val route = lShaped()
        walkTo(route, 31f) // A metre from the end.

        assertEquals(route.totalM, route.nextMarkM(checkpoint, corner), 1e-3f)
        assertTrue(route.remainingM <= 1.01f)
    }

    @Test
    fun `arriving is reported at the end and not before`() {
        val route = lShaped()
        walkTo(route, 19f)
        assertTrue(!route.arrived)

        walkTo(route, route.totalM)
        assertTrue(route.arrived)
    }

    @Test
    fun `a point on the line comes back where it was put`() {
        val route = lShaped()
        val out = FloatArray(2)

        route.pointAt(0f, out)
        assertEquals(0f, out[0], 1e-3f)
        assertEquals(0f, out[1], 1e-3f)

        route.pointAt(20f, out) // The corner.
        assertEquals(0f, out[0], 1e-3f)
        assertEquals(-20f, out[1], 1e-3f)

        route.pointAt(26f, out) // Six metres round it.
        assertEquals(-6f, out[0], 1e-3f)
        assertEquals(-20f, out[1], 1e-3f)
    }

    @Test
    fun `asking past the end returns the destination rather than extrapolating`() {
        val route = lShaped()
        val out = FloatArray(2)
        route.pointAt(500f, out)

        // Otherwise the arrow points at a spot far through the wall behind the
        // door it was sending somebody to.
        assertEquals(-12f, out[0], 1e-3f)
        assertEquals(-20f, out[1], 1e-3f)
    }

    @Test
    fun `a route that doubles back does not teleport the walker across it`() {
        // Out 10 m and back along a parallel line two metres away — a corridor
        // walked to the end and returned along. The two halves are close
        // together, and projecting onto the whole line would jump between them.
        val route = RegisteredRoute(
            floatArrayOf(0f, 0f, 2f, 2f),
            floatArrayOf(0f, -10f, -10f, 0f),
            floorY = -1.35f,
        )

        route.update(0f, -2f)
        assertEquals(2f, route.alongM, 1e-2f)

        // Standing at (2, -2) is a metre from the *return* leg, which is 20 m
        // along — but they have only walked two. The search window is what
        // stops the walk jumping to the far half.
        route.update(0.5f, -3f)
        assertTrue("jumped to ${route.alongM}m", route.alongM < 8f)
    }

    @Test
    fun `a re-registration of the same walk resumes where it left off`() {
        val first = lShaped()
        walkTo(first, 14f)

        val second = lShaped()
        second.resumeFrom(first)

        // Dart re-registers mid-corridor when the walker drifts off the line.
        // Starting the new route from zero would send them back down it.
        assertEquals(14f, second.alongM, 1e-3f)
    }

    @Test
    fun `a route needs two points to exist at all`() {
        val threw = try {
            RegisteredRoute(floatArrayOf(1f), floatArrayOf(1f), floorY = 0f)
            false
        } catch (e: IllegalArgumentException) {
            true
        }
        assertTrue("a one-point route was accepted", threw)
    }
}
