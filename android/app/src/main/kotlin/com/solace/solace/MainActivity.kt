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
import android.graphics.Color
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import android.os.Environment
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
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
        // Flutter's saved theme preference is available before the first frame.
        // Match the native launch window to it so dark mode never flashes white.
        applySavedLaunchBackground()
        super.onCreate(savedInstanceState)

        // ═══ Shizuku 生命周期初始化 ═══
        setupShizukuLifecycle()
    }

    private fun applySavedLaunchBackground() {
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val themeMode = prefs.getString("flutter.app_theme_mode", null)
        val isDark = themeMode == "2" ||
            (themeMode != "1" && (resources.configuration.uiMode and
                android.content.res.Configuration.UI_MODE_NIGHT_MASK) ==
                android.content.res.Configuration.UI_MODE_NIGHT_YES)
        val background = if (isDark) Color.rgb(16, 17, 20) else Color.rgb(247, 248, 250)
        window.setBackgroundDrawable(android.graphics.drawable.ColorDrawable(background))
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

        // ─── 音频格式转换（mp3/m4a 等 → 16-bit PCM wav，供音色克隆参考音频用） ───
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "com.solace.solace/audio"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "convertToWav" -> {
                    // 解码耗时秒级~数十秒：必须在后台线程执行，否则主线程被
                    // 占死 → UI 卡死（ANR）。MethodChannel 的 result 可跨线程调用。
                    Thread {
                        try {
                            val inputPath = call.argument<String>("inputPath") ?: ""
                            val out = convertAudioToWav(inputPath)
                            result.success(out)
                        } catch (e: Exception) {
                            result.error("CONVERT_ERROR", e.message, null)
                        }
                    }.start()
                }
                "normalizeReferenceAudio" -> {
                    // 参考音频规范化：24kHz 单声道 ≤N 秒（音色克隆专用）。
                    // 同样必须后台线程（解码可能几十秒）。
                    Thread {
                        try {
                            val inputPath = call.argument<String>("inputPath") ?: ""
                            val maxSeconds = call.argument<Int>("maxSeconds") ?: 6
                            val out = normalizeReferenceAudio(inputPath, maxSeconds)
                            result.success(out)
                        } catch (e: Exception) {
                            result.error("CONVERT_ERROR", e.message, null)
                        }
                    }.start()
                }
                "voiceSimilarity" -> {
                    // 音色相似度：对比参考音频与合成音频的频带能量分布（B 方案）。
                    // 漂移检测用：合成后算分，低于阈值则重合成。后台线程执行。
                    Thread {
                        try {
                            val refPath = call.argument<String>("refPath") ?: ""
                            val synPath = call.argument<String>("synPath") ?: ""
                            val score = voiceSimilarity(refPath, synPath)
                            result.success(score)
                        } catch (e: Exception) {
                            result.error("SIM_ERROR", e.message, null)
                        }
                    }.start()
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

    // ─── 音频转换：mp3/m4a/aac/ogg/flac → 16-bit 单声道 PCM wav ───

    /**
     * 用系统 MediaExtractor + MediaCodec 解码任意 Android 支持的音频文件，
     * 重混为单声道 16-bit PCM 并写出 wav。
     * 输出优先存到公共下载目录 Download/Solace/（有权限时），否则落到应用外部缓存目录。
     */
private fun convertAudioToWav(inputPath: String): Map<String, Any?> {
        val d = decodeAudioToPcm16(inputPath)
        val stereo = if (d.channelCount == 2) d.pcm
            else upmixToStereo(d.pcm, d.channelCount)
        // MOSS codec encode 参考音频要求 48kHz 双声道 16-bit PCM（与录制路径一致）。
        // 非 48kHz 源（如 44.1kHz mp3）用 Lanczos-3 低通重采样，避免混叠。
        val stereo48k = resampleTo(stereo, d.sampleRate, 48000)

        val outFile = File(writableAudioDir(), "voice_ref_${System.currentTimeMillis()}.wav")
        writeWavFile(outFile, stereo48k, 48000, 2)

        return mapOf(
            "path" to outFile.absolutePath,
            "sampleRate" to 48000,
            "durationMs" to (stereo48k.size.toLong() * 1000L / (48000 * 4L))
        )
    }

    /**
     * 参考音频规范化：任意音频（mp3/wav/录音）→ 24kHz 单声道 16-bit PCM，
     * 切除头部静音后截取前 [maxSeconds] 秒，写 wav。
     *
     * MiMo voiceclone 官方仅保证「短至几秒即可」的参考音频，且 24kHz 单声道
     * 与其输出规格及内置默认音色对齐。超长（30s+）或立体声参考样本会令
     * 克隆音色严重偏移、人机感重——这是音色克隆质量问题的头号根源。
     */
    private fun normalizeReferenceAudio(inputPath: String, maxSeconds: Int): Map<String, Any?> {
        val d = decodeAudioToPcm16(inputPath)
        val mono = downmixToMono(d.pcm, d.channelCount)
        val mono24k = resampleTo(mono, d.sampleRate, 24000)
        // 挑「最像说话的」连续语音段（能量分段），而非硬取头部——头部
        // 可能是静音/音乐/开场白，会让克隆音色偏移、人机感重
        val picked = pickBestSpeechSegment(mono24k, maxSeconds)
        val outFile = File(writableAudioDir(), "voice_ref_${System.currentTimeMillis()}.wav")
        writeWavFile(outFile, picked, 24000, 1)
        return mapOf(
            "path" to outFile.absolutePath,
            "sampleRate" to 24000,
            "durationMs" to (picked.size.toLong() * 1000L / 48000L)
        )
    }

    /**
     * 能量分段选段：按 20ms 块计算 RMS，连续活动块组成语音段（≤0.5s 间隙
     * 合并为段内停顿）。优先取时长 2.5~8s、语音密度最高的段（超长段给
     * 0.5 倍惩罚，避免整段 BGM/长段讲话压过干净的人声段）；没有 ≥2.5s
     * 的段时取最长段；再不行回退切头静音取前 [maxSeconds]。
     */
    private fun pickBestSpeechSegment(pcm24k: ByteArray, maxSeconds: Int): ByteArray {
        val samples = pcm24k.size / 2
        if (samples <= 0) return pcm24k

        val block = 480 // 20ms @ 24kHz
        val nBlocks = samples / block
        val active = BooleanArray(nBlocks)
        for (b in 0 until nBlocks) {
            var sum = 0L
            for (i in b * block until (b + 1) * block) {
                val lo = pcm24k[i * 2].toInt() and 0xFF
                val hi = pcm24k[i * 2 + 1].toInt() and 0xFF
                val s = ((hi shl 8) or lo).toShort().toInt()
                sum += (s * s).toLong()
            }
            val rms = Math.sqrt(sum.toDouble() / block)
            active[b] = rms >= 500.0 // ≈ -36dBFS，安静环境与说话声的分界
        }

        // 合并连续活动块为语音段
        val runs = ArrayList<IntArray>() // [startBlock, endBlock, activeCount]
        val maxGap = 25 // 0.5s 静音间隙
        var b = 0
        while (b < nBlocks) {
            if (!active[b]) { b++; continue }
            val start = b
            var lastActive = b
            var count = 0
            while (b < nBlocks) {
                if (active[b]) { lastActive = b; count++ } else {
                    var gap = 1
                    while (b + gap < nBlocks && !active[b + gap] && gap < maxGap) gap++
                    if (b + gap >= nBlocks || gap >= maxGap) break
                    b += gap
                }
                b++
            }
            runs.add(intArrayOf(start, lastActive + 1, count))
        }
        if (runs.isEmpty()) return trimLeadingSilenceAndCap(pcm24k, maxSeconds)

        // 选段：优先 2.5~8s、密度最高；超长段惩罚 0.5
        var best: IntArray? = null
        var bestScore = 0.0
        for (r in runs) {
            val durSec = (r[1] - r[0]) * 20.0 / 1000.0
            if (durSec < 2.5) continue
            val density = r[2].toDouble() / (r[1] - r[0])
            val score = if (durSec <= 8.0) density else density * 0.5
            if (best == null || score > bestScore) { best = r; bestScore = score }
        }
        if (best == null) {
            // 全部不足 2.5s：取最长的一段
            var longest: IntArray? = null
            for (r in runs) {
                if (longest == null || (r[1] - r[0]) > (longest[1] - longest[0])) longest = r
            }
            best = longest
        }
        if (best == null) return trimLeadingSilenceAndCap(pcm24k, maxSeconds)

        var startSample = best[0] * block
        val maxSamples = maxSeconds * 24000
        var endSample = Math.min(best[1] * block, startSample + maxSamples)
        if (endSample <= startSample) return trimLeadingSilenceAndCap(pcm24k, maxSeconds)
        val out = ByteArray((endSample - startSample) * 2)
        System.arraycopy(pcm24k, startSample * 2, out, 0, out.size)
        return denoiseHighpass(out)
    }

    /**
     * 参考音频降噪（A1）：高通滤波（削 80Hz 以下低频轰鸣/电流声）+ 噪声门限
     * （RMS < -50dBFS 的采样块拉静音，削环境底噪/空调声）。
     * MiMo voiceclone 对参考音频里的背景噪声极敏感——底噪特征会被克隆进
     * 音色，是音色漂移、人机感的重要来源。纯 Kotlin 实现，零第三方依赖。
     */
    private fun denoiseHighpass(pcm16: ByteArray): ByteArray {
        val n = pcm16.size / 2
        if (n < 512) return pcm16
        val samples = ShortArray(n)
        for (i in 0 until n) {
            val lo = pcm16[i * 2].toInt() and 0xFF
            val hi = pcm16[i * 2 + 1].toInt() and 0xFF
            samples[i] = ((hi shl 8) or lo).toShort()
        }
        // 一阶高通：y[i] = a * (x[i] - x[i-1] + y[i-1])，a≈0.996 @24kHz 截止~80Hz
        val a = 0.996f
        var prevX = 0f
        var prevY = 0f
        for (i in 0 until n) {
            val x = samples[i].toFloat()
            val y = a * (prevY + x - prevX)
            samples[i] = y.coerceIn(-32768f, 32767f).toInt().toShort()
            prevX = x
            prevY = y
        }
        // 噪声门限：20ms 块 RMS < 阈值（-50dBFS ≈ 3.3/32768）→ 拉静音
        val block = 480 // 20ms @ 24kHz
        val threshold = 3.3f
        var b = 0
        while (b < n) {
            val end = Math.min(b + block, n)
            var sum = 0L
            for (i in b until end) {
                val s = samples[i].toInt()
                sum += s.toLong() * s
            }
            val rms = Math.sqrt(sum.toDouble() / (end - b))
            if (rms < threshold) {
                for (i in b until end) samples[i] = 0
            }
            b = end
        }
        val out = ByteArray(n * 2)
        for (i in 0 until n) {
            val s = samples[i].toInt()
            out[i * 2] = (s and 0xFF).toByte()
            out[i * 2 + 1] = ((s shr 8) and 0xFF).toByte()
        }
        return out
    }

    private class DecodedPcm(val pcm: ByteArray, val sampleRate: Int, val channelCount: Int)

    /**
     * 音色相似度（B 方案）：对比参考音频与合成音频的频带能量分布。
     * 两段音频各自解码 → 重采样 16kHz 单声道 → 分帧(20ms) → FFT → 按
     * 梅尔近似频带统计能量 → 归一化后算余弦相似度。0~1，>0.85 视为同音色。
     *
     * MiMo voiceclone 每次合成独立采样，音色有随机漂移；漂移严重时频谱
     * 分布明显偏离参考。客户端拿不准时重合成（最多 N 次），把「漂移」变
     * 成「检测→重试」闭环。纯 Kotlin 自实现 FFT，零第三方依赖。
     */
    private fun voiceSimilarity(refPath: String, synPath: String): Double {
        val ref = decodeAudioToPcm16(refPath)
        val syn = decodeAudioToPcm16(synPath)
        val ref16k = resampleTo(downmixToMono(ref.pcm, ref.channelCount), ref.sampleRate, 16000)
        val syn16k = resampleTo(downmixToMono(syn.pcm, syn.channelCount), syn.sampleRate, 16000)
        val refFeat = bandEnergyFeature(ref16k)
        val synFeat = bandEnergyFeature(syn16k)
        return cosineSimilarity(refFeat, synFeat)
    }

    /** 16kHz 单声道 → 梅尔近似 24 频带能量向量（20ms 帧，取全段均值）。 */
    private fun bandEnergyFeature(pcm16k: ByteArray): FloatArray {
        val n = pcm16k.size / 2
        val fftSize = 512 // 32ms @16kHz
        val nFrames = Math.max(1, n / fftSize)
        val feat = FloatArray(24)
        val hann = FloatArray(fftSize)
        for (i in 0 until fftSize) hann[i] = 0.5f - 0.5f * Math.cos(2.0 * Math.PI * i / fftSize).toFloat()
        val frame = FloatArray(fftSize)
        val re = FloatArray(fftSize)
        val im = FloatArray(fftSize)
        for (f in 0 until nFrames) {
            val base = f * fftSize
            for (i in 0 until fftSize) {
                val lo = pcm16k[(base + i) * 2].toInt() and 0xFF
                val hi = pcm16k[(base + i) * 2 + 1].toInt() and 0xFF
                frame[i] = (((hi shl 8) or lo).toShort().toFloat() / 32768f) * hann[i]
            }
            System.arraycopy(frame, 0, re, 0, fftSize)
            java.util.Arrays.fill(im, 0f)
            fftRadix2(re, im)
            // 24 梅尔近似频带（16kHz 上限 8kHz，mel 间隔指数增长）
            for (b in 0 until 24) {
                val loBin = Math.min(fftSize / 2, (melFreq(b) * fftSize / 16000.0).toInt())
                val hiBin = Math.min(fftSize / 2, Math.max(loBin + 1, (melFreq(b + 1) * fftSize / 16000.0).toInt()))
                var e = 0.0
                for (k in loBin until hiBin) e += re[k] * re[k] + im[k] * im[k]
                feat[b] += (e / (hiBin - loBin)).toFloat()
            }
        }
        for (b in 0 until 24) feat[b] /= nFrames
        return feat
    }

    private fun melFreq(m: Int): Double = 700.0 * (Math.pow(10.0, m / 24.0 * Math.log10(1.0 + 8000.0 / 700.0)) - 1.0)

    /** 基-2 迭代 FFT（原地，size 必须为 2 的幂）。 */
    private fun fftRadix2(re: FloatArray, im: FloatArray) {
        val n = re.size
        var j = 0
        for (i in 1 until n) {
            var bit = n shr 1
            while (j and bit != 0) { j = j xor bit; bit = bit shr 1 }
            j = j xor bit
            if (i < j) {
                var t = re[i]; re[i] = re[j]; re[j] = t
                t = im[i]; im[i] = im[j]; im[j] = t
            }
        }
        var len = 2
        while (len <= n) {
            val ang = -2.0 * Math.PI / len
            val wRe = Math.cos(ang).toFloat()
            val wIm = Math.sin(ang).toFloat()
            for (i in 0 until n step len) {
                var curRe = 1f
                var curIm = 0f
                for (k in 0 until len / 2) {
                    val uRe = re[i + k]
                    val uIm = im[i + k]
                    val vRe = re[i + k + len / 2] * curRe - im[i + k + len / 2] * curIm
                    val vIm = re[i + k + len / 2] * curIm + im[i + k + len / 2] * curRe
                    re[i + k] = uRe + vRe
                    im[i + k] = uIm + vIm
                    re[i + k + len / 2] = uRe - vRe
                    im[i + k + len / 2] = uIm - vIm
                    val nRe = curRe * wRe - curIm * wIm
                    curIm = curRe * wIm + curIm * wRe
                    curRe = nRe
                }
            }
            len = len shl 1
        }
    }

    private fun cosineSimilarity(a: FloatArray, b: FloatArray): Double {
        var dot = 0.0; var na = 0.0; var nb = 0.0
        for (i in a.indices) { dot += a[i] * b[i]; na += a[i] * a[i]; nb += b[i] * b[i] }
        if (na == 0.0 || nb == 0.0) return 0.0
        return dot / (Math.sqrt(na) * Math.sqrt(nb))
    }

    /** 解码任意音频为 16-bit PCM（原始采样率/声道）。超长输入的防护在循环内。 */
    private fun decodeAudioToPcm16(inputPath: String): DecodedPcm {
        val src = File(inputPath)
        if (!src.exists()) throw Exception("源文件不存在: $inputPath")
        // 上限保护：解码是内存全量 PCM，超长输入会 OOM 闪退。
        if (src.length() > 20L * 1024 * 1024)
            throw Exception("音频文件过大（>20MB），请先裁剪到 3~5 秒再导入")

        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        val pcm = ByteArrayOutputStream()
        try {
            extractor.setDataSource(inputPath)

            var trackIndex = -1
            var mime = ""
            var sampleRate = 44100
            var channelCount = 2
            for (i in 0 until extractor.trackCount) {
                val fmt = extractor.getTrackFormat(i)
                val m = fmt.getString(MediaFormat.KEY_MIME) ?: ""
                if (m.startsWith("audio/")) {
                    trackIndex = i
                    mime = m
                    if (fmt.containsKey(MediaFormat.KEY_SAMPLE_RATE))
                        sampleRate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    if (fmt.containsKey(MediaFormat.KEY_CHANNEL_COUNT))
                        channelCount = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    break
                }
            }
            if (trackIndex < 0) throw Exception("没有找到音频轨道")

            extractor.selectTrack(trackIndex)
            val format = extractor.getTrackFormat(trackIndex)
            decoder = MediaCodec.createDecoderByType(mime)
            decoder.configure(format, null, null, 0)
            decoder.start()

            val info = MediaCodec.BufferInfo()
            var inputDone = false
            var outputDone = false

            while (!outputDone) {
                if (!inputDone) {
                    val inIndex = decoder.dequeueInputBuffer(10_000)
                    if (inIndex >= 0) {
                        val buf = decoder.getInputBuffer(inIndex)!!
                        val size = extractor.readSampleData(buf, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(
                                inIndex, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM
                            )
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inIndex, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                val outIndex = decoder.dequeueOutputBuffer(info, 10_000)
                when {
                    outIndex >= 0 -> {
                        if (info.size > 0) {
                            val buf = decoder.getOutputBuffer(outIndex)!!
                            buf.position(info.offset)
                            buf.limit(info.offset + info.size)
                            val chunk = ByteArray(info.size)
                            buf.get(chunk)
                            pcm.write(chunk)
                            // 解码中即时拦截超长输出，避免内存持续膨胀 OOM。
                            // （32MB PCM ≈ 173 秒 @48kHz 立体声）
                            if (pcm.size() > 32 * 1024 * 1024)
                                throw Exception("音频过长（解码后超过约 3 分钟），请先裁剪到 3~5 秒再导入")
                        }
                        decoder.releaseOutputBuffer(outIndex, false)
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) {
                            outputDone = true
                        }
                    }
                    outIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                        val newFormat = decoder.outputFormat
                        if (newFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE))
                            sampleRate = newFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                        if (newFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT))
                            channelCount = newFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    }
                }
            }
            return DecodedPcm(pcm.toByteArray(), sampleRate, channelCount)
        } finally {
            try { decoder?.stop() } catch (_: Exception) {}
            try { decoder?.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
        }
    }

    private fun writableAudioDir(): File {
        // 优先公共下载目录（用户可见、有权限时）；失败则回退到应用外部缓存目录。
        return try {
            val public = File(
                Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS),
                "Solace"
            )
            public.mkdirs()
            val probe = File(public, ".w_${System.currentTimeMillis()}")
            probe.createNewFile()
            probe.delete()
            public
        } catch (_: Exception) {
            externalCacheDir ?: cacheDir
        }
    }

    /**
     * Lanczos-3 窗口 sinc 低通重采样：任意采样率 -> [dstRate]。
     * 已是目标采样率时原样返回。
     */
    private fun resampleTo(pcm16: ByteArray, srcRate: Int, dstRate: Int): ByteArray {
        if (srcRate == dstRate) return pcm16
        val n = pcm16.size / 2
        if (n == 0) return pcm16
        val src = ShortArray(n)
        for (i in 0 until n) {
            val lo = pcm16[i * 2].toInt() and 0xFF
            val hi = pcm16[i * 2 + 1].toInt() and 0xFF
            src[i] = ((hi shl 8) or lo).toShort()
        }
        val ratio = srcRate.toDouble() / dstRate.toDouble()
        val outLen = (n / ratio).toInt()
        val out = ShortArray(outLen)
        val a = 3
        for (i in 0 until outLen) {
            val center = i * ratio
            val i0 = Math.floor(center - a).toInt()
            val i1 = Math.ceil(center + a).toInt()
            var sum = 0.0
            var norm = 0.0
            for (j in i0..i1) {
                if (j < 0 || j >= n) continue
                val w = lanczosWeight(j - center, a)
                sum += src[j].toDouble() * w
                norm += w
            }
            val v = if (norm != 0.0) sum / norm else 0.0
            out[i] = v.toInt().coerceIn(-32768, 32767).toShort()
        }
        val bytes = ByteArray(outLen * 2)
        for (i in 0 until outLen) {
            bytes[i * 2] = (out[i].toInt() and 0xFF).toByte()
            bytes[i * 2 + 1] = ((out[i].toInt() shr 8) and 0xFF).toByte()
        }
        return bytes
    }

    /** 多声道 -> 单声道（取前两声道平均）。 */
    private fun downmixToMono(pcm: ByteArray, channels: Int): ByteArray {
        if (channels <= 0) throw Exception("音频声道信息异常（channels=$channels），无法转换")
        if (channels == 1) return pcm
        val frames = pcm.size / (channels * 2)
        val mono = ByteArray(frames * 2)
        for (f in 0 until frames) {
            val i0 = (f * channels) * 2
            val i1 = i0 + 2
            val lo0 = pcm[i0].toInt() and 0xFF
            val hi0 = pcm[i0 + 1].toInt() and 0xFF
            val lo1 = pcm[i1].toInt() and 0xFF
            val hi1 = pcm[i1 + 1].toInt() and 0xFF
            val s0 = ((hi0 shl 8) or lo0).toShort().toInt()
            val s1 = ((hi1 shl 8) or lo1).toShort().toInt()
            val m = (s0 + s1) / 2
            mono[f * 2] = (m and 0xFF).toByte()
            mono[f * 2 + 1] = ((m shr 8) and 0xFF).toByte()
        }
        return mono
    }

    /**
     * 切除头部静音（10ms 块峰值 < 300/32768 ≈ -40dBFS 视为静音），
     * 然后截取前 [maxSeconds] 秒。短于上限的原样保留（不足 6 秒不补长）。
     */
    private fun trimLeadingSilenceAndCap(mono24k: ByteArray, maxSeconds: Int): ByteArray {
        val samples = mono24k.size / 2
        if (samples == 0) return mono24k
        val blockSize = 240 // 10ms @ 24kHz
        var start = 0
        while (start + blockSize <= samples) {
            var peak = 0
            for (i in start until start + blockSize) {
                val lo = mono24k[i * 2].toInt() and 0xFF
                val hi = mono24k[i * 2 + 1].toInt() and 0xFF
                val s = ((hi shl 8) or lo).toShort().toInt()
                if (Math.abs(s) > peak) peak = Math.abs(s)
            }
            if (peak >= 300) break
            start += blockSize
        }
        val maxSamples = maxSeconds * 24000
        val end = Math.min(samples, start + maxSamples)
        val out = ByteArray((end - start) * 2)
        System.arraycopy(mono24k, start * 2, out, 0, out.size)
        return out
    }

    /** Lanczos-a 窗口：sinc(x) * sinc(x/a)，|x| >= a 时为 0。 */
    private fun lanczosWeight(x: Double, a: Int): Double {
        if (x == 0.0) return 1.0
        if (Math.abs(x) >= a) return 0.0
        val px = Math.PI * x
        return (a * Math.sin(px) * Math.sin(px / a)) / (px * px)
    }

    /** 多声道 -> 双声道（取前 2 声道；单声道复制为双声道）。 */
    private fun upmixToStereo(pcm: ByteArray, channels: Int): ByteArray {
        if (channels <= 0) throw Exception("音频声道信息异常（channels=$channels），无法转换")
        val frames = pcm.size / (channels * 2)
        val stereo = ByteArray(frames * 4)
        for (f in 0 until frames) {
            // 取前两声道；单声道时 L=R
            val lIdx = (f * channels) * 2
            val lLo = pcm[lIdx].toInt() and 0xFF
            val lHi = pcm[lIdx + 1].toInt() and 0xFF
            val lSample = ((lHi shl 8) or lLo)
            val rIdx = if (channels >= 2) (f * channels + 1) * 2 else lIdx
            val rLo = pcm[rIdx].toInt() and 0xFF
            val rHi = pcm[rIdx + 1].toInt() and 0xFF
            val rSample = ((rHi shl 8) or rLo)
            stereo[f * 4] = (lSample and 0xFF).toByte()
            stereo[f * 4 + 1] = ((lSample shr 8) and 0xFF).toByte()
            stereo[f * 4 + 2] = (rSample and 0xFF).toByte()
            stereo[f * 4 + 3] = ((rSample shr 8) and 0xFF).toByte()
        }
        return stereo
    }

    private fun writeWavFile(file: File, pcm: ByteArray, sampleRate: Int, channels: Int) {
        val byteRate = sampleRate * channels * 2
        val blockAlign = channels * 2
        val header = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN)
        header.put("RIFF".toByteArray(Charsets.US_ASCII))
        header.putInt(36 + pcm.size)
        header.put("WAVE".toByteArray(Charsets.US_ASCII))
        header.put("fmt ".toByteArray(Charsets.US_ASCII))
        header.putInt(16)                    // PCM fmt chunk size
        header.putShort(1)                   // audio format = PCM
        header.putShort(channels.toShort())
        header.putInt(sampleRate)
        header.putInt(byteRate)
        header.putShort(blockAlign.toShort())
        header.putShort(16)                  // bits per sample
        header.put("data".toByteArray(Charsets.US_ASCII))
        header.putInt(pcm.size)
        file.outputStream().use { os ->
            os.write(header.array())
            os.write(pcm)
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
                    if (!hasNotificationAccess()) {
                        result.error("NO_ACCESS", "通知使用权未授权", null)
                        return
                    }
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
