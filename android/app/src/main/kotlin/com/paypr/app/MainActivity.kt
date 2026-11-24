package com.paypr.app

import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    @Suppress("DEPRECATION")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.paypr.app/app_info",
        ).setMethodCallHandler { call, result ->
            if (call.method != "getVersion") {
                result.notImplemented()
                return@setMethodCallHandler
            }
            val info = packageManager.getPackageInfo(packageName, 0)
            val build = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                info.versionCode.toLong()
            }
            result.success(info.versionName?.let { "$it ($build)" })
        }
    }

    @Suppress("DEPRECATION")
    override fun onResume() {
        super.onResume()

        val currentDisplay = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            windowManager.defaultDisplay
        } ?: return

        val activeMode = currentDisplay.mode
        val preferredModeId = currentDisplay.supportedModes.filter {
            it.physicalWidth == activeMode.physicalWidth &&
                it.physicalHeight == activeMode.physicalHeight &&
                it.refreshRate in 119f..121f
        }.maxByOrNull { it.refreshRate }?.modeId ?: 0

        // Request the 120 Hz mode at the current resolution. A refresh-rate
        // hint alone allows some devices to select their 90 Hz category.
        val params = window.attributes
        if (params.preferredDisplayModeId != preferredModeId) {
            params.preferredDisplayModeId = preferredModeId
            window.attributes = params
        }
    }
}
