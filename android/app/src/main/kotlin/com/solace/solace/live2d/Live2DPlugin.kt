package com.solace.solace.live2d

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * Live2D 桌宠 Flutter 插件桥接
 *
 * 提供 MethodChannel 给 Dart 层调用：
 * - showOverlay: 显示桌宠悬浮窗
 * - hideOverlay: 隐藏桌宠悬浮窗
 * - checkOverlayPermission: 检查悬浮窗权限
 * - requestOverlayPermission: 请求悬浮窗权限
 * - syncAvatarConfig: 同步整套 Avatar 配置
 * - setPartVisible: 设置某个部位显隐
 */
class Live2DPlugin(private val context: Context) : io.flutter.plugin.common.MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "Live2DPlugin"
        private const val CHANNEL = "com.solace.solace/live2d"

        @JvmStatic
        fun registerWith(messenger: io.flutter.plugin.common.BinaryMessenger, context: Context) {
            io.flutter.plugin.common.MethodChannel(messenger, CHANNEL).setMethodCallHandler(Live2DPlugin(context))
        }
    }

    override fun onMethodCall(call: io.flutter.plugin.common.MethodCall, result: io.flutter.plugin.common.MethodChannel.Result) {
        when (call.method) {
            "checkOverlayPermission" -> {
                result.success(canDrawOverlays())
            }
            "requestOverlayPermission" -> {
                requestOverlayPermission()
                result.success(null)
            }
            "showOverlay" -> {
                showOverlay()
                result.success(true)
            }
            "hideOverlay" -> {
                hideOverlay()
                result.success(true)
            }
            "isOverlayRunning" -> {
                result.success(Live2DOverlayService.isRunning())
            }
            "syncAvatarConfig" -> {
                val config = call.argument<String>("config")
                if (config != null) {
                    Live2DStateManager.syncAvatarConfig(config)
                }
                result.success(null)
            }
            "syncPetCharacter" -> {
                val config = call.argument<String>("config")
                if (config != null) {
                    Live2DStateManager.syncPetCharacter(config)
                }
                result.success(null)
            }
            "setPartVisible" -> {
                val part = call.argument<String>("part")
                val visible = call.argument<Boolean>("visible") ?: true
                if (part != null) {
                    Live2DStateManager.setPartVisible(part, visible)
                }
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun canDrawOverlays(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            Settings.canDrawOverlays(context)
        } else {
            true
        }
    }

    private fun requestOverlayPermission() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
            val intent = Intent(
                Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                Uri.parse("package:${context.packageName}")
            )
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (context is Activity) {
                context.startActivityForResult(intent, 1001)
            } else {
                context.startActivity(intent)
            }
        }
    }

    private fun showOverlay() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !Settings.canDrawOverlays(context)) {
            requestOverlayPermission()
            return
        }
        val intent = Intent(context, Live2DOverlayService::class.java)
        // ═══ Android 8+ 启动 FGS 必须用 startForegroundService ═══
        // 否则会抛 BackgroundServiceNotAllowedException / ForegroundServiceStartNotAllowedException
        // ContextCompat.startForegroundService 内部按 SDK 分发：
        //   - Android 8+ 调 context.startForegroundService(intent)
        //   - Android 7- 调 context.startService(intent)
        // 服务 onStartCommand 会立即调 startForeground() 完成前台化（Android 14+ 强制）
        ContextCompat.startForegroundService(context, intent)
    }

    private fun hideOverlay() {
        val intent = Intent(context, Live2DOverlayService::class.java)
        context.stopService(intent)
    }
}
