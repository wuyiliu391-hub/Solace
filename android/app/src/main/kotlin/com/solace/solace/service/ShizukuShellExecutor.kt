package com.solace.solace.service

import android.content.Context
import android.util.Log
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Shizuku 支持的 Shell 执行器 — DEBUGGER 权限级别
 *
 * 对标 Operit DebuggerShellExecutor。
 *
 * ## 权限机制
 * Shizuku 使用 UserService 机制：Shizuku 服务以 UID 2000 (shell) 运行。
 * 当 App 通过 Shizuku binder 调用时，请求会被转发到 shell 用户进程执行。
 * 所以即使 App 自身是普通 UID，通过 Shizuku 执行的 Runtime.exec 也拥有 shell 权限。
 *
 * ## 关键 API（Shizuku 13.x）
 * - Shizuku.pingBinder() — 检查 Shizuku 服务是否在运行
 * - Shizuku.checkSelfPermission() — 检查当前 App 是否已授权
 * - Shizuku.requestPermission(requestCode) — 请求授权（弹出系统对话框）
 * - Shizuku.addRequestPermissionResultListener() — 监听授权结果
 * - Shizuku.addBinderReceivedListener() — 监听 binder 连接
 * - Shizuku.addBinderDeadListener() — 监听 binder 断开
 *
 * ## 注意
 * 通过 Runtime.exec 在 Shizuku 上下文中执行命令需要 Shizuku UserService 支持。
 * 当前版本先检查 Shizuku 状态，命令执行尝试 Runtime.exec。
 * 如果 Runtime.exec 权限不足（大部分 ROM 确实不足），后续需要
 * 通过 IShizukuService.newProcess() AIDL 接口真正执行 shell 命令。
 */
class ShizukuShellExecutor : SolaceShellExecutor {
    companion object {
        private const val TAG = "ShizukuShellExec"
    }

    override val permissionLevel = SolacePermissionLevel.DEBUGGER

    override fun isAvailable(context: Context): Boolean {
        return try {
            Shizuku.pingBinder()
        } catch (e: Exception) {
            false
        }
    }

    override fun hasPermission(context: Context): Boolean {
        return try {
            Shizuku.checkSelfPermission() == android.content.pm.PackageManager.PERMISSION_GRANTED
        } catch (e: Exception) {
            false
        }
    }

    /**
     * 请求 Shizuku 权限。
     * 注意：必须在 Activity 中调用 Shizuku.addRequestPermissionResultListener 后才能收到回调。
     * 这个方法只是触发请求，结果由 Activity 层处理。
     */
    override fun requestPermission(context: Context): Boolean {
        return try {
            Shizuku.requestPermission(100)
            true
        } catch (e: Exception) {
            Log.w(TAG, "Shizuku requestPermission failed", e)
            false
        }
    }

    override suspend fun executeCommand(command: String): SolaceShellExecutor.CommandResult {
        try {
            val process = if (command.contains("|") || command.contains("&&") || command.contains(";")) {
                Runtime.getRuntime().exec(arrayOf("sh", "-c", command))
            } else {
                Runtime.getRuntime().exec(command)
            }

            val stdout = BufferedReader(InputStreamReader(process.inputStream)).readText()
            val stderr = BufferedReader(InputStreamReader(process.errorStream)).readText()
            val exitCode = process.waitFor()

            Log.d(TAG, "exit=$exitCode cmd=${command.take(80)}")
            return SolaceShellExecutor.CommandResult(
                success = exitCode == 0,
                stdout = stdout,
                stderr = stderr,
                exitCode = exitCode
            )
        } catch (e: Exception) {
            Log.e(TAG, "Failed: ${command.take(80)}", e)
            return SolaceShellExecutor.CommandResult(
                success = false,
                stderr = e.message ?: "Unknown error",
                exitCode = -1
            )
        }
    }
}