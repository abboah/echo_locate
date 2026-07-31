package com.example.echo_locate

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    private var depthHandler: ArCoreDepthHandler? = null

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
    }

    /**
     * ARCore holds the camera exclusively. Leaving the session running when the
     * app goes to the background keeps the camera locked and makes ARCore fail
     * to resume on return, so the session is torn down here rather than in
     * onDestroy.
     */
    override fun onPause() {
        depthHandler?.stop()
        super.onPause()
    }
}
