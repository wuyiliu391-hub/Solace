package com.solace.solace.service

import android.content.Context
import android.util.Log

class SolaceDeviceController(private val context: Context) {
    companion object {
        private const val TAG = "SolaceDeviceCtrl"

        @Volatile
        var instance: SolaceDeviceController? = null
    }

    private val shizukuExecutor = ShizukuShellExecutor()

    fun getExecutor(): SolaceShellExecutor? {
        if (shizukuExecutor.isAvailable(context) && shizukuExecutor.hasPermission(context)) {
            return shizukuExecutor
        }
        return null
    }

    fun isShizukuReady(): Boolean {
        return shizukuExecutor.isAvailable(context) && shizukuExecutor.hasPermission(context)
    }

    fun isShizukuAvailable(): Boolean {
        return shizukuExecutor.isAvailable(context)
    }

    // ═══ 所有 shell 命令都通过 ShizukuShell（IShizukuService AIDL）执行 ═══
    // 因为 Runtime.exec 没有 shell UID，必须通过 Shizuku 的 newProcess 提权

    suspend fun inputTap(x: Int, y: Int): SolaceShellExecutor.CommandResult = shizukuShellExec("input tap $x $y")

    suspend fun inputSwipe(startX: Int, startY: Int, endX: Int, endY: Int, duration: Int = 300): SolaceShellExecutor.CommandResult =
        shizukuShellExec("input swipe $startX $startY $endX $endY $duration")

    suspend fun inputKeyEvent(keyCode: Int): SolaceShellExecutor.CommandResult =
        shizukuShellExec("input keyevent $keyCode")

    suspend fun inputText(text: String): SolaceShellExecutor.CommandResult {
        val escaped = text.replace("'", "'\\''")
        return shizukuShellExec("input text '$escaped'")
    }

    suspend fun screencap(outputPath: String): SolaceShellExecutor.CommandResult =
        shizukuShellExec("screencap -p $outputPath")

    suspend fun executeShell(command: String): SolaceShellExecutor.CommandResult =
        shizukuShellExec(command)

    /** 通过 ShizukuShell (IShizukuService.newProcess) 执行命令 */
    private fun shizukuShellExec(command: String): SolaceShellExecutor.CommandResult {
        if (!ShizukuShell.isReady()) {
            return SolaceShellExecutor.CommandResult(
                success = false, stderr = "ShizukuShell not ready", exitCode = -1
            )
        }
        return try {
            val r = ShizukuShell.exec(command)
            SolaceShellExecutor.CommandResult(
                success = r.exitCode == 0,
                stdout = r.stdout,
                stderr = r.stderr,
                exitCode = r.exitCode
            )
        } catch (e: Exception) {
            Log.e(TAG, "ShizukuShell exec failed: ${command.take(80)}", e)
            SolaceShellExecutor.CommandResult(
                success = false, stderr = e.message ?: "error", exitCode = -1
            )
        }
    }
}