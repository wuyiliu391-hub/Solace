package com.solace.solace

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Shizuku Shell 命令执行管理器
 *
 * 通过 Shizuku API 以 shell 级别权限执行系统命令。
 * 需要用户安装 Shizuku Manager App 并通过无线调试激活。
 *
 * 能力范围：
 * - 系统设置：WiFi、蓝牙、音量、亮度
 * - 应用管理：安装/卸载、授权
 * - 通用 shell 命令
 *
 * 注意：重启后需要重新激活 Shizuku。
 */
class ShizukuManager(private val context: Context) {

    companion object {
        private const val TAG = "ShizukuManager"

        /// Shizuku 是否可用（通过 ping 检测）
        fun isShizukuAvailable(): Boolean {
            return try {
                val cls = Class.forName("moe.shizuku.api.Shizuku")
                val method = cls.getMethod("ping")
                method.invoke(null) as? Boolean ?: false
            } catch (e: Exception) {
                Log.w(TAG, "Shizuku not available: ${e.message}")
                false
            }
        }

        /// Shizuku 是否已授权
        fun isShizukuAuthorized(): Boolean {
            // 先检查是否可用
            if (!isShizukuAvailable()) return false
            // 再检查授权状态
            return try {
                val cls = Class.forName("moe.shizuku.api.Shizuku")
                val method = cls.getMethod("getVersion")
                val version = method.invoke(null) as? Int ?: -1
                version > 0
            } catch (e: Exception) {
                false
            }
        }
    }

    /// 执行 shell 命令，返回输出文本
    fun executeCommand(command: String): ShellResult {
        return try {
            val cls = Class.forName("moe.shizuku.api.Shizuku")
            val newProcessMethod = cls.getMethod("newProcess", Array<String>::class.java)

            val cmdArray = arrayOf("sh", "-c", command)
            val process = newProcessMethod.invoke(null, cmdArray) as? Process ?: return ShellResult(false, "", "Failed to create process")

            val stdout = BufferedReader(InputStreamReader(process.inputStream)).readText()
            val stderr = BufferedReader(InputStreamReader(process.errorStream)).readText()

            // 需要在子线程等待，防止阻塞 UI
            val exitCode = process.waitFor()

            ShellResult(
                success = exitCode == 0,
                output = stdout.trim(),
                error = stderr.trim()
            )
        } catch (e: Exception) {
            Log.e(TAG, "Shizuku command failed: ${e.message}")
            ShellResult(false, "", e.message ?: "Unknown error")
        }
    }

    /// 开关 WiFi
    fun setWifiEnabled(enabled: Boolean): ShellResult {
        return executeCommand(if (enabled) "svc wifi enable" else "svc wifi disable")
    }

    /// 设置音量（0-100）
    fun setVolume(level: Int): ShellResult {
        val clamped = level.coerceIn(0, 100)
        // 转换为 Android 音量范围 0-15（媒体音量）
        val androidVolume = (clamped * 15 / 100).coerceIn(0, 15)
        return executeCommand("media volume --stream 3 --set $androidVolume")
    }

    /// 设置屏幕亮度（0-255）
    fun setBrightness(level: Int): ShellResult {
        val clamped = level.coerceIn(0, 255)
        return executeCommand("settings put system screen_brightness $clamped")
    }

    /// 安装 APK
    fun installApp(apkPath: String): ShellResult {
        return executeCommand("pm install -r --user 0 $apkPath")
    }

    /// 卸载 App
    fun uninstallApp(packageName: String): ShellResult {
        return executeCommand("pm uninstall --user 0 $packageName")
    }

    /// 授予运行时权限
    fun grantPermission(packageName: String, permission: String): ShellResult {
        return executeCommand("pm grant $packageName $permission")
    }

    /// 开关蓝牙（需要 BLUETOOTH_ADMIN 权限）
    fun setBluetoothEnabled(enabled: Boolean): ShellResult {
        return executeCommand(if (enabled) "settings put global bluetooth_on 1" else "settings put global bluetooth_on 0")
    }
}

/// Shell 命令执行结果
data class ShellResult(
    val success: Boolean,
    val output: String,
    val error: String
)
