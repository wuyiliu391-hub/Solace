package com.solace.solace.accessibility

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.util.Log
import com.solace.solace.MainActivity
import com.solace.solace.R

/**
 * 无障碍保活前台服务
 *
 * ## 设计目标
 * 将无障碍服务的生存概率提升到接近前台 App 级别。
 * 在前台服务运行期间，系统不会轻易杀死进程，
 * 从而间接保护 SolaceAccessibilityService 不被系统回收。
 *
 * ## 国产 ROM 策略
 * - 前台服务 + 持久通知 = 系统认为 App 正在执行可见任务
 * - 配合电池优化白名单，极大降低被杀概率
 * - 配合通知栏重要性设为 LOW（静默通道），不骚扰用户
 *
 * ## 轻量化设计
 * - 不做 CPU 密集操作
 * - 不做网络常连接
 * - 无额外内存开销
 * - 仅在无障碍开启时运行
 */
class AccessibilityKeepAliveService : Service() {

    companion object {
        private const val TAG = "A11yKeepAlive"
        private const val NOTIFICATION_ID = 3001
        private const val CHANNEL_ID = "solace_accessibility_keepalive"
        private const val CHANNEL_NAME = "无障碍服务"

        @Volatile
        var isRunning: Boolean = false
            private set

        /**
         * 启动保活服务
         * 应在无障碍服务连接成功后被调用
         */
        fun start(context: Context) {
            if (isRunning) return
            Log.i(TAG, "启动保活前台服务")
            val intent = Intent(context, AccessibilityKeepAliveService::class.java)
            try {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    context.startForegroundService(intent)
                } else {
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.e(TAG, "启动保活服务失败", e)
            }
        }

        /**
         * 停止保活服务
         * 应在无障碍服务被关闭时调用
         */
        fun stop(context: Context) {
            if (!isRunning) return
            Log.i(TAG, "停止保活前台服务")
            try {
                context.stopService(Intent(context, AccessibilityKeepAliveService::class.java))
            } catch (e: Exception) {
                Log.e(TAG, "停止保活服务失败", e)
            }
        }
    }

    override fun onCreate() {
        super.onCreate()
        Log.i(TAG, "onCreate")
        createNotificationChannel()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        Log.i(TAG, "onStartCommand")

        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            isRunning = true
        } catch (e: Exception) {
            Log.e(TAG, "startForeground 失败", e)

            // 部分旧设备不支持 FOREGROUND_SERVICE_TYPE，降级重试
            try {
                startForeground(NOTIFICATION_ID, notification)
                isRunning = true
            } catch (e2: Exception) {
                Log.e(TAG, "降级 startForeground 也失败", e2)
            }
        }

        return START_STICKY
    }

    override fun onDestroy() {
        isRunning = false
        Log.w(TAG, "onDestroy — 保活服务被销毁，无障碍可能受影响")
        super.onDestroy()
    }

    override fun onTaskRemoved(rootIntent: Intent?) {
        // 用户从最近任务中划掉了 App
        // START_STICKY 会尝试重启，但国产 ROM 可能阻止
        Log.w(TAG, "onTaskRemoved — 用户划掉了最近任务")
        super.onTaskRemoved(rootIntent)
    }

    // ── 通知 ──

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW  // LOW: 不发出声音，只显示在通知栏
            ).apply {
                description = "用于保持无障碍服务运行"
                setShowBadge(false)
                // 国产 ROM 通常不允许完全静默的前台服务通知
                // 设为 LOW 是最低打扰的折中方案
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_UPDATE_CURRENT
            }
        )

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle("Solace 无障碍服务")
                .setContentText("正在运行中，保持服务可用")
                .setSmallIcon(android.R.drawable.ic_menu_manage)
                .setOngoing(true)
                .setContentIntent(pendingIntent)
                .build()
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
                .setContentTitle("Solace 无障碍服务")
                .setContentText("正在运行中，保持服务可用")
                .setSmallIcon(android.R.drawable.ic_menu_manage)
                .setOngoing(true)
                .setContentIntent(pendingIntent)
                .build()
        }
    }
}