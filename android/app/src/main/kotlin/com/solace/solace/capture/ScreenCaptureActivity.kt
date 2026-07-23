package com.solace.solace.capture

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjectionManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock

/**
 * 透明 Activity — 请求 MediaProjection 权限
 * 对标 Operit ScreenCaptureActivity
 */
class ScreenCaptureActivity : Activity() {

    companion object {
        private const val REQUEST_CODE_CAPTURE = 1001

        fun start(context: Context) {
            val intent = Intent(context, ScreenCaptureActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }
    }

    private lateinit var mediaProjectionManager: MediaProjectionManager

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        mediaProjectionManager = getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
        startActivityForResult(
            mediaProjectionManager.createScreenCaptureIntent(),
            REQUEST_CODE_CAPTURE
        )
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)

        if (requestCode != REQUEST_CODE_CAPTURE || resultCode != Activity.RESULT_OK || data == null) {
            finish()
            return
        }

        MediaProjectionHolder.setPermission(resultCode, data)

        // Android 14+ 必须先启动 FGS 再调用 getMediaProjection
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            ScreenCaptureService.start(this)
            waitForFgsThenGetProjection()
        } else {
            acquireProjection()
            finish()
        }
    }

    private fun waitForFgsThenGetProjection() {
        val handler = Handler(Looper.getMainLooper())
        val startAt = SystemClock.uptimeMillis()
        val timeoutMs = 1500L

        val checker = object : Runnable {
            override fun run() {
                val elapsed = SystemClock.uptimeMillis() - startAt
                if (ScreenCaptureService.isForegroundReady || elapsed >= timeoutMs) {
                    acquireProjection()
                    finish()
                    return
                }
                handler.postDelayed(this, 30)
            }
        }
        handler.post(checker)
    }

    private fun acquireProjection() {
        try {
            val projection = mediaProjectionManager.getMediaProjection(
                MediaProjectionHolder.permissionResultCode,
                MediaProjectionHolder.permissionResultData!!
            ) ?: return
            MediaProjectionHolder.setProjection(projection)
        } catch (e: SecurityException) {
            MediaProjectionHolder.clear(this)
        }
    }
}