package com.example.echo_locate

import android.util.Log
import com.google.ar.core.Anchor
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.TrackingState

/**
 * Turns a tap on the screen into a point on the building's floor.
 *
 * ## Why the floor and not the corner
 *
 * The user taps the floor **at the base of each corner**, never the corner
 * itself. Wall-to-wall junctions are where ARCore's plane boundaries are least
 * reliable — they are feature-poor and geometrically ambiguous, so the fitted
 * plane edge wanders. Floor planes are ARCore's most dependable output, so the
 * interaction is built around the surface it is good at and the corner is
 * inferred from where the walls meet.
 *
 * ## Two guards, both load-bearing
 *
 * 1. **[Plane.isPoseInPolygon]** — without it, `hitTest` happily returns points
 *    on the *infinite* mathematical plane, metres beyond anything ARCore has
 *    actually observed. Those come back as plausible coordinates that are pure
 *    fabrication, and they land in parts of the room the camera never saw.
 *
 * 2. **Plane locking** — desks, beds and windowsills are all
 *    `HORIZONTAL_UPWARD_FACING`. Without a lock, a stray tap on a table puts a
 *    corner three-quarters of a metre off the floor, which in plan terms is
 *    simply the wrong place.
 *
 * ## The subsumption trap
 *
 * ARCore merges planes continuously as it explores, and when it does it
 * commonly subsumes the older, smaller plane into a new larger one. A lock that
 * only checks `candidate.subsumedBy == locked` therefore breaks the moment the
 * floor grows: every later tap lands on the new plane, whose `subsumedBy` is
 * null and which is not the locked instance, so **every remaining corner is
 * silently rejected** halfway through a room.
 *
 * [isSameSurface] follows the chain in both directions, which is what makes the
 * lock survive the merge.
 */
class FloorHitTester {

    companion object {
        private const val TAG = "FloorHitTester"

        /**
         * How far above or below the locked plane a hit may land and still be
         * accepted, in metres.
         *
         * ARCore's floor estimate drifts by a few centimetres as it explores,
         * so an exact plane match would reject legitimate taps. Anything much
         * beyond this is a different surface — a step, a low table — and is
         * meant to be rejected. **Tuning point:** raise it for buildings with
         * uneven floors, lower it where furniture is being picked up.
         */
        const val PLANE_TOLERANCE_METRES = 0.12f
    }

    /** The floor we locked onto. Every corner of a room must land on it. */
    private var anchorPlane: Plane? = null

    /** Height of the locked plane, for the tolerance check. */
    private var anchorY: Float = 0f

    val hasLock: Boolean get() = anchorPlane != null

    /** Called when a new room is started, so it can lock to its own floor. */
    fun reset() {
        anchorPlane = null
        anchorY = 0f
    }

    /**
     * Hit-tests at [xPx], [yPx] in the coordinate space most recently passed to
     * `Session.setDisplayGeometry`.
     *
     * Returns null when the tap hit nothing usable — no tracking, no plane, a
     * point outside the detected boundary, or a surface that is not the floor
     * this room was started on. Null is a normal outcome and the UI says "try
     * again, pointing at the floor" rather than treating it as an error.
     */
    fun hit(frame: Frame, xPx: Float, yPx: Float): FloorHit? {
        if (frame.camera.trackingState != TrackingState.TRACKING) return null

        for (result in frame.hitTest(xPx, yPx)) {
            val trackable = result.trackable
            if (trackable !is Plane) continue
            if (trackable.type != Plane.Type.HORIZONTAL_UPWARD_FACING) continue

            // Inside the *detected* boundary, not the infinite plane. Dropping
            // this check is what produces confident coordinates for parts of
            // the room nobody has looked at.
            if (!trackable.isPoseInPolygon(result.hitPose)) continue

            val translation = result.hitPose.translation
            val locked = anchorPlane

            if (locked == null) {
                anchorPlane = trackable
                anchorY = translation[1]
            } else if (!isSameSurface(trackable, locked)) {
                continue
            } else if (kotlin.math.abs(translation[1] - anchorY) > PLANE_TOLERANCE_METRES) {
                // Same plane object, wrong height: a merged plane that now
                // spans a step. Rejecting is safer than recording a corner on
                // the wrong level.
                continue
            }

            return FloorHit(
                x = translation[0],
                z = translation[2],
                // A plane ARCore is still tracking is worth more than one it has
                // stopped updating; the Dart side keeps the number so a plan can
                // report how much of it was captured under good tracking.
                confidence = if (trackable.trackingState == TrackingState.TRACKING) 1f else 0.5f,
                // An anchor, not just a number.
                //
                // ARCore can relocalise mid-room — it loses tracking, finds
                // itself again, and **shifts its idea of where the world
                // origin is**. Corners recorded as raw translations before and
                // after that shift are then in two different frames, and the
                // polygon quietly deforms: no error, no warning, a room that is
                // simply the wrong shape. An anchor is ARCore's own handle on a
                // fixed point in the world, and it is corrected along with
                // everything else, so re-reading it at close gives the position
                // in the frame that survived.
                anchor = result.createAnchor(),
            )
        }
        return null
    }

    /**
     * Whether [candidate] and [locked] are the same physical surface, following
     * ARCore's subsumption chain **in both directions**.
     *
     * The direction that matters in practice is `locked` being subsumed by a
     * newer, larger plane as the floor is explored — see the class note. Walking
     * both chains costs nothing and removes the ordering assumption entirely.
     */
    private fun isSameSurface(candidate: Plane, locked: Plane): Boolean {
        if (candidate == locked) return true

        // Follow each plane to the root of its merge chain and compare those.
        val candidateRoot = rootOf(candidate)
        val lockedRoot = rootOf(locked)
        if (candidateRoot == lockedRoot) {
            // Re-point the lock at the surviving plane so the chain does not
            // have to be walked again on every subsequent tap.
            anchorPlane = candidateRoot
            return true
        }
        return false
    }

    /** The plane that ultimately absorbed this one. */
    private fun rootOf(plane: Plane): Plane {
        var current = plane
        var guard = 0
        while (true) {
            val parent = current.subsumedBy ?: return current
            current = parent
            // ARCore should never produce a cycle, but a malformed chain here
            // would hang the render thread, and a hung render thread is a
            // frozen camera with no error anywhere.
            if (++guard > 16) {
                Log.w(TAG, "Subsumption chain too deep; stopping walk")
                return current
            }
        }
    }
}

/**
 * One tapped floor point, in ARCore world space.
 *
 * Y is dropped on the Dart side: the floor is the XZ plane, and the plan frame
 * is built from those two axes. See `room_geometry.dart` for the frame, and
 * `arcore_capture_service.dart` for the conversion — including the sign flip,
 * which is the single easiest thing to get wrong here.
 */
data class FloorHit(
    val x: Float,
    val z: Float,
    val confidence: Float,
    /**
     * ARCore's handle on this point, kept so its position can be re-read after
     * a relocalisation. Detached when the corner is undone or the room closes —
     * anchors cost tracking work, and a session that never releases them slows
     * down as a building is walked.
     */
    val anchor: Anchor,
)
