package com.solace.solace

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.content.Intent
import android.graphics.Path
import android.graphics.Rect
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.DisplayMetrics
import android.view.WindowManager
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.Serializable
import java.util.concurrent.ConcurrentLinkedQueue

/**
 * Solace 设备操控无障碍服务
 *
 * 提供：点击、滑动、长按、返回、主页、最近任务、读屏、文字输入、通知读取等能力。
 * 通过静态回调与 MainActivity 通信，将结果回传给 Flutter 层。
 */
class DeviceAccessibilityService : AccessibilityService() {

    companion object {
        var instance: DeviceAccessibilityService? = null
            private set

        /// Flutter 侧的回调接口
        var resultCallback: ((String, Any?) -> Unit)? = null

        val isRunning: Boolean
            get() = instance != null
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private val gestureHandler = Handler(Looper.getMainLooper())

    // 操作序列锁 — 确保手势按顺序执行
    private val operationQueue = ConcurrentLinkedQueue<GestureTask>()
    private var isExecuting = false
    private var screenWidth = 0
    private var screenHeight = 0

    // 最近一次屏幕内容缓存
    private var lastScreenContent: String = ""

    // 最近一次通知列表
    private val notifications = mutableListOf<NotificationInfo>()

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        val metrics = DisplayMetrics()
        val wm = getSystemService(WINDOW_SERVICE) as WindowManager
        wm.defaultDisplay.getRealMetrics(metrics)
        screenWidth = metrics.widthPixels
        screenHeight = metrics.heightPixels
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        when (event.eventType) {
            AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED,
            AccessibilityEvent.TYPE_WINDOW_CONTENT_CHANGED -> {
                // 缓存屏幕内容
                val root = rootInActiveWindow
                if (root != null) {
                    lastScreenContent = collectText(root)
                    root.recycle()
                }
            }
            AccessibilityEvent.TYPE_NOTIFICATION_STATE_CHANGED -> {
                // 缓存通知
                val text = event.text?.joinToString(" ") ?: ""
                if (text.isNotBlank()) {
                    notifications.add(
                        NotificationInfo(
                            packageName = event.packageName?.toString() ?: "",
                            text = text,
                            time = System.currentTimeMillis()
                        )
                    )
                    // 最多保留 50 条
                    if (notifications.size > 50) {
                        notifications.removeAt(0)
                    }
                }
            }
        }
    }

    override fun onInterrupt() {
        // 服务被中断
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
    }

    override fun onUnbind(intent: Intent?): Boolean {
        instance = null
        return super.onUnbind(intent)
    }

    // ─── 对外 API（由 MainActivity 通过静态引用调用） ───

    /// 手势 — 点击
    fun performTap(x: Float, y: Float): Boolean {
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 50))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    /// 手势 — 滑动
    fun performSwipe(x1: Float, y1: Float, x2: Float, y2: Float, durationMs: Long = 300): Boolean {
        val path = Path().apply { moveTo(x1, y1); lineTo(x2, y2) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    /// 手势 — 长按
    fun performLongPress(x: Float, y: Float, durationMs: Long = 800): Boolean {
        val path = Path().apply { moveTo(x, y) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        return dispatchGesture(gesture, null, null)
    }

    /// 全局操作 — 返回
    fun performBack(): Boolean = performGlobalAction(GLOBAL_ACTION_BACK)

    /// 全局操作 — 主页
    fun performHome(): Boolean = performGlobalAction(GLOBAL_ACTION_HOME)

    /// 全局操作 — 最近任务
    fun performRecentApps(): Boolean = performGlobalAction(GLOBAL_ACTION_RECENTS)

    /// 全局操作 — 通知面板
    fun performOpenNotifications(): Boolean = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)

    /// 全局操作 — 快速设置
    fun performOpenQuickSettings(): Boolean = performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)

    /// 点击包含指定文本的 UI 元素
    fun clickByText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        val nodes = root.findAccessibilityNodeInfosByText(text)
        return try {
            for (node in nodes) {
                if (node.isClickable) {
                    node.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                    return true
                }
            }
            // 如果没找到可直接点击的节点，尝试找父节点
            for (node in nodes) {
                var parent = node.parent
                while (parent != null) {
                    if (parent.isClickable) {
                        parent.performAction(AccessibilityNodeInfo.ACTION_CLICK)
                        return true
                    }
                    parent = parent.parent
                }
            }
            false
        } finally {
            for (node in nodes) {
                node.recycle()
            }
            root.recycle()
        }
    }

    /// 在焦点输入框中输入文字
    fun typeText(text: String): Boolean {
        val root = rootInActiveWindow ?: return false
        return try {
            val focused = root.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            if (focused != null) {
                val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) }
                focused.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                true
            } else {
                // 尝试找第一个可输入的节点
                val editableNodes = mutableListOf<AccessibilityNodeInfo>()
                findEditableNodes(root, editableNodes)
                if (editableNodes.isNotEmpty()) {
                    val node = editableNodes[0]
                    val args = Bundle().apply { putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text) }
                    node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                    true
                } else {
                    false
                }
            }
        } finally {
            root.recycle()
        }
    }

    /// 获取当前屏幕文字内容
    fun getScreenContent(): String {
        // 如果缓存不为空，使用缓存
        if (lastScreenContent.isNotBlank()) return lastScreenContent
        val root = rootInActiveWindow ?: return ""
        return try {
            collectText(root)
        } finally {
            root.recycle()
        }
    }

    /// 刷新屏幕内容（强制重新读取）
    fun refreshScreenContent(): String {
        val root = rootInActiveWindow ?: return ""
        return try {
            collectText(root).also { lastScreenContent = it }
        } finally {
            root.recycle()
        }
    }

    /// 获取最近通知
    fun getNotifications(): List<Map<String, Any>> {
        return notifications.map { it.toMap() }
    }

    /// 获取截图（需要 Android 11+ 且服务支持）
    fun takeScreenshot(): String? {
        // 使用无障碍截图 API（Android 12+ 原生支持）
        // Android 11 部分厂商支持
        return try {
            var screenshotPath: String? = null
            val callback = object : AccessibilityService.TakeScreenshotCallback {
                override fun onSuccess(screenshot: AccessibilityService.ScreenshotResult) {
                    screenshotPath = "screenshot_${System.currentTimeMillis()}.png"
                    // 保存到缓存目录
                    val file = java.io.File(cacheDir, screenshotPath!!)
                    val bitmap = android.graphics.Bitmap.wrapHardwareBuffer(
                        screenshot.hardwareBuffer, screenshot.colorSpace
                    )
                    file.outputStream().use { bitmap?.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
                    bitmap?.recycle()
                }
                override fun onFailure(failure: Int) {
                    screenshotPath = null
                }
            }
            val executor = java.util.concurrent.Executor { mainHandler.post(it) }
            takeScreenshot(/* displayId = */ 0, /* executor = */ executor, callback)
            // 注意：takeScreenshot 是异步的，这里简单返回空，
            // Flutter 侧需通过回调获取结果
            null
        } catch (e: Exception) {
            null
        }
    }

    /// 打开指定 App
    fun openApp(packageName: String): Boolean {
        return try {
            val intent = packageManager.getLaunchIntentForPackage(packageName)
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                startActivity(intent)
                true
            } else false
        } catch (e: Exception) {
            false
        }
    }

    // ─── 辅助方法 ───

    private fun collectText(node: AccessibilityNodeInfo): String {
        val sb = StringBuilder()
        collectTextRecursive(node, sb)
        return sb.toString().trim()
    }

    private fun collectTextRecursive(node: AccessibilityNodeInfo, sb: StringBuilder) {
        if (node == null) return
        if (node.text != null) {
            sb.appendLine(node.text)
        }
        if (node.contentDescription != null) {
            sb.appendLine(node.contentDescription)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                collectTextRecursive(child, sb)
                child.recycle()
            }
        }
    }

    private fun findEditableNodes(node: AccessibilityNodeInfo, result: MutableList<AccessibilityNodeInfo>) {
        if (node.isEditable) {
            result.add(node)
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i)
            if (child != null) {
                findEditableNodes(child, result)
                child.recycle()
            }
        }
    }

    /// 获取屏幕尺寸
    fun getScreenSize(): Pair<Int, Int> = Pair(screenWidth, screenHeight)
}

/// 手势任务
data class GestureTask(
    val type: String,
    val params: Map<String, Any>,
    val callback: ((Boolean) -> Unit)?
)

/// 通知信息
data class NotificationInfo(
    val packageName: String,
    val text: String,
    val time: Long
) : Serializable {
    fun toMap(): Map<String, Any> = mapOf(
        "packageName" to packageName,
        "text" to text,
        "time" to time
    )
}
