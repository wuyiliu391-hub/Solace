package com.solace.solace.service

import android.content.Context

interface SolaceShellExecutor {
    data class CommandResult(
        val success: Boolean,
        val stdout: String = "",
        val stderr: String = "",
        val exitCode: Int = -1
    )

    val permissionLevel: SolacePermissionLevel
    suspend fun executeCommand(command: String): CommandResult
    fun isAvailable(context: Context): Boolean
    fun hasPermission(context: Context): Boolean
    fun requestPermission(context: Context): Boolean
}