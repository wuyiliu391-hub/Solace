package com.solace.solace.service

enum class SolacePermissionLevel(val displayName: String) {
    STANDARD("标准"),
    ACCESSIBILITY("无障碍"),
    DEBUGGER("调试器(Shizuku)"),
    ADMIN("设备管理员"),
    ROOT("Root")
}