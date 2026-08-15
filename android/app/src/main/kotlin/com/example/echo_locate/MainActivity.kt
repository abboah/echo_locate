package com.example.echo_locate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var depthHandler: ArCoreDepthHandler? = null
    private var captureHandler: RoomCaptureHandler? = null

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

        val capture = RoomCaptureHandler(this)
        captureHandler = capture

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RoomCaptureHandler.METHOD_CHANNEL,
        ).setMethodCallHandler(capture)

        EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            RoomCaptureHandler.EVENT_CHANNEL,
        ).setStreamHandler(capture)
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
        super.onPause()
    }
}
