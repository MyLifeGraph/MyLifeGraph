package com.mylifegraph.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val manager = FocusProtectionManager(applicationContext)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "readStatus" -> result.success(manager.readStatus())
                    "listLaunchableApps" -> result.success(manager.listLaunchableApps())
                    "saveConfiguration" -> result.success(
                        manager.saveConfiguration(requireArguments(call.arguments)),
                    )
                    "openAccessibilitySettings" -> {
                        manager.openAccessibilitySettings()
                        result.success(null)
                    }
                    "openNotificationPolicySettings" -> {
                        manager.openNotificationPolicySettings()
                        result.success(null)
                    }
                    "activateLease" -> result.success(
                        manager.activateLease(requireArguments(call.arguments)),
                    )
                    "deactivateLease" -> result.success(
                        manager.deactivateLease(requireSessionId(call.arguments)),
                    )
                    "emergencyRelease" -> result.success(
                        manager.emergencyRelease(requireSessionId(call.arguments)),
                    )
                    else -> result.notImplemented()
                }
            } catch (error: Throwable) {
                result.error(
                    "focus_protection_error",
                    error.message ?: "Android Focus protection failed.",
                    null,
                )
            }
        }
    }

    private fun requireArguments(value: Any?): Map<*, *> =
        value as? Map<*, *> ?: throw IllegalArgumentException("Missing arguments.")

    private fun requireSessionId(value: Any?): String {
        val arguments = requireArguments(value)
        return arguments["sessionId"] as? String
            ?: throw IllegalArgumentException("Missing session id.")
    }

    companion object {
        private const val CHANNEL_NAME = "com.mylifegraph.app/focus_protection"
    }
}
