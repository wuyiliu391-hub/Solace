package com.solace.solace

import android.app.AppOpsManager
import android.app.admin.DevicePolicyManager
import android.app.usage.UsageStatsManager
import android.content.ComponentName
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.Uri
import android.os.Build
import android.os.BatteryManager
import android.os.Process
import android.provider.MediaStore
import android.provider.Settings
import android.view.KeyEvent
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.content.pm.PackageManager
import com.solace.solace.live2d.Live2DPlugin
import com.solace.solace.live2d.Live2DStateManager
import com.solace.solace.live2d.Live2DEngineCache
import com.solace.solace.notification.NotificationStore
import com.solace.solace.accessibility.SolaceAccessibilityService
import com.solace.solace.accessibility.AccessibilityStateMonitor
import com.solace.solace.capture.MediaProjectionHolder
import com.solace.solace.capture.MediaProjectionCaptureManager
import com.solace.solace.capture.ScreenCaptureActivity
import com.solace.solace.service.SolaceDeviceController
import com.solace.solace.service.ShizukuShell
import rikka.shizuku.Shizuku
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject

class MainActivity : FlutterActivity() {
    companion object {
        private val PACKAGE_NAME_REGEX = Regex("^[A-Za-z][A-Za-z0-9_]*(?:\\.[A-Za-z0-9_]+)+$")
    }

    private var volumeChannel: MethodChannel? = null
    private var shizukuChannel: EventChannel? = null
    private var shizukuEventSink: EventChannel.EventSink? = null

    // Shizuku 状态跟踪
    @Volatile
    private var shizukuAvailable: Boolean = false
    @Volatile
    private var shizukuPermitted: Boolean = false

    // 待处理的权限请求回调
    private var pendingPermissionCallback: ((Boolean) -> Unit)? = null
    private var nextPermissionRequestCode: Int = 100

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // 预缓存 Live2D 悬浮窗引擎
        Live2DEngineCache.prepare(application)

        // ═══ Shizuku 生命周期初始化 ═══
        setupShizukuLifecycle()
    }

    override fun onDestroy() {
        // 清理 Shizuku 监听器
        try {
            Shizuku.removeBinderReceivedListener(shizukuBinderReceivedListener)
            Shizuku.removeBinderDeadListener(shizukuBinderDeadListener)
            Shizuku.removeRequestPermissionResultListener(shizukuPermissionResultListener)
        } catch (_: Exception) {}
        super.onDestroy()
    }

    // ═══ Shizuku 生命周期监听 ═══

    private val shizukuBinderReceivedListener = Shizuku.OnBinderReceivedListener {
        shizukuAvailable = true
        shizukuPermitted = Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED
        android.util.Log.i("MainActivity", "Shizuku binder received: available=$shizukuAvailable, permitted=$shizukuPermitted")
        // Binder 来了但未授权 → 自动触发请求
        if (shizukuAvailable && !shizukuPermitted) {
            android.util.Log.i("MainActivity", "Auto-requesting Shizuku permission")
            val requestCode = nextPermissionRequestCode++
            try { Shizuku.requestPermission(requestCode) } catch (_: Exception) {}
        }
        notifyShizukuStateChange()
    }

    private val shizukuBinderDeadListener = Shizuku.OnBinderDeadListener {
        shizukuAvailable = false
        shizukuPermitted = false
        android.util.Log.w("MainActivity", "Shizuku binder dead")
        notifyShizukuStateChange()
    }

    private val shizukuPermissionResultListener = Shizuku.OnRequestPermissionResultListener { requestCode, grantResult ->
        val granted = grantResult == PackageManager.PERMISSION_GRANTED
        shizukuPermitted = granted
        android.util.Log.i("MainActivity", "Shizuku permission result: code=$requestCode, granted=$granted")
        pendingPermissionCallback?.invoke(granted)
        pendingPermissionCallback = null
        notifyShizukuStateChange()
    }

    private fun setupShizukuLifecycle() {
        try {
            // 初始化 ShizukuShell（获取 IShizukuService binder 用于 newProcess）
            ShizukuShell.init()

            Shizuku.addBinderReceivedListener(shizukuBinderReceivedListener)
            Shizuku.addBinderDeadListener(shizukuBinderDeadListener)
            Shizuku.addRequestPermissionResultListener(shizukuPermissionResultListener)

            // 检查当前状态
            shizukuAvailable = try { Shizuku.pingBinder() } catch (_: Exception) { false }
            shizukuPermitted = if (shizukuAvailable) {
                try { Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED } catch (_: Exception) { false }
            } else false

            android.util.Log.i("MainActivity", "Shizuku init: available=$shizukuAvailable, permitted=$shizukuPermitted")

            // ═══ 关键：已运行但未授权 → 立即触发授权请求 ═══
            if (shizukuAvailable && !shizukuPermitted) {
                android.util.Log.i("MainActivity", "Shizuku running but not permitted — auto-requesting permission")
                val requestCode = nextPermissionRequestCode++
                Shizuku.requestPermission(requestCode)
                // 结果通过 shizukuPermissionResultListener 异步返回
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Shizuku setup failed", e)
        }
    }

    private fun notifyShizukuStateChange() {
        shizukuEventSink?.success(mapOf(
            "available" to shizukuAvailable,
            "permitted" to shizukuPermitted
        ))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // ═══ Shizuku 状态流（EventChannel — 推送到 Flutter）═══
        shizukuChannel = EventChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/shizuku_state"
        )
        shizukuChannel!!.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(args: Any?, events: EventChannel.EventSink?) {
                shizukuEventSink = events
                // 立即推送当前状态
                notifyShizukuStateChange()
            }
            override fun onCancel(args: Any?) {
                shizukuEventSink = null
            }
        })

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

        // ─── 作息陪伴 MethodChannel（本地，零外传；只做锁屏 + 使用时长感知） ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/wellbeing"
        ).setMethodCallHandler { call, result ->
            handleWellbeingMethodCall(call, result)
        }

        // ─── 通知监听 MethodChannel（读取手机通知，仅包名+标题+正文） ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/notification"
        ).setMethodCallHandler { call, result ->
            handleNotificationMethodCall(call, result)
        }

        // ─── 无障碍 MethodChannel（仅 UI 树读取与状态查询） ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/accessibility"
        ).setMethodCallHandler { call, result ->
            handleAccessibilityMethodCall(call, result)
        }

        // ─── 屏幕截图 MethodChannel（MediaProjection + VirtualDisplay） ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/screenshot"
        ).setMethodCallHandler { call, result ->
            handleScreenshotMethodCall(call, result)
        }

        // ─── 设备操控 MethodChannel（仅 Shizuku） ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/device"
        ).setMethodCallHandler { call, result ->
            handleDeviceMethodCall(call, result)
        }

        // ═══ Live2D 桌宠 MethodChannel（主 App 调用 showOverlay/hideOverlay/syncAvatarConfig 等）═══
        // 注意：MethodChannel 注册在主引擎，供主 App Dart 调用。
        // EventChannel 不在这里注册 — 已迁移到 Live2DEngineCache.kt 的独立引擎上，
        // 因为悬浮窗 Dart (live2d_entry.dart) 运行在独立引擎中，主引擎的 EventChannel 推送它收不到。
        Live2DPlugin.registerWith(flutterEngine.dartExecutor.binaryMessenger, this)
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

    // ─── 作息陪伴方法处理（本地锁屏 + 使用时长感知，零数据外传） ───

    private fun wellbeingAdmin(): ComponentName =
        ComponentName(this, WellbeingAdminReceiver::class.java)

    private fun handleWellbeingMethodCall(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        try {
            val dpm = getSystemService(Context.DEVICE_POLICY_SERVICE) as DevicePolicyManager
            when (call.method) {
                // 是否已授予「设备管理员（仅锁屏）」
                "isAdminActive" -> {
                    result.success(dpm.isAdminActive(wellbeingAdmin()))
                }
                // 拉起系统的设备管理员授权页（用户主动同意才生效）
                "requestAdmin" -> {
                    val intent = Intent(DevicePolicyManager.ACTION_ADD_DEVICE_ADMIN).apply {
                        putExtra(DevicePolicyManager.EXTRA_DEVICE_ADMIN, wellbeingAdmin())
                        putExtra(
                            DevicePolicyManager.EXTRA_ADD_EXPLANATION,
                            "授予后，Solace 才能在你设定的休息时段温柔地为你锁屏。仅锁屏，你用自己的密码即可解开，可随时在系统设置里撤销。"
                        )
                    }
                    startActivity(intent)
                    result.success(true)
                }
                // 本地触发锁屏（仅在已授权时可用）
                "lockNow" -> {
                    if (dpm.isAdminActive(wellbeingAdmin())) {
                        dpm.lockNow()
                        result.success(true)
                    } else {
                        result.error("NO_ADMIN", "设备管理员未授权", null)
                    }
                }
                // 是否已授予「使用情况访问」
                "hasUsageAccess" -> {
                    result.success(hasUsageStatsPermission())
                }
                // 拉起系统的「使用情况访问」授权页
                "requestUsageAccess" -> {
                    startActivity(Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS))
                    result.success(true)
                }
                // 查询最近 N 分钟的前台使用时长（按包名聚合，只有包名+毫秒时长）
                "queryUsage" -> {
                    if (!hasUsageStatsPermission()) {
                        result.error("NO_USAGE_ACCESS", "使用情况访问未授权", null)
                        return
                    }
                    val windowMinutes = call.argument<Int>("windowMinutes") ?: 30
                    result.success(queryForegroundUsage(windowMinutes))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("WELLBEING_ERROR", e.message, null)
        }
    }

    private fun hasUsageStatsPermission(): Boolean {
        return try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            } else {
                @Suppress("DEPRECATION")
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_GET_USAGE_STATS,
                    Process.myUid(),
                    packageName
                )
            }
            mode == AppOpsManager.MODE_ALLOWED
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 汇总最近 windowMinutes 分钟内各前台应用的使用时长。
     * 返回 {packageName, appName, totalMs, lastUsed}，不读取任何应用内文字/内容。
     */
    private fun queryForegroundUsage(windowMinutes: Int): String {
        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
        val pm = packageManager
        val end = System.currentTimeMillis()
        val begin = end - windowMinutes * 60_000L
        val stats = usm.queryUsageStats(
            UsageStatsManager.INTERVAL_BEST, begin, end
        ) ?: emptyList()
        val arr = JSONArray()
        for (s in stats) {
            if (s.totalTimeInForeground <= 0) continue
            val appName = try {
                val ai = pm.getApplicationInfo(s.packageName, 0)
                pm.getApplicationLabel(ai).toString()
            } catch (_: Exception) {
                s.packageName
            }
            arr.put(JSONObject().apply {
                put("packageName", s.packageName)
                put("appName", appName)
                put("totalMs", s.totalTimeInForeground)
                put("lastUsed", s.lastTimeUsed)
            })
        }
        return arr.toString()
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

    // ─── 通知监听方法处理 ───

    private fun handleNotificationMethodCall(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        try {
            when (call.method) {
                "hasNotificationAccess" -> {
                    result.success(hasNotificationAccess())
                }
                "requestNotificationAccess" -> {
                    try {
                        val intent = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
                            android.content.Intent(android.provider.Settings.ACTION_NOTIFICATION_LISTENER_SETTINGS)
                        } else {
                            android.content.Intent("android.settings.ACTION_NOTIFICATION_LISTENER_SETTINGS")
                        }
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_ERROR", e.message, null)
                    }
                }
                "getNotifications" -> {
                    if (!hasNotificationAccess()) {
                        result.error("NO_ACCESS", "通知使用权未授权", null)
                        return
                    }
                    val limit = call.argument<Int>("limit") ?: 20
                    val notifications = NotificationStore.snapshot(limit)
                    result.success(notifications)
                }
                "getNotificationCount" -> {
                    result.success(NotificationStore.count())
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("NOTIFICATION_ERROR", e.message, null)
        }
    }

    private fun hasNotificationAccess(): Boolean {
        val enabledListeners = try {
            android.provider.Settings.Secure.getString(
                contentResolver,
                "enabled_notification_listeners"
            ) ?: ""
        } catch (_: Exception) {
            return false
        }
        return enabledListeners.split(":")
            .mapNotNull { android.content.ComponentName.unflattenFromString(it) }
            .any { it.packageName == packageName }
    }

    // ─── 无障碍方法处理（仅 UI 读取与状态查询） ───

    private val a11yService: SolaceAccessibilityService?
        get() = SolaceAccessibilityService.instance

    private fun handleAccessibilityMethodCall(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        try {
            when (call.method) {
                "isEnabled" -> {
                    val dualResult = AccessibilityStateMonitor.performDualCheck(this@MainActivity)
                    result.success(dualResult.isServiceInstanceAlive)
                }
                "requestAccess" -> {
                    try {
                        val intent = android.content.Intent(
                            android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS
                        )
                        intent.flags = android.content.Intent.FLAG_ACTIVITY_NEW_TASK
                        startActivity(intent)
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_ERROR", e.message, null)
                    }
                }
                "performDualCheck" -> {
                    val dualResult = AccessibilityStateMonitor.performDualCheck(this@MainActivity)
                    result.success(mapOf(
                        "isSettingsEnabled" to dualResult.isSettingsEnabled,
                        "isServiceInList" to dualResult.isServiceInList,
                        "isServiceInstanceAlive" to dualResult.isServiceInstanceAlive,
                        "vendor" to dualResult.vendor.name,
                        "suggestedAction" to dualResult.suggestedAction.name
                    ))
                }
                "getKeepAliveStatus" -> {
                    val status = AccessibilityStateMonitor.getKeepAliveStatus(this@MainActivity)
                    result.success(mapOf(
                        "isBatteryOptimized" to status.isBatteryOptimized,
                        "isAutoStartLikelyOk" to status.isAutoStartLikelyOk,
                        "vendorFriendlyName" to status.vendorFriendlyName
                    ))
                }
                "isIgnoringBatteryOptimizations" -> {
                    result.success(
                        AccessibilityStateMonitor.isIgnoringBatteryOptimizations(this@MainActivity)
                    )
                }
                "openBatteryOptimizationSettings" -> {
                    result.success(
                        AccessibilityStateMonitor.openBatteryOptimizationSettings(this@MainActivity)
                    )
                }
                "openAutoStartSettings" -> {
                    result.success(
                        AccessibilityStateMonitor.openAutoStartSettings(this@MainActivity)
                    )
                }
                "openAppDetailsSettings" -> {
                    result.success(
                        AccessibilityStateMonitor.openAppDetailsSettings(this@MainActivity)
                    )
                }
                "getVendorInfo" -> {
                    val vendor = SolaceAccessibilityService.vendor
                    result.success(mapOf("vendor" to vendor.name))
                }
                "getUiHierarchy" -> {
                    val svc = a11yService
                    if (svc == null) {
                        result.error("NOT_ENABLED", "无障碍服务未启用", null)
                        return
                    }
                    result.success(svc.getUiHierarchy())
                }
                "getSimplifiedUiInfo" -> {
                    val svc = a11yService
                    if (svc == null) {
                        result.error("NOT_ENABLED", "无障碍服务未启用", null)
                        return
                    }
                    result.success(svc.getSimplifiedUiInfo())
                }
                "getCurrentApp" -> {
                    result.success(mapOf(
                        "packageName" to (SolaceAccessibilityService.currentPackageName ?: ""),
                        "activityName" to (SolaceAccessibilityService.currentActivityName ?: "")
                    ))
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("ACCESSIBILITY_ERROR", e.message, null)
        }
    }

    // ─── 屏幕截图方法处理 ───

    private var _captureManager: MediaProjectionCaptureManager? = null

    private fun handleScreenshotMethodCall(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        try {
            when (call.method) {
                "requestPermission" -> {
                    ScreenCaptureActivity.start(this)
                    result.success(true)
                }
                "hasPermission" -> {
                    result.success(MediaProjectionHolder.isReady)
                }
                "releasePermission" -> {
                    _captureManager?.release()
                    _captureManager = null
                    MediaProjectionHolder.clear(this)
                    result.success(true)
                }
                "capture" -> {
                    val mgr = getOrCreateManager()
                    if (mgr == null) {
                        result.error("NO_PERMISSION", "截图权限未授予", null)
                        return
                    }
                    val file = java.io.File(cacheDir, "screenshot_${System.currentTimeMillis()}.png")
                    val ok = mgr.captureToFile(file)
                    if (ok) {
                        val dims = mgr.captureDimensions()
                        result.success(mapOf(
                            "path" to file.absolutePath,
                            "width" to dims.first,
                            "height" to dims.second
                        ))
                    } else {
                        result.error("CAPTURE_FAILED", "截图失败", null)
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("SCREENSHOT_ERROR", e.message, null)
        }
    }

    private fun getOrCreateManager(): MediaProjectionCaptureManager? {
        if (!MediaProjectionHolder.isReady) return null

        val existing = _captureManager
        if (existing != null) return existing

        return try {
            MediaProjectionCaptureManager(this).also {
                it.setup()
                _captureManager = it
            }
        } catch (e: Exception) {
            android.util.Log.e("MainActivity", "Failed to initialize MediaProjection capture", e)
            null
        }
    }

    private fun isValidPackageName(packageName: String): Boolean {
        return PACKAGE_NAME_REGEX.matches(packageName)
    }

    // ─── 设备操控方法处理（仅 Shizuku） ───

    private fun handleDeviceMethodCall(
        call: MethodCall,
        result: MethodChannel.Result
    ) {
        val ctrl = SolaceDeviceController(this)

        try {
            when (call.method) {
                "isShizukuAvailable" -> {
                    shizukuAvailable = try { Shizuku.pingBinder() } catch (_: Exception) { false }
                    shizukuPermitted = if (shizukuAvailable) {
                        try {
                            Shizuku.checkSelfPermission() == PackageManager.PERMISSION_GRANTED &&
                                ShizukuShell.isReady()
                        } catch (_: Exception) { false }
                    } else false
                    result.success(mapOf(
                        "available" to shizukuAvailable,
                        "permitted" to shizukuPermitted
                    ))
                }
                "requestShizukuPermission" -> {
                    if (!shizukuAvailable) {
                        result.error("NO_SHIZUKU", "Shizuku服务未运行", null)
                        return
                    }
                    if (shizukuPermitted) {
                        result.success(true)
                        return
                    }
                    val requestCode = nextPermissionRequestCode++
                    try {
                        pendingPermissionCallback = { granted ->
                            notifyShizukuStateChange()
                        }
                        Shizuku.requestPermission(requestCode)
                        result.success(null)
                    } catch (e: Exception) {
                        pendingPermissionCallback = null
                        result.success(false)
                    }
                }
                "tap" -> {
                    val x = call.argument<Int>("x") ?: 0
                    val y = call.argument<Int>("y") ?: 0
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法执行点击", null)
                        return
                    }
                    Thread {
                        try {
                            val r = runBlocking { ctrl.inputTap(x, y) }
                            Handler(Looper.getMainLooper()).post { result.success(r.success) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "swipe" -> {
                    val sx = call.argument<Int>("startX") ?: 0
                    val sy = call.argument<Int>("startY") ?: 0
                    val ex = call.argument<Int>("endX") ?: 0
                    val ey = call.argument<Int>("endY") ?: 0
                    val duration = call.argument<Int>("duration") ?: 300
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法执行滑动", null)
                        return
                    }
                    Thread {
                        try {
                            val r = runBlocking { ctrl.inputSwipe(sx, sy, ex, ey, duration) }
                            Handler(Looper.getMainLooper()).post { result.success(r.success) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "pressKey" -> {
                    val keyCode = call.argument<Int>("keyCode") ?: 0
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法执行按键", null)
                        return
                    }
                    Thread {
                        try {
                            val r = runBlocking { ctrl.inputKeyEvent(keyCode) }
                            Handler(Looper.getMainLooper()).post { result.success(r.success) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "inputText" -> {
                    val text = call.argument<String>("text") ?: ""
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法输入文本", null)
                        return
                    }
                    Thread {
                        try {
                            val r = runBlocking { ctrl.inputText(text) }
                            Handler(Looper.getMainLooper()).post { result.success(r.success) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "shellScreenshot" -> {
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法使用shell截图", null)
                        return
                    }
                    Thread {
                        try {
                            val cacheRoot = externalCacheDir?.absolutePath ?: cacheDir.absolutePath
                            val path = "$cacheRoot/shell_ss_${System.currentTimeMillis()}.png"
                            val r = runBlocking { ctrl.screencap(path) }
                            Handler(Looper.getMainLooper()).post {
                                result.success(if (r.success) path else null)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(null) }
                        }
                    }.start()
                }
                "toggleWifi" -> {
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法控制WiFi", null)
                        return
                    }
                    val enable = call.argument<Boolean>("enable") ?: true
                    Thread {
                        try {
                            val cmd = if (enable) "svc wifi enable" else "svc wifi disable"
                            val r = runBlocking { ctrl.executeShell(cmd) }
                            if (!r.success) {
                                val cmd2 = if (enable) "cmd wifi set-wifi-enabled enabled" else "cmd wifi set-wifi-enabled disabled"
                                val r2 = runBlocking { ctrl.executeShell(cmd2) }
                                Handler(Looper.getMainLooper()).post { result.success(r2.success) }
                            } else {
                                Handler(Looper.getMainLooper()).post { result.success(true) }
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "toggleBluetooth" -> {
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法控制蓝牙", null)
                        return
                    }
                    val enable = call.argument<Boolean>("enable") ?: true
                    Thread {
                        try {
                            val cmd = if (enable) "svc bluetooth enable" else "svc bluetooth disable"
                            val r = runBlocking { ctrl.executeShell(cmd) }
                            Handler(Looper.getMainLooper()).post { result.success(r.success) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "setBrightness" -> {
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法调节亮度", null)
                        return
                    }
                    val level = call.argument<Int>("level") ?: 128
                    Thread {
                        try {
                            val r = runBlocking { ctrl.executeShell("settings put system screen_brightness $level") }
                            Handler(Looper.getMainLooper()).post { result.success(r.success) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "startApp" -> {
                    val targetPackage = call.argument<String>("packageName") ?: ""
                    if (!isValidPackageName(targetPackage)) {
                        result.error("INVALID_ARG", "packageName 格式无效", null)
                        return
                    }
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法打开应用", null)
                        return
                    }
                    Thread {
                        try {
                            val r = ShizukuShell.exec("monkey -p $targetPackage -c android.intent.category.LAUNCHER 1")
                            Handler(Looper.getMainLooper()).post { result.success(r.exitCode == 0) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "exitApp" -> {
                    val targetPackage = call.argument<String>("packageName") ?: ""
                    if (!isValidPackageName(targetPackage)) {
                        result.error("INVALID_ARG", "packageName 格式无效", null)
                        return
                    }
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法退出应用", null)
                        return
                    }
                    Thread {
                        try {
                            val stopped = ShizukuShell.exec("am force-stop $targetPackage")
                            val home = ShizukuShell.exec("input keyevent KEYCODE_HOME")
                            Handler(Looper.getMainLooper()).post {
                                result.success(stopped.exitCode == 0 && home.exitCode == 0)
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "lockScreen" -> {
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法锁屏", null)
                        return
                    }
                    Thread {
                        try {
                            val r = ShizukuShell.exec("input keyevent 26")
                            Handler(Looper.getMainLooper()).post { result.success(r.exitCode == 0) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "adjustVolume" -> {
                    val up = call.argument<Boolean>("up") ?: true
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法调节音量", null)
                        return
                    }
                    Thread {
                        try {
                            val keyCode = if (up) 24 else 25
                            val r = ShizukuShell.exec("input keyevent $keyCode")
                            Handler(Looper.getMainLooper()).post { result.success(r.exitCode == 0) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "setMuteMode" -> {
                    val ringerMode = call.argument<Int>("ringerMode") ?: 2
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法设置静音模式", null)
                        return
                    }
                    Thread {
                        try {
                            val mode = if (ringerMode == 0) 0 else 2
                            var r = ShizukuShell.exec("cmd audio set-ringer-mode $mode")
                            if (r.exitCode != 0) {
                                r = ShizukuShell.exec(
                                    if (mode == 0) "cmd notification set_dnd priority" else "cmd notification set_dnd off"
                                )
                            }
                            Handler(Looper.getMainLooper()).post { result.success(r.exitCode == 0) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "openGallery" -> {
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用，无法打开相册", null)
                        return
                    }
                    Thread {
                        try {
                            val pkgs = listOf(
                                "com.android.gallery3d", "com.google.android.apps.photos",
                                "com.miui.gallery", "com.sec.android.gallery3d",
                                "com.huawei.photos", "com.oppo.gallery3d"
                            )
                            var ok = false
                            for (pkg in pkgs) {
                                val r = ShizukuShell.exec("monkey -p $pkg -c android.intent.category.LAUNCHER 1")
                                if (r.exitCode == 0) { ok = true; break }
                            }
                            if (!ok) {
                                val r = ShizukuShell.exec("am start -a android.intent.action.VIEW -t image/*")
                                ok = r.exitCode == 0
                            }
                            Handler(Looper.getMainLooper()).post { result.success(ok) }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post { result.success(false) }
                        }
                    }.start()
                }
                "getAppUsageTime" -> {
                    val requestedPkg = call.argument<String>("packageName")
                    val sinceHours = call.argument<Int>("sinceHours") ?: 24
                    val limit = call.argument<Int>("limit") ?: 10
                    val includeSystem = call.argument<Boolean>("includeSystemApps") ?: false

                    try {
                        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
                            result.error("UNSUPPORTED", "需要 Android 5.0+", null)
                            return
                        }

                        // 检查 UsageStats 权限
                        val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
                        val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                            appOps.unsafeCheckOpNoThrow(
                                AppOpsManager.OPSTR_GET_USAGE_STATS,
                                Process.myUid(), packageName
                            )
                        } else {
                            @Suppress("DEPRECATION")
                            appOps.checkOpNoThrow(
                                AppOpsManager.OPSTR_GET_USAGE_STATS,
                                Process.myUid(), packageName
                            )
                        }

                        if (mode != AppOpsManager.MODE_ALLOWED) {
                            // 打开使用情况访问设置页面
                            try {
                                val intent = Intent(Settings.ACTION_USAGE_ACCESS_SETTINGS).apply {
                                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                }
                                startActivity(intent)
                            } catch (_: Exception) {}
                            result.error("NO_PERMISSION", "需要「使用情况访问」权限，已打开设置页面", null)
                            return
                        }

                        val endTime = System.currentTimeMillis()
                        val startTime = endTime - sinceHours * 60L * 60L * 1000L
                        val usm = getSystemService(Context.USAGE_STATS_SERVICE) as UsageStatsManager
                        val rawStats = usm.queryUsageStats(
                            UsageStatsManager.INTERVAL_DAILY, startTime, endTime
                        ) ?: emptyList()

                        val aggregated = rawStats
                            .groupBy { it.packageName.orEmpty() }
                            .mapNotNull { (pkg, stats) ->
                                if (pkg.isBlank()) return@mapNotNull null
                                val totalMs = stats.sumOf { it.totalTimeInForeground }
                                if (totalMs <= 0L) return@mapNotNull null
                                val lastUsed = stats.maxOfOrNull { it.lastTimeUsed } ?: 0L

                                val appInfo = try {
                                    packageManager.getApplicationInfo(pkg, 0)
                                } catch (_: PackageManager.NameNotFoundException) { null }

                                val isSystem = appInfo?.let {
                                    (it.flags and android.content.pm.ApplicationInfo.FLAG_SYSTEM) != 0
                                } ?: false

                                if (requestedPkg == null && !includeSystem && isSystem) return@mapNotNull null
                                if (requestedPkg != null && requestedPkg != pkg) return@mapNotNull null

                                val appName = appInfo?.let {
                                    try { it.loadLabel(packageManager).toString() } catch (_: Exception) { pkg }
                                } ?: pkg

                                mapOf(
                                    "packageName" to pkg,
                                    "appName" to appName,
                                    "totalForegroundTimeMs" to totalMs,
                                    "lastTimeUsed" to lastUsed,
                                    "isSystemApp" to isSystem
                                )
                            }
                            .sortedByDescending { it["totalForegroundTimeMs"] as Long }

                        val entries = if (requestedPkg != null) aggregated.take(1) else aggregated.take(limit)

                        result.success(mapOf(
                            "success" to true,
                            "sinceHours" to sinceHours,
                            "totalEntries" to entries.size,
                            "entries" to entries
                        ))
                    } catch (e: SecurityException) {
                        result.error("SECURITY", "安全异常: ${e.message}", null)
                    } catch (e: Exception) {
                        result.error("ERROR", e.message ?: "读取使用时间失败", null)
                    }
                }
                "shellExec" -> {
                    val command = call.argument<String>("command") ?: ""
                    if (command.isEmpty()) {
                        result.error("INVALID_ARG", "command 为空", null)
                        return
                    }
                    if (!ctrl.isShizukuReady()) {
                        result.error("NO_SHIZUKU", "Shizuku不可用", null)
                        return
                    }
                    Thread {
                        try {
                            val r = ShizukuShell.exec(command)
                            Handler(Looper.getMainLooper()).post {
                                result.success(mapOf(
                                    "exitCode" to r.exitCode,
                                    "stdout" to r.stdout,
                                    "stderr" to r.stderr
                                ))
                            }
                        } catch (e: Exception) {
                            Handler(Looper.getMainLooper()).post {
                                result.success(mapOf(
                                    "exitCode" to -1,
                                    "stdout" to "",
                                    "stderr" to (e.message ?: "unknown error")
                                ))
                            }
                        }
                    }.start()
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("DEVICE_ERROR", e.message, null)
        }
    }

}
