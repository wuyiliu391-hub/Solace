package com.solace.solace

import android.accessibilityservice.AccessibilityService
import android.content.ContentValues
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.BatteryManager
import android.os.Environment
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    private var volumeChannel: MethodChannel? = null
    private var deviceChannel: MethodChannel? = null
    private val shizukuManager by lazy { ShizukuManager(this) }
    private val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        volumeChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/volume_key"
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/settings"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openAppSettings" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                "canRequestPackageInstalls" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        result.success(packageManager.canRequestPackageInstalls())
                    } else result.success(true)
                }
                "openInstallSourceSettings" -> {
                    try {
                        val intent = Intent(
                            Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                            Uri.parse("package:$packageName")
                        )
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/battery"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getBatteryInfo" -> {
                    try {
                        result.success(getBatteryInfo())
                    } catch (e: Exception) {
                        result.error("BATTERY_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // 保存图片到系统相册（MediaStore，Android 10+ 兼容）
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/gallery"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "saveImageToGallery" -> {
                    try {
                        val filePath = call.argument<String>("filePath") ?: ""
                        val saved = saveImageToGallery(filePath)
                        result.success(saved)
                    } catch (e: Exception) {
                        result.error("SAVE_ERROR", e.message, null)
                    }
                }
                else -> result.notImplemented()
            }
        }

        // ─── 设备操控 MethodChannel ───
        deviceChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/device"
        ).apply {
            setMethodCallHandler { call, result ->
                handleDeviceMethodCall(call, result)
            }
        }

        // 注册无障碍服务结果回调（用于从 Service 异步返回结果）
        DeviceAccessibilityService.resultCallback = { method, data ->
            mainHandler.post {
                deviceChannel?.invokeMethod(method, data)
            }
        }
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (keyCode == KeyEvent.KEYCODE_VOLUME_UP) {
            volumeChannel?.invokeMethod("volume_up", null)
            return true
        }
        if (keyCode == KeyEvent.KEYCODE_VOLUME_DOWN) {
            volumeChannel?.invokeMethod("volume_down", null)
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    // ─── 设备操控方法处理 ───

    private fun handleDeviceMethodCall(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        try {
            when (call.method) {
                // ─── 状态检测 ───
                "isAccessibilityServiceEnabled" -> {
                    result.success(DeviceAccessibilityService.isRunning)
                }
                "openAccessibilitySettings" -> {
                    try {
                        val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS)
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                "isShizukuAvailable" -> {
                    result.success(ShizukuManager.isShizukuAvailable())
                }
                "isShizukuAuthorized" -> {
                    result.success(ShizukuManager.isShizukuAuthorized())
                }
                "openShizuku" -> {
                    try {
                        // 引导用户打开 Shizuku App
                        val intent = packageManager.getLaunchIntentForPackage("moe.shizuku.manager")
                        if (intent != null) {
                            startActivity(intent)
                            result.success(true)
                        } else {
                            // Shizuku 未安装，打开引导页面
                            result.success(false)
                        }
                    } catch (e: Exception) {
                        result.error("FAILED", e.message, null)
                    }
                }
                "getEngineStatus" -> {
                    val a11y = DeviceAccessibilityService.isRunning
                    val shizuku = ShizukuManager.isShizukuAuthorized()
                    val status = when {
                        a11y && shizuku -> "dual"
                        a11y -> "a11y_only"
                        shizuku -> "shizuku_only"
                        else -> "none"
                    }
                    result.success(status)
                }

                // ─── AccessibilityService 操作 ───
                "tap" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) {
                        val x = (call.argument<Double>("x") ?: 0.0).toFloat()
                        val y = (call.argument<Double>("y") ?: 0.0).toFloat()
                        result.success(service.performTap(x, y))
                    } else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "swipe" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) {
                        val x1 = (call.argument<Double>("x1") ?: 0.0).toFloat()
                        val y1 = (call.argument<Double>("y1") ?: 0.0).toFloat()
                        val x2 = (call.argument<Double>("x2") ?: 0.0).toFloat()
                        val y2 = (call.argument<Double>("y2") ?: 0.0).toFloat()
                        val duration = (call.argument<Int>("durationMs") ?: 300).toLong()
                        result.success(service.performSwipe(x1, y1, x2, y2, duration))
                    } else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "longPress" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) {
                        val x = (call.argument<Double>("x") ?: 0.0).toFloat()
                        val y = (call.argument<Double>("y") ?: 0.0).toFloat()
                        val duration = (call.argument<Int>("durationMs") ?: 800).toLong()
                        result.success(service.performLongPress(x, y, duration))
                    } else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "back" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) result.success(service.performBack())
                    else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "home" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) result.success(service.performHome())
                    else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "recentApps" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) result.success(service.performRecentApps())
                    else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "clickText" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) {
                        val text = call.argument<String>("text") ?: ""
                        result.success(service.clickByText(text))
                    } else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "typeText" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) {
                        val text = call.argument<String>("text") ?: ""
                        result.success(service.typeText(text))
                    } else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "getScreenContent" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) {
                        result.success(service.getScreenContent())
                    } else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "refreshScreenContent" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) {
                        result.success(service.refreshScreenContent())
                    } else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "openApp" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) {
                        val pkg = call.argument<String>("packageName") ?: ""
                        result.success(service.openApp(pkg))
                    } else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "getNotifications" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) {
                        val list = service.getNotifications()
                        val jsonArr = JSONArray()
                        for (item in list) {
                            jsonArr.put(JSONObject(item as Map<String, Any>))
                        }
                        result.success(jsonArr.toString())
                    } else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "getScreenSize" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) {
                        val (w, h) = service.getScreenSize()
                        result.success(mapOf("width" to w, "height" to h))
                    } else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "openNotifications" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) result.success(service.performOpenNotifications())
                    else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }
                "quickSettings" -> {
                    val service = DeviceAccessibilityService.instance
                    if (service != null) result.success(service.performOpenQuickSettings())
                    else result.error("SERVICE_NOT_RUNNING", "AccessibilityService not running", null)
                }

                // ─── Shizuku 操作 ───
                "shizukuExec" -> {
                    if (!ShizukuManager.isShizukuAuthorized()) {
                        result.error("SHIZUKU_NOT_AVAILABLE", "Shizuku not available or authorized", null)
                        return
                    }
                    val command = call.argument<String>("command") ?: ""
                    val shellResult = shizukuManager.executeCommand(command)
                    result.success(mapOf(
                        "success" to shellResult.success,
                        "output" to shellResult.output,
                        "error" to shellResult.error
                    ))
                }
                "shizukuSetWifi" -> {
                    if (!ShizukuManager.isShizukuAuthorized()) {
                        result.error("SHIZUKU_NOT_AVAILABLE", null, null); return
                    }
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    val r = shizukuManager.setWifiEnabled(enabled)
                    result.success(mapOf("success" to r.success, "output" to r.output))
                }
                "shizukuSetVolume" -> {
                    if (!ShizukuManager.isShizukuAuthorized()) {
                        result.error("SHIZUKU_NOT_AVAILABLE", null, null); return
                    }
                    val level = call.argument<Int>("level") ?: 50
                    val r = shizukuManager.setVolume(level)
                    result.success(mapOf("success" to r.success, "output" to r.output))
                }
                "shizukuSetBrightness" -> {
                    if (!ShizukuManager.isShizukuAuthorized()) {
                        result.error("SHIZUKU_NOT_AVAILABLE", null, null); return
                    }
                    val level = call.argument<Int>("level") ?: 128
                    val r = shizukuManager.setBrightness(level)
                    result.success(mapOf("success" to r.success, "output" to r.output))
                }
                "shizukuInstallApp" -> {
                    if (!ShizukuManager.isShizukuAuthorized()) {
                        result.error("SHIZUKU_NOT_AVAILABLE", null, null); return
                    }
                    val path = call.argument<String>("apkPath") ?: ""
                    val r = shizukuManager.installApp(path)
                    result.success(mapOf("success" to r.success, "output" to r.output))
                }
                "shizukuUninstallApp" -> {
                    if (!ShizukuManager.isShizukuAuthorized()) {
                        result.error("SHIZUKU_NOT_AVAILABLE", null, null); return
                    }
                    val pkg = call.argument<String>("packageName") ?: ""
                    val r = shizukuManager.uninstallApp(pkg)
                    result.success(mapOf("success" to r.success, "output" to r.output))
                }
                "shizukuGrantPermission" -> {
                    if (!ShizukuManager.isShizukuAuthorized()) {
                        result.error("SHIZUKU_NOT_AVAILABLE", null, null); return
                    }
                    val pkg = call.argument<String>("packageName") ?: ""
                    val perm = call.argument<String>("permission") ?: ""
                    val r = shizukuManager.grantPermission(pkg, perm)
                    result.success(mapOf("success" to r.success, "output" to r.output))
                }
                "shizukuSetBluetooth" -> {
                    if (!ShizukuManager.isShizukuAuthorized()) {
                        result.error("SHIZUKU_NOT_AVAILABLE", null, null); return
                    }
                    val enabled = call.argument<Boolean>("enabled") ?: true
                    val r = shizukuManager.setBluetoothEnabled(enabled)
                    result.success(mapOf("success" to r.success, "output" to r.output))
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("DEVICE_ERROR", e.message, null)
        }
    }

    // ─── 已有方法 ───

    private fun getBatteryInfo(): Map<String, Any> {
        val batteryIntent = registerReceiver(
            null,
            IntentFilter(Intent.ACTION_BATTERY_CHANGED)
        )
        val level = batteryIntent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = batteryIntent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val percentage = if (level >= 0 && scale > 0) (level * 100 / scale) else 0
        val status = batteryIntent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val isCharging = status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
        val plugged = batteryIntent?.getIntExtra(BatteryManager.EXTRA_PLUGGED, -1) ?: -1
        val chargeSource = when (plugged) {
            BatteryManager.BATTERY_PLUGGED_AC -> "ac"
            BatteryManager.BATTERY_PLUGGED_USB -> "usb"
            BatteryManager.BATTERY_PLUGGED_WIRELESS -> "wireless"
            else -> "none"
        }
        return mapOf(
            "percentage" to percentage,
            "isCharging" to isCharging,
            "isFull" to (status == BatteryManager.BATTERY_STATUS_FULL),
            "chargeSource" to chargeSource
        )
    }

    private fun saveImageToGallery(filePath: String): Boolean {
        return try {
            val file = java.io.File(filePath)
            if (!file.exists()) return false

            val fileName = "Solace_${System.currentTimeMillis()}.png"
            val contentValues = ContentValues().apply {
                put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Images.Media.MIME_TYPE, "image/png")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    put(MediaStore.Images.Media.IS_PENDING, 1)
                }
            }

            val resolver = contentResolver
            val imageCollectionUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                MediaStore.Images.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
            } else {
                MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            }

            val insertedUri = resolver.insert(imageCollectionUri, contentValues) ?: return false

            resolver.openOutputStream(insertedUri)?.use { outputStream ->
                file.inputStream().use { inputStream ->
                    inputStream.copyTo(outputStream)
                }
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentValues.clear()
                contentValues.put(MediaStore.Images.Media.IS_PENDING, 0)
                resolver.update(insertedUri, contentValues, null, null)
            }

            true
        } catch (e: Exception) {
            false
        }
    }

    override fun onDestroy() {
        DeviceAccessibilityService.resultCallback = null
        super.onDestroy()
    }
}
