package com.solace.solace.capture

import android.content.Context
import android.graphics.Bitmap
import android.graphics.PixelFormat
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.Image
import android.media.ImageReader
import android.media.projection.MediaProjection
import android.os.Handler
import android.os.Looper
import android.view.WindowManager
import java.io.File
import java.io.FileOutputStream

/**
 * 屏幕截图引擎 — VirtualDisplay + ImageReader
 * 对标 Operit MediaProjectionCaptureManager
 */
class MediaProjectionCaptureManager(private val context: Context) {

    private var virtualDisplay: VirtualDisplay? = null
    private var imageReader: ImageReader? = null

    private var displayWidth: Int = 0
    private var displayHeight: Int = 0
    private var displayDpi: Int = 0

    private val handler = Handler(Looper.getMainLooper())

    fun setup() {
        if (virtualDisplay != null) return

        val projection = MediaProjectionHolder.mediaProjection ?: return

        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = android.util.DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(metrics)

        displayWidth = metrics.widthPixels
        displayHeight = metrics.heightPixels
        displayDpi = metrics.densityDpi

        if (displayWidth <= 0 || displayHeight <= 0) return

        val reader = ImageReader.newInstance(displayWidth, displayHeight, PixelFormat.RGBA_8888, 2)
        imageReader = reader

        virtualDisplay = projection.createVirtualDisplay(
            "SolaceScreenCapture",
            displayWidth, displayHeight, displayDpi,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            reader.surface, null, handler
        )

        projection.registerCallback(object : MediaProjection.Callback() {
            override fun onStop() {
                release()
                MediaProjectionHolder.clear(context)
            }
        }, handler)
    }

    fun captureToBitmap(): Bitmap? {
        val reader = imageReader ?: return null
        var image: Image? = null
        return try {
            image = reader.acquireLatestImage()
            if (image == null || image.width <= 0 || image.height <= 0) return null

            val width = image.width
            val height = image.height
            val plane = image.planes[0]
            val buffer = plane.buffer
            val pixelStride = plane.pixelStride
            val rowStride = plane.rowStride
            val rowPadding = rowStride - pixelStride * width

            val paddedBitmap = Bitmap.createBitmap(
                width + rowPadding / pixelStride, height, Bitmap.Config.ARGB_8888
            )
            paddedBitmap.copyPixelsFromBuffer(buffer)
            val cropped = Bitmap.createBitmap(paddedBitmap, 0, 0, width, height)
            paddedBitmap.recycle()
            cropped
        } catch (e: Exception) {
            null
        } finally {
            image?.close()
        }
    }

    fun captureToFile(file: File): Boolean {
        val bitmap = captureToBitmap() ?: return false
        return try {
            FileOutputStream(file).use { out ->
                bitmap.compress(Bitmap.CompressFormat.PNG, 85, out)
            }
        } catch (e: Exception) {
            false
        } finally {
            bitmap.recycle()
        }
    }

    fun captureDimensions(): Pair<Int, Int> {
        return Pair(displayWidth, displayHeight)
    }

    fun release() {
        try {
            virtualDisplay?.release()
        } catch (_: Exception) {}
        virtualDisplay = null
        try {
            imageReader?.close()
        } catch (_: Exception) {}
        imageReader = null
    }
}