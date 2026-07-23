package com.solace.solace.capture

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import com.solace.solace.MainActivity

/**
 * 屏幕截图前台服务 — Android 14+ 要求的 mediaProjection FGS 类型
 * 对标 Operit ScreenCaptureService
 */
class ScreenCaptureService : Service() {

    companion object {
        private const val NOTIFICATION_ID = 2001
        private const val CHANNEL_ID = "solace_screen_capture"
        private const val CHANNEL_NAME = "屏幕截图"

        @Volatile
        var isForegroundReady: Boolean = false
            private set

        fun start(context: Context) {
            isForegroundReady = false
            val intent = Intent(context, ScreenCaptureService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            isForegroundReady = false
            context.stopService(Intent(context, ScreenCaptureService::class.java))
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        createNotificationChannel()
        val notification = buildNotification()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PROJECTION
                )
            } else {
                startForeground(NOTIFICATION_ID, notification)
            }
            isForegroundReady = true
        } catch (e: Exception) {
            android.util.Log.e("ScreenCaptureService", "startForeground failed", e)
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        isForegroundReady = false
        super.onDestroy()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "屏幕截图所需的后台服务"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification() = NotificationCompat.Builder(this, CHANNEL_ID)
        .setContentTitle("Solace 屏幕感知")
        .setContentText("正在运行屏幕截图服务")
        .setSmallIcon(android.R.drawable.ic_menu_camera)
        .setOngoing(true)
        .setContentIntent(
            PendingIntent.getActivity(
                this,
                0,
                Intent(this, MainActivity::class.java),
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT
            )
        )
        .build()
}
