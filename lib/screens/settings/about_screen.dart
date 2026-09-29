import 'package:flutter/material.dart';
import '../../config/constants.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../services/update_service.dart';
import '../../widgets/update_dialog.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  bool _checking = false;


  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('关于 Solace'),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // App info
          Center(
            child: Column(
              children: [
                Icon(Icons.favorite_rounded,
                    size: 64, color: colorScheme.primary),
                const SizedBox(height: 16),
                const Text('Solace',
                    style:
                        TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text('版本 $AppVersion.version（Build $AppVersion.build）',
                    style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurface.withOpacity(0.5))),
                const SizedBox(height: 8),
                Text('你的 AI 陪伴伙伴',
                    style: TextStyle(
                        fontSize: 16,
                        color: colorScheme.onSurface.withOpacity(0.6))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: TextButton.icon(
              onPressed: _checking ? null : _checkUpdate,
              icon: _checking
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.system_update_outlined, size: 18),
              label: Text(_checking ? '检查中...' : '检查更新'),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              onPressed: _openAdminStats,
              icon: const Icon(Icons.bar_chart_rounded, size: 18),
              label: const Text('后台统计'),
            ),
          ),
          const SizedBox(height: 20),
          // Privacy policy
          _sectionTitle('隐私政策', colorScheme),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _policyItem(
                    '1. 信息收集', '本应用不收集任何个人信息。你输入的昵称仅用于本地显示，不会上传至任何服务器。'),
                _policyItem('2. 数据存储',
                    '所有数据（聊天记录、角色配置、设置等）仅保存在你的设备本地存储中。应用不使用任何云端数据库或远程服务器。'),
                _policyItem('3. API Key 安全',
                    '你在「设置助手」中配置的 API Key 仅保存在本地设备，用于直接向 AI 模型提供商发送请求。应用不会读取或上传你的 API Key。'),
                _policyItem('4. 网络请求',
                    '应用仅向你自己配置的 AI API 地址发送网络请求（用于生成 AI 回复和朋友圈内容）。不向任何其他第三方服务器发送数据。'),
                _policyItem('5. 权限说明',
                    '本应用可能请求存储权限（用于保存图片/头像）和通知权限（用于接收 AI 主动消息）。这些权限仅用于实现功能，不会滥用。'),
                _policyItem('6. 第三方服务', '本应用不集成任何第三方分析、广告或追踪 SDK。'),
                _policyItem('7. 年龄限制与合规声明',
                    '本应用实行年龄分级制度：14岁以下禁止使用；15-18岁可使用非恋人陪伴功能（恋人模式及成人内容不可用）；18岁以上可使用全部功能。开发者目前为未成年人，无法对接官方实名认证系统，请用户如实选择年龄段。刻意虚报年龄导致的意外风险和事故，责任全部由使用者和监护人承担。'),
                _policyItem('7.1 实名认证能力声明',
                    '本应用开发者目前为未成年人，无法接入官方实名认证系统，仅通过用户自主申报年龄进行年龄判定，无法联网核验用户身份真伪。'),
                _policyItem('7.2 虚报责任',
                    '刻意虚报年龄，导致意外风险和事故，责任全部由使用者和监护人承担。如用户为14岁以下却使用本应用，或15-18岁用户使用恋人模式功能，一切法律后果由用户本人及其监护人承担，与本应用开发者无关。'),
                _policyItem('8. AI身份标识',
                    '本应用所有AI生成内容均在聊天界面标注"AI生成"标识。用户应知悉正在与人工智能服务而非自然人进行互动，不应将AI内容视为真实人类的观点、情感或承诺。'),
                _policyItem('9. 使用时长提醒',
                    '为防范过度依赖和沉迷，本应用将在用户连续使用每满2小时时弹出提醒，建议用户注意休息和现实生活社交。'),
                _policyItem(
                    '10. 协议更新', '本隐私政策可能不时更新。更新后的政策将在应用内公布。继续使用即视为同意更新后的政策。'),
              ],
            ),
          ),
          const SizedBox(height: 24),
          // Disclaimer
          _sectionTitle('免责声明', colorScheme),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.08),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.orange.withOpacity(0.2)),
            ),
            child: Text(
              '本应用生成的 AI 内容仅供参考和娱乐，不代表任何事实或立场。'
              'AI 模型可能产生不准确或不适当的回应，开发者对此不承担责任。'
              '请不要将 AI 的建议视为专业意见。如你有心理或情绪困扰，请寻求专业帮助。',
              style: TextStyle(
                  fontSize: 13, color: Colors.orange.shade800, height: 1.6),
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _sectionTitle(String title, ColorScheme colorScheme) {
    return Text(title,
        style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: colorScheme.primary));
  }

  Future<void> _openAdminStats() async {
    // 开源版本：移除硬编码 Token，管理员需自行配置
    final uri = Uri.parse(AppConfig.adminStatsUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('无法打开浏览器')),
        );
      }
    }
  }

  Future<void> _checkUpdate() async {
    setState(() => _checking = true);
    final info = await UpdateService().checkForUpdate(
      currentVersion: AppVersion.version,
      currentBuild: AppVersion.build,
    );
    if (mounted) {
      setState(() => _checking = false);
      final actuallyHasUpdate = info.hasUpdate &&
          (info.buildNumber > AppVersion.build ||
           _versionCompare(info.latestVersion, AppVersion.version) > 0);
      if (actuallyHasUpdate) {
        showDialog(
          context: context,
          barrierDismissible: !info.forceUpdate,
          builder: (_) => UpdateDialog(info: info),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已是最新版本')),
        );
      }
    }
  }

  int _versionCompare(String v1, String v2) {
    final p1 = v1.split('.').map(int.tryParse).toList();
    final p2 = v2.split('.').map(int.tryParse).toList();
    for (int i = 0; i < 3; i++) {
      final a = (i < p1.length ? p1[i] : 0) ?? 0;
      final b = (i < p2.length ? p2[i] : 0) ?? 0;
      if (a > b) return 1;
      if (a < b) return -1;
    }
    return 0;
  }

  Widget _policyItem(String title, String content) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style:
                  const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(content,
              style: const TextStyle(
                  fontSize: 12, height: 1.5, color: Colors.black87)),
        ],
      ),
    );
  }
}
