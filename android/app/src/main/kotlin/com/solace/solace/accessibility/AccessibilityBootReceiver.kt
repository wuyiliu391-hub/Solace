package com.solace.solace.accessibility

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 开机自启 + 无障碍状态监控接收器
 *
 * ## 职责
 * 1. 开机后检测无障碍状态，若已授权则尝试触发服务重连
 * 2. 接收无障碍状态变更广播
 *
 * ## 注意
 * 国产 ROM 对开机自启有严格限制（特别是小米、OPPO），
 * 需要用户在系统设置中手动开启"自启动"权限。
 * 此 Receiver 仅在用户已授权自启动时生效。
 */
class AccessibilityBootReceiver : BroadcastReceiver() {

    companion object {
        private const val TAG = "A11yBootReceiver"
    }

    override fun onReceive(context: Context, intent: Intent?) {
        when (intent?.action) {
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",  // 部分厂商的快启
            "com.huawei.intent.action.QUICKBOOT_POWERON" -> {
                handleBootCompleted(context)
            }
            AccessibilityStateMonitor.ACTION_STATE_CHANGED -> {
                handleStateChanged(context, intent)
            }
        }
    }

    private fun handleBootCompleted(context: Context) {
        Log.i(TAG, "设备启动完成，检查无障碍状态")

        val result = AccessibilityStateMonitor.performDualCheck(context)
        Log.i(TAG, "开机检测结果: $result")

        when (result.suggestedAction) {
            AccessibilityStateMonitor.SuggestedAction.ALL_GOOD -> {
                Log.i(TAG, "无障碍已正常运行")
                // 确保保活服务在运行
                if (!AccessibilityKeepAliveService.isRunning) {
                    AccessibilityKeepAliveService.start(context)
                }
            }
            AccessibilityStateMonitor.SuggestedAction.ENABLED_BUT_FROZEN -> {
                // 服务被冻结，但 Settings 开关仍为 on
                // 国产 ROM 场景：通知用户重新开关一次
                Log.w(TAG, "无障碍开关已勾选但服务未运行 — 需要用户重新开关")
                // 这里不直接操作，等待 App 启动后弹窗引导
            }
            AccessibilityStateMonitor.SuggestedAction.NOT_ENABLED -> {
                Log.i(TAG, "无障碍未授权，等待用户手动开启")
            }
            else -> {}
        }
    }

    private fun handleStateChanged(context: Context, intent: Intent) {
        val state = intent.getStringExtra("state") ?: return
        Log.i(TAG, "无障碍状态变更: $state")

        when (state) {
            "connected" -> {
                // 无障碍已连接，启动保活服务
                AccessibilityKeepAliveService.start(context)
            }
            "destroyed" -> {
                // 无障碍被销毁，停止保活服务
                AccessibilityKeepAliveService.stop(context)
            }
        }
    }
}