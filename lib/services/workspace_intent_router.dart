/// 工作区任务意图路由。只拦截明确的工作请求，不拦截普通剧情聊天。
class WorkspaceIntentRouter {
  WorkspaceIntentRouter._();

  static bool isTask(String message) {
    final text = message.trim();
    if (text.isEmpty || text.length > 500) return false;
    if (RegExp(r'^(?:剧情里|故事里|小说里|我梦到|假如)', caseSensitive: false)
        .hasMatch(text)) {
      return false;
    }
    return RegExp(
      r'(?:读取|读一下|查看|分析|检查|写入|写到|创建|新建|修改|编辑|重构|修复|删除|运行|执行|测试|编译|构建|实现|开发|代码|文件|项目|仓库|工作区|read_file|write_file|edit_file|run_command|agent|subagent)',
      caseSensitive: false,
    ).hasMatch(text);
  }
}
