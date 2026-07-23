package com.solace.solace.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.Context
import android.content.Intent
import android.graphics.Rect
import android.os.Build
import android.provider.Settings
import android.util.Log
import android.util.Xml
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import org.xmlpull.v1.XmlSerializer
import java.io.StringWriter

/**
 * 无障碍服务 — Solace 角色的"眼睛"
 *
 * 仅负责：
 * - 读取当前窗口 UI 树（完整 XML 与简化信息）
 * - 监听当前前台包名/Activity 变化
 *
 * 所有执行操作（点击、滑动、按键、打开应用、系统控制等）已迁移到 Shizuku。
 */
class SolaceAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "SolaceA11y"

        @Volatile
        var instance: SolaceAccessibilityService? = null
            private set

        /** 最后一次窗口变化的包名+Activity名 */
        @Volatile
        var currentPackageName: String? = null
            private set

        @Volatile
        var currentActivityName: String? = null
            private set

        /** 服务是否曾成功连接过（用于判断是否需要重连） */
        @Volatile
        var wasEverConnected: Boolean = false
            private set

        /** 上次被销毁的时间戳 */
        @Volatile
        var lastDestroyTimestamp: Long = 0L
            private set

        // ── 厂商检测 ──

        /** 是否运行在国产 ROM 上 */
        val isChineseRom: Boolean by lazy {
            val brand = Build.BRAND.lowercase()
            val manufacturer = Build.MANUFACTURER.lowercase()
            brand in setOf("xiaomi", "redmi", "huawei", "honor", "oppo", "vivo", "oneplus", "realme", "meizu") ||
            manufacturer in setOf("xiaomi", "redmi", "huawei", "honor", "oppo", "vivo", "oneplus", "realme", "meizu")
        }

        /** 具体厂商识别 */
        enum class Vendor { XIAOMI, HUAWEI, HONOR, OPPO, VIVO, SAMSUNG, GOOGLE, UNKNOWN }

        val vendor: Vendor by lazy {
            val m = Build.MANUFACTURER.lowercase()
            val b = Build.BRAND.lowercase()
            when {
                m.contains("xiaomi") || b.contains("xiaomi") || b.contains("redmi") -> Vendor.XIAOMI
                m.contains("huawei") || b.contains("huawei") -> Vendor.HUAWEI
                m.contains("honor") || b.contains("honor") -> Vendor.HONOR
                m.contains("oppo") || b.contains("oppo") || b.contains("realme") || b.contains("oneplus") -> Vendor.OPPO
                m.contains("vivo") || b.contains("vivo") || b.contains("iqoo") -> Vendor.VIVO
                m.contains("samsung") || b.contains("samsung") -> Vendor.SAMSUNG
                m.contains("google") || b.contains("google") -> Vendor.GOOGLE
                else -> Vendor.UNKNOWN
            }
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        wasEverConnected = true

        Log.i(TAG, "onServiceConnected — vendor=$vendor, rom=${Build.MANUFACTURER}/${Build.BRAND}")

        val info = AccessibilityServiceInfo().apply {
            eventTypes = AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    AccessibilityServiceInfo.FLAG_INCLUDE_NOT_IMPORTANT_VIEWS or
                    AccessibilityServiceInfo.FLAG_REQUEST_ENHANCED_WEB_ACCESSIBILITY
            notificationTimeout = 100
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                flags = flags or AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
            }
        }
        serviceInfo = info

        // 通知 MainActivity 无障碍已连接
        AccessibilityStateMonitor.notifyConnected(this)
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent) {
        if (event.eventType == AccessibilityEvent.TYPE_WINDOW_STATE_CHANGED) {
            event.packageName?.toString()?.let { currentPackageName = it }
            event.className?.toString()?.let { currentActivityName = it }
        }
    }

    override fun onInterrupt() {
        Log.w(TAG, "onInterrupt — 服务被中断")
    }

    override fun onUnbind(intent: Intent?): Boolean {
        Log.w(TAG, "onUnbind — 服务即将解绑, intent=$intent")
        AccessibilityStateMonitor.notifyDisconnecting(this)
        return super.onUnbind(intent)
    }

    override fun onDestroy() {
        lastDestroyTimestamp = System.currentTimeMillis()
        instance = null
        Log.w(TAG, "onDestroy — 无障碍服务已销毁, timestamp=$lastDestroyTimestamp")
        AccessibilityStateMonitor.notifyDestroyed(this)
        super.onDestroy()
    }

    // ═══════════════════════════════════════════════════
    // UI 树读取（唯一职责）
    // ═══════════════════════════════════════════════════

    fun getUiHierarchy(): String {
        val root = rootInActiveWindow ?: return ""
        return try {
            val writer = StringWriter()
            val serializer = Xml.newSerializer()
            serializer.setOutput(writer)
            serializer.startDocument("UTF-8", true)
            serializeNode(serializer, root, 0)
            serializer.endDocument()
            writer.toString()
        } catch (_: Exception) {
            ""
        } finally {
            root.recycle()
        }
    }

    private fun serializeNode(serializer: XmlSerializer, node: AccessibilityNodeInfo, depth: Int) {
        try {
            serializer.startTag("", "node")
            val attrs = buildMap {
                put("index", node.hashCode().toString())
                node.className?.toString()?.let { put("class", it) }
                node.viewIdResourceName?.let { put("resource-id", it) }
                node.packageName?.toString()?.let { put("package", it) }
                node.contentDescription?.toString()?.takeIf { it.isNotBlank() }?.let { put("content-desc", it) }
                node.text?.toString()?.takeIf { it.isNotBlank() }?.let { put("text", it) }
                put("clickable", node.isClickable.toString())
                put("focusable", node.isFocusable.toString())
                put("enabled", node.isEnabled.toString())
                put("scrollable", node.isScrollable.toString())
                put("editable", node.isEditable.toString())
                val rect = Rect()
                node.getBoundsInScreen(rect)
                put("bounds", "[${rect.left},${rect.top}][${rect.right},${rect.bottom}]")
            }
            for ((key, value) in attrs) {
                serializer.attribute("", key, value)
            }
            for (i in 0 until node.childCount) {
                val child = node.getChild(i) ?: continue
                serializeNode(serializer, child, depth + 1)
                child.recycle()
            }
            serializer.endTag("", "node")
        } catch (_: Exception) {}
    }

    fun findFocusedNodeId(): String {
        val focused = findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
            ?: findFocus(AccessibilityNodeInfo.FOCUS_ACCESSIBILITY)
            ?: return ""
        return try {
            focused.viewIdResourceName ?: focused.hashCode().toString()
        } finally {
            focused.recycle()
        }
    }

    // ═══════════════════════════════════════════════════
    // 工具方法：简化 UI 信息
    // ═══════════════════════════════════════════════════

    fun getSimplifiedUiInfo(): Map<String, Any?> {
        val root = rootInActiveWindow ?: return emptyMap()
        return try {
            val elements = mutableListOf<Map<String, Any?>>()
            collectInteractiveNodes(root, elements, 0, 8)
            mapOf(
                "packageName" to (currentPackageName ?: ""),
                "activityName" to (currentActivityName ?: ""),
                "elements" to elements
            )
        } finally {
            root.recycle()
        }
    }

    private fun collectInteractiveNodes(
        node: AccessibilityNodeInfo,
        result: MutableList<Map<String, Any?>>,
        depth: Int,
        maxDepth: Int
    ) {
        if (depth > maxDepth) return
        val text = node.text?.toString()?.trim().orEmpty()
        val contentDesc = node.contentDescription?.toString()?.trim().orEmpty()
        val isInteractive = node.isClickable || node.isFocusable || node.isEditable
        if (isInteractive || text.isNotEmpty() || contentDesc.isNotEmpty()) {
            val rect = Rect()
            node.getBoundsInScreen(rect)
            result.add(mapOf(
                "class" to (node.className?.toString() ?: ""),
                "text" to text,
                "contentDesc" to contentDesc,
                "resourceId" to (node.viewIdResourceName ?: ""),
                "clickable" to node.isClickable,
                "focusable" to node.isFocusable,
                "editable" to node.isEditable,
                "bounds" to mapOf(
                    "left" to rect.left, "top" to rect.top,
                    "right" to rect.right, "bottom" to rect.bottom
                )
            ))
        }
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            collectInteractiveNodes(child, result, depth + 1, maxDepth)
            child.recycle()
        }
    }
}