package com.solace.solace.notification

import android.app.Notification
import android.os.Build
import android.service.notification.NotificationListenerService
import android.service.notification.StatusBarNotification

/**
 * 通知持久存储 — 线程安全、最多 200 条、FIFO
 * 对标 Operit OperitNotificationStore
 */
object NotificationStore {
    private data class Entry(
        val key: String,
        val packageName: String,
        val title: String,
        val text: String,
        val timestamp: Long,
        val tag: String?
    )

    private val lock = Any()
    private val entries = LinkedHashMap<String, Entry>()

    fun upsert(sbn: StatusBarNotification) {
        val key = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            sbn.key
        } else {
            "${sbn.packageName}:${sbn.id}:${sbn.tag ?: ""}"
        }

        val notification = sbn.notification
        val extras = notification.extras
        val title = extras?.getCharSequence(Notification.EXTRA_TITLE)?.toString()?.trim().orEmpty()
        val text = buildString {
            val t = extras?.getCharSequence(Notification.EXTRA_TEXT)?.toString()?.trim().orEmpty()
            if (t.isNotBlank()) append(t)
            val big = extras?.getCharSequence(Notification.EXTRA_BIG_TEXT)?.toString()?.trim().orEmpty()
            if (big.isNotBlank() && big != t) {
                if (isNotEmpty()) append("\n")
                append(big)
            }
            val lines = extras?.getCharSequenceArray(Notification.EXTRA_TEXT_LINES)
            if (lines != null) {
                for (line in lines) {
                    val l = line?.toString()?.trim().orEmpty()
                    if (l.isNotBlank() && l != t && l != big) {
                        if (isNotEmpty()) append("\n")
                        append(l)
                    }
                }
            }
        }

        val entry = Entry(
            key = key,
            packageName = sbn.packageName ?: "",
            title = title,
            text = text,
            timestamp = sbn.postTime,
            tag = sbn.tag
        )

        synchronized(lock) {
            entries[key] = entry
            if (entries.size > 200) {
                val toRemove = entries.entries.iterator().next().key
                entries.remove(toRemove)
            }
        }
    }

    fun remove(sbn: StatusBarNotification) {
        val key = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            sbn.key
        } else {
            "${sbn.packageName}:${sbn.id}:${sbn.tag ?: ""}"
        }
        synchronized(lock) {
            entries.remove(key)
        }
    }

    fun snapshot(limit: Int): List<Map<String, Any?>> {
        val safeLimit = limit.coerceAtLeast(0)
        synchronized(lock) {
            return entries.values
                .sortedByDescending { it.timestamp }
                .take(safeLimit)
                .map {
                    mapOf(
                        "packageName" to it.packageName,
                        "title" to it.title,
                        "text" to it.text,
                        "timestamp" to it.timestamp,
                        "tag" to it.tag
                    )
                }
        }
    }

    fun count(): Int = synchronized(lock) { entries.size }
}

/**
 * 通知监听服务 — 实时捕获系统通知并存入 NotificationStore
 * 对标 Operit OperitNotificationListenerService
 */
class SolaceNotificationListenerService : NotificationListenerService() {

    override fun onListenerConnected() {
        super.onListenerConnected()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                activeNotifications?.forEach { NotificationStore.upsert(it) }
            } catch (_: Exception) {
            }
        }
    }

    override fun onNotificationPosted(sbn: StatusBarNotification) {
        NotificationStore.upsert(sbn)
    }

    override fun onNotificationRemoved(sbn: StatusBarNotification) {
        NotificationStore.remove(sbn)
    }
}
