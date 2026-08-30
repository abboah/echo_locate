package com.example.echo_locate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var depthHandler: ArCoreDepthHandler? = null
    private var captureHandler: RoomCaptureHandler? = null
    private var guidanceHandler: ArGuidanceHandler? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        val handler = ArCoreDepthHandler(this)
        depthHandler = handler

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ArCoreDepthHandler.METHOD_CHANNEL,
        ).setMethodCallHandler(handler)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ArCoreDepthHandler.EVENT_CHANNEL,
        ).setStreamHandler(handler)

        // The renderer *is* the texture registry. Capture draws the camera into
        // a texture it registers here rather than shipping frames to Dart, so
        // it needs the registry, not just a messenger.
        val capture = RoomCaptureHandler(this, flutterEngine.renderer)
        captureHandler = capture

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RoomCaptureHandler.METHOD_CHANNEL,
        ).setMethodCallHandler(capture)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RoomCaptureHandler.EVENT_CHANNEL,
        ).setStreamHandler(capture)

        // AR guidance: same texture arrangement as capture, plus a second event
        // channel carrying camera frames to ML Kit — ARCore holds the camera
        // exclusively, so sign reading has to be fed from its session or not at
        // all while this screen is up.
        val guidance = ArGuidanceHandler(this, flutterEngine.renderer)
        guidanceHandler = guidance

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ArGuidanceHandler.METHOD_CHANNEL,
        ).setMethodCallHandler(guidance)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ArGuidanceHandler.EVENT_CHANNEL,
        ).setStreamHandler(guidance)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            ArGuidanceHandler.FRAME_CHANNEL,
        ).setStreamHandler(guidance.frames)
    }

    /**
     * ARCore holds the camera exclusively. Leaving the session running when the
     * app goes to the background keeps the camera locked and makes ARCore fail
     * to resume on return, so the session is torn down here rather than in
     * onDestroy.
     */
    override fun onPause() {
        depthHandler?.stop()
        // Both sessions, and for the same reason: two ARCore sessions cannot
        // hold the camera at once either, so leaving one running is also what
        // makes the *other* fail to start.
        captureHandler?.stop()
        // Quietly: Dart stops this one itself on the lifecycle event that is
        // about to follow, and a "the session ended" push from here would reach
        // it while the framework still thinks the app is in the foreground —
        // where it reads as the camera having been taken away mid-walk.
        guidanceHandler?.stop(notify = false)
        super.onPause()
    }
}
