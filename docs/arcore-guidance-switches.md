# ARCore guidance switches

Two compile-time switches in `android/app/src/main/kotlin/com/example/echo_locate/ArGuidanceHandler.kt`.
Flip either to `false`, rebuild, and that half of the registration behaves like
the build before it. Kept as a note because they are the first thing to reach
for when the arrow is wrong on hardware, and the trade-off each one makes is
not obvious from the code.

These lived as a block comment at the bottom of `lib/app.dart` — a Dart file
holding the root widget, which is the last place anybody debugging the Kotlin
AR layer would look.

Top of ArGuidanceHandler.kt, lines 145 and 163:

private const val MEASURE_FLOOR = true    // line 145
private const val FOLLOW_ANCHORS = true   // line 163

Flip either to false, rebuild, and that half of yesterday's
work behaves exactly like the build you had before it.

MEASURE_FLOOR = false — no plane fitting at all, floor falls
back to the assumed 1.35 m below the phone. Turn this off
first if the session stutters when the guidance screen
opens. Your 60 fps measurement on the Infinix was taken
without plane finding, and it now competes with the ML Kit
frame feed for the first 20 seconds rather than 9.

**The cost of turning it off is no longer only cosmetic.**
It used to be: an assumed floor height, a ring floating a
few centimetres off. The same switch now also turns off
vertical plane finding, and the wall grid those planes
supply is the only thing correcting the registration's yaw
— which rotates the entire building and which no landmark
can repair. Without it the rotation falls back to the
direction the walker happened to set off in, which is the
thing that was putting rings in the wrong room.

So: turn it off to get frames back, and expect the arrow to
be roughly right rather than right. Read `off …m` in the
capture before and after, not the frame rate alone.

FOLLOW_ANCHORS = false — route and leg keep the raw world
coordinates they were laid down in. Turn this off if a
registered route looks wrong in a way a dead-reckoned leg
doesn't: arrow drifting sideways, the line slowly rotating,
rings landing off the corridor. This is the only code that
rewrites route geometry after registration, so if the
geometry is being mangled, it's this or nothing. Cost of
turning it off is that a relocalisation moves the building
out from under the route.
