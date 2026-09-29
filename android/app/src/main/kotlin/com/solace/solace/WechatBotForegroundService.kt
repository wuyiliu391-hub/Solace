package com.solace.solace

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

/// 微信机器人前台保活服务。
///
/// 只要 bot 在轮询，这个服务就以前台方式运行，阻止 Android 杀 App 网络连接。
/// 通知显示机器人状态，用户可以滑动移除（移除 = 停止 bot）。
/// 纯保活，不跑任何业务逻辑（业务逻辑在 Flutter 侧）。
class WechatBotForegroundService : Service() {

    companion object {
        const val CHANNEL_ID = "wechat_bot_foreground"
        const val NOTIFICATION_ID = 99002
        const val ACTION_START = "com.solace.solace.action.START_WECHAT_BOT"
        const val ACTION_STOP = "com.solace.solace.action.STOP_WECHAT_BOT"
        const val EXTRA_TITLE = "title"
        const val EXTRA_BODY = "body"
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val title = intent.getStringExtra(EXTRA_TITLE) ?: "微信机器人"
                val body = intent.getStringExtra(EXTRA_BODY) ?: "在线"
                val notification = buildNotification(title, body)
                startForeground(NOTIFICATION_ID, notification)
            }
            ACTION_STOP -> {
                stopForeground(STOP_FOREGROUND_REMOVE)
                stopSelf()
            }
        }
        return START_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "微信机器人",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "微信机器人后台运行状态"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }
    }

    @Suppress("DEPRECATION")
    private fun buildNotification(title: String, body: String): Notification {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setOngoing(true)
                .build()
        } else {
            Notification.Builder(this)
                .setContentTitle(title)
                .setContentText(body)
                .setSmallIcon(android.R.drawable.ic_dialog_info)
                .setOngoing(true)
                .build()
        }
    }
}