package com.mylifegraph.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var healthConnectBridge: HealthConnectBridge? = null
    private var pushBridge: PushBridge? = null

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        healthConnectBridge?.onPermissionResult(requestCode)
        pushBridge?.onPermissionResult(requestCode)
    }

    override fun onDestroy() {
        healthConnectBridge?.dispose()
        healthConnectBridge = null
        pushBridge?.dispose()
        pushBridge = null
        super.onDestroy()
    }
    override fun onResume() {
        super.onResume()
        FocusBlockAccessibilityService.onAppResumed(applicationContext)
        PushBridge.captureIntent(this, intent)
    }

    override fun onNewIntent(intent: android.content.Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        PushBridge.captureIntent(this, intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        pushBridge = PushBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, PushBridge.CHANNEL)
            .setMethodCallHandler { call, result -> pushBridge?.handle(call, result) }
        healthConnectBridge = HealthConnectBridge(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, HealthConnectBridge.CHANNEL)
            .setMethodCallHandler { call, result -> healthConnectBridge?.handle(call, result) }
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
