# main.dart 机械拆分脚本：把私有 Widget 整类搬进 part 文件（同库，私有名可互访）。
# 行号来自事前分析（1-based，闭区间）：
#   imports+main+_MiniFallback: 1-182, 1541-1549 保留在 main.dart
#   _AuthGate(_State):      184-342  -> lib/src/app/auth_gate.dart
#   _MainShell(_State):     344-1002 -> lib/src/app/main_shell.dart
#   _GlobalRebuildBanner:   1551-1596 -> lib/src/app/main_shell.dart（仅被 _MainShellState 引用）
#   _DiscoverPage(_State):  1004-1115 -> lib/src/app/discover_page.dart
#   _ChatLauncher(_State):  1117-1155 -> lib/src/app/solace_app.dart（仅被 SolaceApp 引用）
#   SolaceApp:              1157-1539 -> lib/src/app/solace_app.dart
import io, os

ROOT = r"c:\Users\Administrator\Desktop\Solace"
SRC = os.path.join(ROOT, "lib", "main.dart")

with io.open(SRC, "r", encoding="utf-8") as f:
    lines = f.readlines()  # 0-based index = line-1

def take(a, b):
    """1-based 闭区间取行"""
    return "".join(lines[a - 1 : b])

PARTS = [
    ("auth_gate.dart", 184, 342, "// 登录闸门：首启合规弹窗链 + 版本提示，全部通过后进入主界面。"),
    ("main_shell.dart", 344, 1002, "// 主界面壳：微信风格底部导航 + 页面缓存 + 路由分发 + 前台主动消息心跳。"),
    ("discover_page.dart", 1004, 1115, "// 发现页：功能 / 娱乐互动双 Tab。"),
    ("solace_app.dart", 1117, 1539, "// 应用根组件（含 _ChatLauncher 路由页）：仓库/BLoC 注入 + 主题 + 路由表。"),
]

banner_parts = []
for name, a, b, doc in PARTS:
    body = take(a, b)
    if name == "solace_app.dart":
        # 1117-1155(_ChatLauncher) + 1157-1539(SolaceApp)，中间无缝拼接
        pass
    if name == "main_shell.dart":
        body += "\n" + take(1551, 1596)  # _GlobalRebuildBanner 一并搬入
    header = (
        doc + "\n"
        "// 本文件是 main.dart 的 part，仅与其共同构成一个库，不可单独 import。\n"
        "\n"
        "part of '../../main.dart';\n"
        "\n"
    )
    out_dir = os.path.join(ROOT, "lib", "src", "app")
    os.makedirs(out_dir, exist_ok=True)
    with io.open(os.path.join(out_dir, name), "w", encoding="utf-8", newline="") as f:
        f.write(header + body.strip("\n") + "\n")
    rel = f"part 'src/app/{name}';"
    banner_parts.append(rel)
    print(f"wrote {name}: lines {a}-{b}")

# 重写 main.dart：保留 1-182 + _MiniFallback(1541-1549)，插入 part 指令
keep_head = take(1, 182).rstrip("\n")
mini = take(1541, 1549).rstrip("\n")

# part 指令必须位于 import 之后、声明之前，按字母序列出
part_block = "\n".join(banner_parts)

new_main = (
    keep_head
    + "\n\n"
    + part_block
    + "\n\n"
    + mini
    + "\n"
)

with io.open(SRC, "w", encoding="utf-8", newline="") as f:
    f.write(new_main)

print("main.dart rewritten, lines:", new_main.count("\n") + 1)
