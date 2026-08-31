package com.example.echo_locate

/**
 * Whoever currently holds the ARCore session.
 *
 * ARCore takes the camera **exclusively**, and this app has two things that
 * want it: the depth probe and AR guidance. Navigating from one screen to the
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
