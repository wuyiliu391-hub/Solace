package com.solace.solace.capture

import android.content.Context
import android.content.Intent
import android.media.projection.MediaProjection

/**
 * 全局 MediaProjection 令牌持有者
 * 对标 Operit MediaProjectionHolder
 */
object MediaProjectionHolder {
    var mediaProjection: MediaProjection? = null
        private set

    var permissionResultCode: Int = 0
        private set
    var permissionResultData: Intent? = null
        private set

    fun setPermission(resultCode: Int, data: Intent) {
        permissionResultCode = resultCode
        permissionResultData = data
    }

    fun setProjection(projection: MediaProjection) {
        mediaProjection = projection
    }

    fun clear(context: Context?) {
        try {
            mediaProjection?.stop()
        } catch (_: Exception) {}
        mediaProjection = null
        permissionResultData = null
        permissionResultCode = 0
        if (context != null) {
            ScreenCaptureService.stop(context)
        }
    }

    val isReady: Boolean
        get() = mediaProjection != null
}
