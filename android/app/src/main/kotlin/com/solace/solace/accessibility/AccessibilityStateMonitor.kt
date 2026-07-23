package com.solace.solace.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.text.TextUtils
import android.util.Log

/**
 * 双重无障碍状态检测工具类
 *
 * ## 检测策略（解决国产 ROM 差异化问题）
 *
 * ### 现象①：设置开关保留但服务冻结无法自启
 * - Settings.Secure 中 enabled_accessibility_services 仍包含 Solace
 * - 但系统进程管理器已冻结服务，不再自动绑定
 * - 常见于：鸿蒙 HarmonyOS、小米 HyperOS、荣耀 MagicOS
 * - 检测方法：读 Settings 开关 + 读 running services 列表，双重验证
 *
 * ### 现象②：上滑后台后系统直接把无障碍开关置为关闭
 * - Settings.Secure 中 enabled_accessibility_services 已移除 Solace
 * - 相当于系统自动写入 off
 * - 常见于：OPPO ColorOS（较老版本）、vivo OriginOS
 * - 检测方法：直接读 Settings 开关即可发现
 *
 * ### 厂商差异化对照表：
 * | 厂商       | ROM        | 现象①（冻结） | 现象②（关闭） | 备注 |
 * |-----------|------------|:---------:|:---------:|------|
 * | 华为       | 鸿蒙/HarmonyOS | ✅ 常见 | ❌ 罕见 | 冻结后需重新开关一次 |
 * | 小米       | HyperOS    | ✅ 常见 | ❌ 罕见 | 冻结后需重新开关一次 |
 * | OPPO/一加  | ColorOS    | ⚠ 有时 | ✅ 常见 | 上滑后直接写off |
 * | vivo/iQOO | OriginOS   | ⚠ 有时 | ✅ 常见 | 与ColorOS类似 |
 * | 荣耀       | MagicOS    | ✅ 常见 | ❌ 罕见 | 与鸿蒙行为类似 |
 * | 三星       | OneUI      | ❌ 罕见 | ❌ 罕见 | 行为最规范 |
 * | 原生       | AOSP       | ❌ 罕见 | ❌ 罕见 | 标准行为 |
 */
object AccessibilityStateMonitor {

    private const val TAG = "A11yStateMonitor"

    /** 状态变更广播 Action */
    const val ACTION_STATE_CHANGED = "com.solace.solace.ACCESSIBILITY_STATE_CHANGED"

    // ── 双重检测 ──

    /**
     * 检测结果数据类
     */
    data class AccessibilityDualCheckResult(
        /** Settings 开关是否勾选 */
        val isSettingsEnabled: Boolean,
        /** 系统无障碍服务列表中是否有 Solace */
        val isServiceInList: Boolean,
        /** 无障碍服务实例是否存活 */
        val isServiceInstanceAlive: Boolean,
        /** 检测到的厂商 */
        val vendor: SolaceAccessibilityService.Companion.Vendor,
        /** 建议操作 */
        val suggestedAction: SuggestedAction
    )

    enum class SuggestedAction {
        /** 一切正常 */
        ALL_GOOD,
        /** 已授权但服务未运行 — 需要引导用户重新开关一次 */
        ENABLED_BUT_FROZEN,
        /** 未授权 — 引导用户去设置页开启 */
        NOT_ENABLED,
        /** 已授权且在运行列表但实例为null — 可能正在绑定中 */
        BINDING_IN_PROGRESS
    }

    /**
     * 执行双重检测
     *
     * @param context Application Context
     * @return 完整的检测结果
     */
    fun performDualCheck(context: Context): AccessibilityDualCheckResult {
        val vendor = SolaceAccessibilityService.vendor

        // 第一重：读 Settings 开关
        val isSettingsEnabled = isAccessibilityEnabledInSettings(context)

        // 第二重：读系统正在运行的无障碍服务列表
        val isServiceInList = isServiceInRunningList(context)

        // 第三重：实例是否存活
        val isInstanceAlive = SolaceAccessibilityService.instance != null

        // 判断建议操作
        val action = when {
            isSettingsEnabled && isInstanceAlive -> SuggestedAction.ALL_GOOD
            isSettingsEnabled && isServiceInList && !isInstanceAlive -> SuggestedAction.BINDING_IN_PROGRESS
            isSettingsEnabled && !isServiceInList && !isInstanceAlive -> SuggestedAction.ENABLED_BUT_FROZEN
            !isSettingsEnabled -> SuggestedAction.NOT_ENABLED
            else -> SuggestedAction.NOT_ENABLED
        }

        Log.i(TAG, "双重检测结果: settings=$isSettingsEnabled, inList=$isServiceInList, " +
            "instance=$isInstanceAlive, vendor=$vendor, action=$action")

        return AccessibilityDualCheckResult(
            isSettingsEnabled = isSettingsEnabled,
            isServiceInList = isServiceInList,
            isServiceInstanceAlive = isInstanceAlive,
            vendor = vendor,
            suggestedAction = action
        )
    }

    /**
     * 检测 Settings 中无障碍开关是否勾选
     */
    fun isAccessibilityEnabledInSettings(context: Context): Boolean {
        val enabledServices = try {
            Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: ""
        } catch (e: Exception) {
            Log.e(TAG, "读取 ENABLED_ACCESSIBILITY_SERVICES 失败", e)
            ""
        }

        if (enabledServices.isEmpty()) return false

        val serviceName = "${context.packageName}/${SolaceAccessibilityService::class.java.name}"
        val shortServiceName = "${context.packageName}/.accessibility.SolaceAccessibilityService"

        return enabledServices.contains(serviceName) || enabledServices.contains(shortServiceName)
    }

    /**
     * 检测 Solace 无障碍服务是否在系统当前运行列表中
     *
     * 这是国产 ROM 场景下的关键检测：
     * - Settings 开关可能仍勾选，但系统进程管理器已冻结服务
     * - 通过检查正在运行的 accessibility services 列表来确认
     *
     * 注意：部分国产 ROM 会修改 AccessibilityService 的 lifecycle，
     * 导致 Settings 开关为 on 但实际服务未运行。
     */
    fun isServiceInRunningList(context: Context): Boolean {
        // 方法1：通过 AccessibilityManager 获取已启用的服务列表
        try {
            val am = context.getSystemService(Context.ACCESSIBILITY_SERVICE)
                as? android.view.accessibility.AccessibilityManager
            if (am != null) {
                val enabledList = am.getEnabledAccessibilityServiceList(
                    AccessibilityServiceInfo.FEEDBACK_ALL_MASK
                )
                for (info in enabledList) {
                    val resolvedInfo = info.resolveInfo
                    if (resolvedInfo != null) {
                        val svcName = resolvedInfo.serviceInfo?.name ?: continue
                        if (svcName == SolaceAccessibilityService::class.java.name ||
                            svcName == ".accessibility.SolaceAccessibilityService") {
                            return true
                        }
                    }
                }
            }
        } catch (e: Exception) {
            Log.e(TAG, "getEnabledAccessibilityServiceList 失败", e)
        }

        // 方法2：直接检查静态实例
        if (SolaceAccessibilityService.instance != null) return true

        return false
    }

    // ── 状态通知（供 Activity 接收） ──

    fun notifyConnected(service: SolaceAccessibilityService) {
        sendStateBroadcast(service, "connected")
    }

    fun notifyDisconnecting(service: SolaceAccessibilityService) {
        sendStateBroadcast(service, "disconnecting")
    }

    fun notifyDestroyed(service: SolaceAccessibilityService) {
        sendStateBroadcast(service, "destroyed")
    }

    private fun sendStateBroadcast(service: AccessibilityService, state: String) {
        try {
            val intent = Intent(ACTION_STATE_CHANGED).apply {
                setPackage(service.packageName)
                putExtra("state", state)
                putExtra("timestamp", System.currentTimeMillis())
            }
            service.sendBroadcast(intent)
        } catch (e: Exception) {
            Log.e(TAG, "发送状态广播失败", e)
        }
    }

    // ── 厂商系统设置页跳转 ──

    /**
     * 跳转到无障碍设置页
     */
    fun openAccessibilitySettings(context: Context): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_ACCESSIBILITY_SETTINGS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 跳转到应用的自启动设置页（各厂商独立 Action）
     */
    fun openAutoStartSettings(context: Context): Boolean {
        val vendor = SolaceAccessibilityService.vendor
        return try {
            val intent = when (vendor) {
                SolaceAccessibilityService.Companion.Vendor.XIAOMI -> {
                    // 小米：安全中心 → 自启动管理
                    Intent().apply {
                        component = ComponentName(
                            "com.miui.securitycenter",
                            "com.miui.permcenter.autostart.AutoStartManagementActivity"
                        )
                    }
                }
                SolaceAccessibilityService.Companion.Vendor.HUAWEI -> {
                    // 华为：手机管家 → 启动管理
                    Intent().apply {
                        component = ComponentName(
                            "com.huawei.systemmanager",
                            "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                        )
                    }
                }
                SolaceAccessibilityService.Companion.Vendor.HONOR -> {
                    // 荣耀：系统管家 → 启动管理
                    Intent().apply {
                        component = ComponentName(
                            "com.hihonor.systemmanager",
                            "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity"
                        )
                    }
                }
                SolaceAccessibilityService.Companion.Vendor.OPPO -> {
                    // OPPO/一加：手机管家 → 自启动
                    Intent().apply {
                        component = ComponentName(
                            "com.coloros.phonemanager",
                            "com.coloros.phonemanager.startup.StartupNormalAppListActivity"
                        )
                    }
                }
                SolaceAccessibilityService.Companion.Vendor.VIVO -> {
                    // vivo：i管家 → 自启动
                    Intent().apply {
                        component = ComponentName(
                            "com.iqoo.secure",
                            "com.iqoo.secure.ui.purview.AutoStartManageActivity"
                        )
                    }
                }
                else -> null
            }
            if (intent != null) {
                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(intent)
                true
            } else false
        } catch (e: Exception) {
            Log.w(TAG, "打开自启动设置失败: vendor=$vendor", e)
            false
        }
    }

    /**
     * 跳转到电池优化白名单设置
     */
    fun openBatteryOptimizationSettings(context: Context): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.w(TAG, "打开电池优化设置失败", e)
            false
        }
    }

    /**
     * 跳转到应用详情页（用户可手动设置后台限制等）
     */
    fun openAppDetailsSettings(context: Context): Boolean {
        return try {
            val intent = Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                data = Uri.parse("package:${context.packageName}")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 获取当前是否已忽略电池优化
     */
    fun isIgnoringBatteryOptimizations(context: Context): Boolean {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return false
        return pm.isIgnoringBatteryOptimizations(context.packageName)
    }

    /**
     * 获取完整的保活状态摘要（用于 UI 展示）
     */
    data class KeepAliveStatus(
        val isBatteryOptimized: Boolean,      // true = 未被电池优化限制
        val isAutoStartLikelyOk: Boolean,     // 自启动可能OK（无法精确检测，基于厂商推断）
        val vendorName: String,
        val vendorFriendlyName: String
    )

    fun getKeepAliveStatus(context: Context): KeepAliveStatus {
        val vendor = SolaceAccessibilityService.vendor
        val friendlyName = when (vendor) {
            SolaceAccessibilityService.Companion.Vendor.XIAOMI -> "小米/HyperOS"
            SolaceAccessibilityService.Companion.Vendor.HUAWEI -> "华为/鸿蒙"
            SolaceAccessibilityService.Companion.Vendor.HONOR -> "荣耀/MagicOS"
            SolaceAccessibilityService.Companion.Vendor.OPPO -> "OPPO/ColorOS"
            SolaceAccessibilityService.Companion.Vendor.VIVO -> "vivo/OriginOS"
            SolaceAccessibilityService.Companion.Vendor.SAMSUNG -> "三星/OneUI"
            SolaceAccessibilityService.Companion.Vendor.GOOGLE -> "原生Android"
            SolaceAccessibilityService.Companion.Vendor.UNKNOWN -> "未知系统"
        }
        return KeepAliveStatus(
            isBatteryOptimized = !isIgnoringBatteryOptimizations(context),
            isAutoStartLikelyOk = true, // 无法精确检测，默认为true
            vendorName = vendor.name,
            vendorFriendlyName = friendlyName
        )
    }
}