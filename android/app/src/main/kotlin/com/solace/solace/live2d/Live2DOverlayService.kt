package com.solace.solace.live2d

import android.animation.ValueAnimator
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.graphics.PixelFormat
import android.os.Build
import android.os.IBinder
import android.util.Log
import android.view.Gravity
import android.view.MotionEvent
import android.view.WindowManager
import androidx.core.app.NotificationCompat
import io.flutter.embedding.android.FlutterTextureView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor

/**
 * Live2D 桌宠悬浮窗服务
 *
 * 在桌面显示一个可拖拽的 Flutter 视图，承载桌宠渲染。
 * 使用独立的 FlutterEngine 运行 live2d_entry.dart，避免影响主 App 导航栈。
 *
 * Android 14+ 要求：FGS（前台服务）必须调用 startForeground() 并声明 foregroundServiceType。
 * Manifest 已声明 foregroundServiceType="specialUse"，所以这里也要调用
 * startForeground(id, notification, ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE)。
 */
class Live2DOverlayService : Service() {

    companion object {
        private const val TAG = "Live2DOverlayService"
        private const val ENTRYPOINT = "live2d_entry"
        private const val ENGINE_ID = "live2d_overlay_engine"
        private const val NOTIFICATION_ID = 0x0112  // 桌宠悬浮窗通知 ID（与 music/notification 等区分）
        private const val CHANNEL_ID = "solace_live2d_overlay"

        @JvmStatic
        fun isRunning(): Boolean = instance != null

        private var instance: Live2DOverlayService? = null
    }

    private var windowManager: WindowManager? = null
    private var flutterView: FlutterView? = null
    private var params: WindowManager.LayoutParams? = null
    private var initialX = 0
    private var initialY = 0
    private var touchX = 0f
    private var touchY = 0f
    private var isDragging = false
    // 最近一次 ACTION_DOWN 的坐标（相对于 view，像素），供 OnClickListener 使用
    private var lastTapX = 0f
    private var lastTapY = 0f

    override fun onCreate() {
        super.onCreate()
        instance = this
        Log.i(TAG, "Live2D overlay service created")
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        // ═══ FGS 必需：启动时立即调用 startForeground ═══
        // 否则 Android 14+ 会抛 ForegroundServiceDidNotStartInTimeException
        startForegroundCompat()

        if (flutterView != null) {
            Log.i(TAG, "Overlay already running, ignore start")
            return START_STICKY
        }
        try {
            showOverlay()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show overlay", e)
            stopSelf()
        }
        return START_STICKY
    }

    /**
     * 启动前台服务通知（Android 8+ 必需，Android 14+ 强制 FGS type）
     */
    private fun startForegroundCompat() {
        // 创建通知 channel（Android 8+ 必需）
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "桌宠悬浮窗",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "保持桌宠悬浮窗在桌面持续运行"
                setShowBadge(false)
            }
            val nm = getSystemService(NotificationManager::class.java)
            nm.createNotificationChannel(channel)
        }

        val notification: Notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Solace 桌宠")
            .setContentText("桌宠正在桌面上陪伴你")
            .setSmallIcon(android.R.drawable.ic_menu_compass)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()

        // Android 14+ 必须显式指定 foregroundServiceType
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun showOverlay() {
        windowManager = getSystemService(Context.WINDOW_SERVICE) as WindowManager

        // 使用缓存引擎，避免每次都新建
        val engine = FlutterEngineCache.getInstance().get(ENGINE_ID)
            ?: Live2DEngineCache.getEngine(application)
            ?: throw IllegalStateException("Live2D engine not available")

        // 如果引擎未启动 entrypoint，则启动（通常 Live2DEngineCache.prepare 已启动）
        if (engine.dartExecutor.isolateServiceId == null) {
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint(
                    io.flutter.embedding.engine.loader.FlutterLoader().findAppBundlePath(),
                    ENTRYPOINT
                )
            )
        }

        val textureView = FlutterTextureView(this).apply {
            isOpaque = false
        }
        val view = FlutterView(this, textureView).also {
            flutterView = it
        }
        view.attachToFlutterEngine(engine)

        val width = dpToPx(200)
        val height = dpToPx(250)

        params = WindowManager.LayoutParams(
            width,
            height,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY
            else WindowManager.LayoutParams.TYPE_PHONE,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE
                or WindowManager.LayoutParams.FLAG_NOT_TOUCH_MODAL
                or WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS
                or WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED,
            PixelFormat.TRANSLUCENT
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = 0
            y = dpToPx(300)
        }

        view.setOnTouchListener { _, event ->
            when (event.action) {
                MotionEvent.ACTION_DOWN -> {
                    initialX = params?.x ?: 0
                    initialY = params?.y ?: 0
                    touchX = event.rawX
                    touchY = event.rawY
                    // 记录相对于 view 的点击坐标（像素），供 OnClickListener 推送到 Dart
                    lastTapX = event.x
                    lastTapY = event.y
                    isDragging = false
                    true
                }
                MotionEvent.ACTION_MOVE -> {
                    val dx = (event.rawX - touchX).toInt()
                    val dy = (event.rawY - touchY).toInt()
                    if (kotlin.math.abs(dx) > 10 || kotlin.math.abs(dy) > 10) {
                        isDragging = true
                    }
                    params?.x = initialX + dx
                    params?.y = initialY + dy
                    windowManager?.updateViewLayout(view, params)
                    true
                }
                MotionEvent.ACTION_UP -> {
                    if (!isDragging) {
                        view.performClick()
                    } else {
                        // ═══ 拖拽边界吸附：松手时自动滑到最近的左/右边缘 ═══
                        // 纵向只做 clip 防止拖出屏幕，不强制吸附上下（保留用户高度自由度）。
                        snapToEdge()
                    }
                    true
                }
                else -> false
            }
        }

        // ═══ 点击交互：注册 OnClickListener ═══
        // ACTION_UP 时已调用 view.performClick()，这里注册 listener 接收回调，
        // 把点击坐标（转成 dp / 逻辑像素）通过 EventChannel 推送到悬浮窗 Dart。
        // Dart 端按 y 坐标三等分判断点击部位（头/身/腿）并触发对应情绪。
        view.setOnClickListener {
            val density = resources.displayMetrics.density
            val xDp = lastTapX / density
            val yDp = lastTapY / density
            Live2DStateManager.sendTap(xDp, yDp)
        }

        view.addOnFirstFrameRenderedListener(object : io.flutter.embedding.engine.renderer.FlutterUiDisplayListener {
            override fun onFlutterUiDisplayed() {
                Log.i(TAG, "Flutter UI rendered in overlay")
            }
            override fun onFlutterUiNoLongerDisplayed() {}
        })

        windowManager?.addView(view, params)
        Log.i(TAG, "Overlay shown: ${width}x${height}")
    }

    private fun dpToPx(dp: Int): Int {
        return (dp * resources.displayMetrics.density + 0.5f).toInt()
    }

    /**
     * 拖拽松手时把悬浮窗吸附到最近的左右边缘，纵向只 clip 到屏幕内。
     *
     * 行为：
     * - 横向：view 中心 x < 屏幕中线 → 滑到左边 (x=0)，否则滑到右边 (x=screenWidth-viewWidth)
     * - 纵向：clip 到 [0, screenHeight-viewHeight]（保留用户拖到的高度，但防止超出屏幕）
     * - 动画：ValueAnimator + DecelerateInterpolator，200ms
     *
     * 兼容性：用 resources.displayMetrics.widthPixels 取屏幕尺寸（API 1+，无废弃）。
     */
    private fun snapToEdge() {
        val view = flutterView ?: return
        val lp = params ?: return

        val screenWidth = resources.displayMetrics.widthPixels
        val screenHeight = resources.displayMetrics.heightPixels
        val viewWidth = lp.width
        val viewHeight = lp.height

        val curX = lp.x
        val curY = lp.y
        val centerX = curX + viewWidth / 2
        val targetX = if (centerX < screenWidth / 2) 0 else (screenWidth - viewWidth).coerceAtLeast(0)
        val targetY = curY.coerceIn(0, (screenHeight - viewHeight).coerceAtLeast(0))

        if (curX == targetX && curY == targetY) return

        val animator = ValueAnimator.ofInt(curX, targetX).apply {
            duration = 200
            interpolator = android.view.animation.DecelerateInterpolator()
            addUpdateListener {
                val v = it.animatedValue as Int
                try {
                    lp.x = v
                    lp.y = targetY  // 纵向直接 clip（不动画，避免和横向动画时序冲突）
                    windowManager?.updateViewLayout(view, lp)
                } catch (e: Exception) {
                    // view 可能已 detach，吞掉
                    cancel()
                }
            }
        }
        animator.start()
    }

    private fun hideOverlay() {
        flutterView?.let { view ->
            try {
                windowManager?.removeView(view)
            } catch (e: Exception) {
                Log.w(TAG, "removeView failed", e)
            }
            view.detachFromFlutterEngine()
        }
        flutterView = null
        windowManager = null
    }

    override fun onDestroy() {
        hideOverlay()
        instance = null
        super.onDestroy()
        Log.i(TAG, "Live2D overlay service destroyed")
    }
}
