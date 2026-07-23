package com.solace.solace.service

import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.RemoteException
import android.util.Log
import moe.shizuku.server.IShizukuService
import rikka.shizuku.Shizuku
import java.io.BufferedReader
import java.io.InputStreamReader
import java.io.FileInputStream

/**
 * Shizuku Shell 命令执行器 — 通过 IShizukuService.newProcess AIDL 以 UID 2000 执行命令
 *
 * 对标 Operit DebuggerShellExecutor。
 * 通过 Shizuku.addBinderReceivedListener 获取 binder，
 * 然后 IShizukuService.Stub.asInterface(binder).newProcess(cmd, env, dir)
 * 在 Shizuku 服务进程中以 shell 身份创建子进程。
 */
object ShizukuShell {
    private const val TAG = "ShizukuShell"
    private var service: IShizukuService? = null

    private val binderListener = Shizuku.OnBinderReceivedListener {
        try {
            val binder = Shizuku.getBinder()
            if (binder != null && binder.isBinderAlive && binder.pingBinder()) {
                service = IShizukuService.Stub.asInterface(binder)
                Log.i(TAG, "Shizuku binder obtained: ${service != null}")
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to get Shizuku service", e)
        }
    }

    private val deadListener = Shizuku.OnBinderDeadListener {
        service = null
        Log.w(TAG, "Shizuku binder dead")
    }

    private var initialized = false

    @Synchronized
    fun init() {
        if (initialized) return
        initialized = true
        Shizuku.addBinderReceivedListener(binderListener)
        Shizuku.addBinderDeadListener(deadListener)
        // 尝试立即获取
        try {
            binderListener.onBinderReceived()
        } catch (_: Exception) {}
    }

    fun isReady(): Boolean = service != null

    data class ShellResult(
        val exitCode: Int,
        val stdout: String,
        val stderr: String
    )

    /**
     * 通过 Shizuku IShizukuService.newProcess 执行 shell 命令
     *
     * 对标 Operit DebuggerShellExecutor.executeCommandDirect()。
     * newProcess() 返回的是 AIDL 远程代理对象（非 java.lang.Process），
     * 必须通过反射调用其 getInputStream/getErrorStream/waitFor 方法。
     * 直接 .inputStream 访问会失败，因为代理对象上没有该 Java 属性。
     */
    fun exec(command: String): ShellResult {
        val svc = service
        if (svc == null) return ShellResult(-1, "", "Shizuku service not bound")

        // 包含 shell 操作符（管道、变量替换、重定向等）→ 必须用 sh -c
        val needsShell = command.contains("|") || command.contains("$") ||
                command.contains("&&") || command.contains(";") ||
                command.contains(">") || command.contains("<") ||
                command.contains("`")

        val cmdArray = if (needsShell) {
            arrayOf("sh", "-c", command)
        } else {
            parseCommand(command)
        }

        var process: Any? = null
        try {
            process = svc.newProcess(cmdArray, null, null)
            if (process == null) {
                Log.e(TAG, "newProcess returned null for: ${command.take(80)}")
                return ShellResult(-1, "", "newProcess returned null")
            }

            val processClass = process.javaClass

            // 通过反射获取 ParcelFileDescriptor（对标 Operit）
            val stdoutFd = processClass.getMethod("getInputStream").invoke(process) as? ParcelFileDescriptor
            val stderrFd = processClass.getMethod("getErrorStream").invoke(process) as? ParcelFileDescriptor

            val stdout = if (stdoutFd != null) {
                BufferedReader(InputStreamReader(FileInputStream(stdoutFd.fileDescriptor))).use { it.readText() }
            } else ""

            val stderr = if (stderrFd != null) {
                BufferedReader(InputStreamReader(FileInputStream(stderrFd.fileDescriptor))).use { it.readText() }
            } else ""

            val exitCode = processClass.getMethod("waitFor").invoke(process) as Int

            Log.d(TAG, "exec: ${command.take(80)} → exit=$exitCode stdout=${stdout.take(100)} stderr=${stderr.take(100)}")
            return ShellResult(exitCode, stdout, stderr)
        } catch (e: RemoteException) {
            Log.e(TAG, "Shizuku remote call failed: ${command.take(80)}", e)
            return ShellResult(-1, "", "RemoteException: ${e.message}")
        } catch (e: Exception) {
            Log.e(TAG, "Command failed: ${command.take(80)}", e)
            return ShellResult(-1, "", e.message ?: "Unknown error")
        } finally {
            // 安全关闭文件描述符（对标 Operit）
            if (process != null) {
                try {
                    (process.javaClass.getMethod("getInputStream").invoke(process) as? ParcelFileDescriptor)?.close()
                } catch (_: Exception) {}
                try {
                    (process.javaClass.getMethod("getErrorStream").invoke(process) as? ParcelFileDescriptor)?.close()
                } catch (_: Exception) {}
            }
        }
    }

    /**
     * 智能解析命令行，正确处理引号（对标 Operit parseCommand）
     */
    private fun parseCommand(command: String): Array<String> {
        val result = mutableListOf<String>()
        val currentArg = StringBuilder()
        var i = 0
        var inSingleQuotes = false
        var inDoubleQuotes = false

        while (i < command.length) {
            val c = command[i]

            if (i < command.length - 1 && c == '\\') {
                val nextChar = command[i + 1]
                if (nextChar == '\'' || nextChar == '"') {
                    currentArg.append(nextChar)
                    i += 2
                    continue
                }
            }

            if (c == '\'' && !inDoubleQuotes) {
                inSingleQuotes = !inSingleQuotes
                i++
                continue
            }

            if (c == '"' && !inSingleQuotes) {
                inDoubleQuotes = !inDoubleQuotes
                i++
                continue
            }

            if (c == ' ' && !inSingleQuotes && !inDoubleQuotes) {
                if (currentArg.isNotEmpty()) {
                    result.add(currentArg.toString())
                    currentArg.clear()
                }
                i++
                continue
            }

            currentArg.append(c)
            i++
        }

        if (currentArg.isNotEmpty()) {
            result.add(currentArg.toString())
        }

        return result.toTypedArray()
    }
}