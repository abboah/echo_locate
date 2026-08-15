package com.example.echo_locate

import android.util.Log
import com.google.ar.core.Anchor
import com.google.ar.core.Frame
import com.google.ar.core.Plane
import com.google.ar.core.TrackingState

/** Which horizontal surface a room is being traced against. */
enum class CaptureSurface {
    FLOOR,
    CEILING;

    val wireName: String get() = name.lowercase()
}

/**
 * Turns a tap on the screen into a point on the building's floor **or ceiling**.
 *
 * ## Why a horizontal surface and not the corner
 *
 * The user taps at the base of each corner, never the corner itself.
 * Wall-to-wall junctions are where ARCore's plane boundaries are least
 * reliable — they are feature-poor and geometrically ambiguous, so the fitted
 * plane edge wanders. Large horizontal planes are ARCore's most dependable
 * output, so the interaction is built around a surface it is good at and the
 * corner is inferred from where the walls meet it.
 *
 * ## Why the ceiling counts as one of them
 *
 * A furnished room hides its own floor. Desks, stacked chairs, filing cabinets
 * and boxes sit in exactly the corners that define the shape, so the floor
 * plane either never extends that far or the ray hits the furniture instead —
 * and a corner placed on a desktop is, in plan terms, simply somewhere else.
 * The ceiling above those corners is almost always clear.
 *
 * **The plan coordinate is unaffected**, which is what makes this cheap rather
 * than a second coordinate system. A room's walls are vertical, so the ceiling
 * corner sits directly above the floor corner and the two differ only in Y —
 * and Y is dropped on the way to the plan frame (see
 * `arcore_capture_service.dart`). Tracing a room around its ceiling produces
 * the same polygon as tracing it around its floor.
 *
 * The honest caveats, since none of this has been measured on a phone yet:
 * ceilings are often plain and flat, so ARCore detects them later and less
 * completely than a textured floor, and holding the phone up to trace one is
 * more tiring. It is the fallback for a cluttered room, not the default.
 *
 * ## Three guards, all load-bearing
 *
 * 1. **[Plane.isPoseInPolygon]** — without it, `hitTest` happily returns points
 *    on the *infinite* mathematical plane, metres beyond anything ARCore has
 *    actually observed. Those come back as plausible coordinates that are pure
 *    fabrication, and they land in parts of the room the camera never saw.
 *
 * 2. **Surface locking** — desks, beds and windowsills are all
 *    `HORIZONTAL_UPWARD_FACING`, and a ceiling fan's housing is
 *    `HORIZONTAL_DOWNWARD_FACING`. Without a lock, a stray tap on any of them
 *    puts a corner most of a metre out of plane.
 *
 * 3. **The facing is part of the lock.** A room traced against its ceiling must
 *    stay on the ceiling for every corner; half a polygon from each surface is
 *    still a valid-looking polygon, and there is nothing downstream that could
 *    notice. Which surface a room ends up on is decided by its **first** tap and
 *    reported back to the UI, so a lock that went to the wrong one is visible
 *    rather than inferred from a misshapen plan later.
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
class SurfaceHitTester {

    companion object {
        private const val TAG = "SurfaceHitTester"

        /**
         * How far above or below the locked plane a hit may land and still be
         * accepted, in metres.
         *
         * ARCore's plane estimate drifts by a few centimetres as it explores,
         * so an exact match would reject legitimate taps. Anything much beyond
         * this is a different surface — a step, a low table, a dropped ceiling
         * tile — and is meant to be rejected. **Tuning point:** raise it for
         * buildings with uneven floors, lower it where furniture is being
         * picked up.
         */
        const val PLANE_TOLERANCE_METRES = 0.12f
    }

    /** The surface we locked onto. Every corner of a room must land on it. */
    private var anchorPlane: Plane? = null

    /** Height of the locked plane, for the tolerance check. */
    private var anchorY: Float = 0f

    /**
     * Whether this room is being traced on the floor or the ceiling. Null until
     * the first corner lands, because it is that tap which decides.
     */
    var lockedSurface: CaptureSurface? = null
        private set

    val hasLock: Boolean get() = anchorPlane != null

    /**
     * Called when a room is finished, or when its last corner is undone, so the
     * next room locks to its own surface — and so a room that locked to the
     * wrong one can be recovered by undoing back to nothing rather than by
     * restarting the session.
     */
    fun reset() {
        anchorPlane = null
        anchorY = 0f
        lockedSurface = null
    }

    /**
     * Hit-tests at [xPx], [yPx] in the coordinate space most recently passed to
     * `Session.setDisplayGeometry`.
     *
     * Returns null when the tap hit nothing usable — no tracking, no plane, a
     * point outside the detected boundary, or a surface that is not the one
     * this room was started on. Null is a normal outcome and the UI says "try
     * again, aim at the floor" rather than treating it as an error.
     *
     * [lockToSurface] is what separates the two things this method is asked
     * for. **A room's corners must be coplanar** — that is what the lock is
     * for, and it is the whole reason a tap on a desk is rejected. **A door is
     * a single independent point**, tapped while standing in a doorway
     * somewhere else in the building, on a floor plane ARCore may never have
     * merged with the one the last room was traced on. Holding doors to the
     * lock rejected every doorway after the first, for a reason no user could
     * see; it is only more visible with ceilings, where a room traced overhead
     * would reject a door tapped at the contributor's feet.
     */
    fun hit(
        frame: Frame,
        xPx: Float,
        yPx: Float,
        lockToSurface: Boolean = true,
    ): SurfaceHit? {
        if (frame.camera.trackingState != TrackingState.TRACKING) return null

        for (result in frame.hitTest(xPx, yPx)) {
            val trackable = result.trackable
            if (trackable !is Plane) continue

            val facing = surfaceOf(trackable) ?: continue

            // Inside the *detected* boundary, not the infinite plane. Dropping
            // this check is what produces confident coordinates for parts of
            // the room nobody has looked at.
            if (!trackable.isPoseInPolygon(result.hitPose)) continue

            val translation = result.hitPose.translation
            val locked = anchorPlane

            if (!lockToSurface) {
                // Neither read nor written: a door must not lock the surface
                // the next room will be traced against either.
            } else if (locked == null) {
                anchorPlane = trackable
                anchorY = translation[1]
                lockedSurface = facing
            } else if (facing != lockedSurface) {
                // The floor of a room and its ceiling are both legitimate
                // targets, and mixing them within one room is not.
                continue
            } else if (!isSameSurface(trackable, locked)) {
                continue
            } else if (kotlin.math.abs(translation[1] - anchorY) > PLANE_TOLERANCE_METRES) {
                // Same plane object, wrong height: a merged plane that now
                // spans a step. Rejecting is safer than recording a corner on
                // the wrong level.
                continue
            }

            return SurfaceHit(
                x = translation[0],
                z = translation[2],
                // A plane ARCore is still tracking is worth more than one it has
                // stopped updating; the Dart side keeps the number so a plan can
                // report how much of it was captured under good tracking.
                confidence = if (trackable.trackingState == TrackingState.TRACKING) 1f else 0.5f,
                surface = facing,
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
     * Which of the two surfaces this plane is, or null if it is neither.
     *
     * Vertical planes are excluded here rather than in the session config,
     * because the session asks for `HORIZONTAL` plane finding only — this is
     * the belt to that braces, and it is what keeps a future config change from
     * silently letting walls into the polygon.
     */
    private fun surfaceOf(plane: Plane): CaptureSurface? = when (plane.type) {
        Plane.Type.HORIZONTAL_UPWARD_FACING -> CaptureSurface.FLOOR
        Plane.Type.HORIZONTAL_DOWNWARD_FACING -> CaptureSurface.CEILING
        else -> null
    }

    /**
     * Whether [candidate] and [locked] are the same physical surface, following
     * ARCore's subsumption chain **in both directions**.
     *
     * The direction that matters in practice is `locked` being subsumed by a
     * newer, larger plane as the surface is explored — see the class note.
     * Walking both chains costs nothing and removes the ordering assumption
     * entirely.
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
 * One tapped point on a horizontal surface, in ARCore world space.
 *
 * Y is dropped on the Dart side: the plan frame is built from X and Z, which is
 * exactly why a ceiling trace and a floor trace of the same room produce the
 * same polygon. See `room_geometry.dart` for the frame, and
 * `arcore_capture_service.dart` for the conversion — including the sign flip,
 * which is the single easiest thing to get wrong here.
 */
data class SurfaceHit(
    val x: Float,
    val z: Float,
    val confidence: Float,
    /** Which surface this point was taken from — floor or ceiling. */
    val surface: CaptureSurface,
    /**
     * ARCore's handle on this point, kept so its position can be re-read after
     * a relocalisation. Detached when the corner is undone or the room closes —
     * anchors cost tracking work, and a session that never releases them slows
     * down as a building is walked.
     */
    val anchor: Anchor,
)
