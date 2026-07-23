package com.solace.solace.service

import android.util.Log
import java.io.BufferedReader
import java.io.InputStreamReader

/**
 * Binder Service — 由 Shizuku 以 shell 身份启动
 *
 * 在 Shizuku 的 UserService 机制下运行，UID 2000 (shell)。
 * 提供真正有权限的 shell 命令执行能力：
 * - input tap/swipe/keyevent
 * - screencap -p
 * - uiautomator dump
 *
 * Shizuku 会通过 app_process 加载这个类，运行在一个独立的 shell 进程中。
 * Flutter 侧通过 AIDL binder 与之通信。
 */
class SolaceShellService(private val serviceContext: android.content.Context) {

    companion object {
        private const val TAG = "SolaceShellService"
    }

    /**
     * 执行 shell 命令
     * @return Pair<exitCode, output>
     */
    fun executeCommand(command: String): Pair<Int, String> {
        return try {
            val process = if (command.contains("|") || command.contains("&&") || command.contains(";")) {
                Runtime.getRuntime().exec(arrayOf("sh", "-c", command))
            } else {
                Runtime.getRuntime().exec(command)
            }

            val stdout = BufferedReader(InputStreamReader(process.inputStream)).readText()
            val stderr = BufferedReader(InputStreamReader(process.errorStream)).readText()
            val exitCode = process.waitFor()

            val output = if (stdout.isNotBlank()) stdout else stderr
            Log.d(TAG, "Command: ${command.take(80)} → exit=$exitCode")
            Pair(exitCode, output)
        } catch (e: Exception) {
            Log.e(TAG, "Command failed: ${command.take(80)}", e)
            Pair(-1, "Error: ${e.message}")
        }
    }

    /** 点击屏幕坐标 */
    fun tap(x: Int, y: Int): String {
        val (code, out) = executeCommand("input tap $x $y")
        return if (code == 0) "ok" else "failed: $out"
    }

    /** 滑动 */
    fun swipe(startX: Int, startY: Int, endX: Int, endY: Int, duration: Int = 300): String {
        val (code, out) = executeCommand("input swipe $startX $startY $endX $endY $duration")
        return if (code == 0) "ok" else "failed: $out"
    }

    /** 按键 */
    fun keyEvent(keyCode: Int): String {
        val (code, out) = executeCommand("input keyevent $keyCode")
        return if (code == 0) "ok" else "failed: $out"
    }

    /** 输入文本 */
    fun text(text: String): String {
        val escaped = text.replace("'", "'\\''")
        val (code, out) = executeCommand("input text '$escaped'")
        return if (code == 0) "ok" else "failed: $out"
    }

    /** 截图（不需要 MediaProjection！） */
    fun screencap(path: String): String {
        val (code, out) = executeCommand("screencap -p $path")
        return if (code == 0) "ok:$path" else "failed: $out"
    }

    /** UI 层次结构 dump */
    fun uiDump(path: String): String {
        val (code, out) = executeCommand("uiautomator dump $path")
        return if (code == 0) "ok:$path" else "failed: $out"
    }

    /** 获取当前前台 Activity */
    fun currentActivity(): String {
        val (_, out) = executeCommand("dumpsys window windows | grep -E 'mCurrentFocus'")
        return out.trim()
    }
}