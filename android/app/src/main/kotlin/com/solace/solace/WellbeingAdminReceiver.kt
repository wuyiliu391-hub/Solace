package com.solace.solace

import android.app.admin.DeviceAdminReceiver
import android.content.Context
import android.content.Intent

/**
 * Solace 作息陪伴 — 设备管理员接收器
 *
 * 仅承载 force-lock（锁屏）能力，配合 wellbeing_device_admin.xml 策略。
 * 用户在系统里主动授予「设备管理员」后，App 才能调用 lockNow() 锁屏。
 * 用户可随时在 系统设置 → 安全 → 设备管理应用 中撤销。
 *
 * 这里刻意不做任何数据采集、不监听任何广播内容，只保留必要的生命周期回调。
 */
class WellbeingAdminReceiver : DeviceAdminReceiver() {

    override fun onEnabled(context: Context, intent: Intent) {
        super.onEnabled(context, intent)
        // 用户已授予设备管理员权限（仅锁屏）。无需额外动作。
    }

    override fun onDisabled(context: Context, intent: Intent) {
        super.onDisabled(context, intent)
        // 用户已撤销权限。App 将无法再触发锁屏。无需额外动作。
    }
}
