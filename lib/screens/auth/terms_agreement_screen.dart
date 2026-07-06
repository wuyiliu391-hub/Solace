import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../repositories/local_storage_repository.dart';

class TermsAgreementScreen extends StatefulWidget {
  const TermsAgreementScreen({super.key});

  @override
  State<TermsAgreementScreen> createState() => _TermsAgreementScreenState();
}

class _TermsAgreementScreenState extends State<TermsAgreementScreen> {
  bool _agreed = false;
  bool _ageConfirmed = false;

  bool get _canConfirm => _agreed && _ageConfirmed;

  void _onConfirm() {
    if (!_canConfirm) return;
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    storage.setTermsAccepted();
    storage.setAgeConfirmed();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(24, 48, 24, 32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [colorScheme.primary, colorScheme.primary.withOpacity(0.8)],
                ),
              ),
              child: Column(
                children: [
                  const Icon(Icons.favorite_rounded, size: 48, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text('欢迎使用 Solace',
                    style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text('在开始之前，请确认以下内容',
                    style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.85))),
                ],
              ),
            ),
            // Content
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _bullet('本应用为 AI 陪伴聊天工具，所有对话由 AI 模型生成，仅供参考和娱乐'),
                        const SizedBox(height: 10),
                        _bullet('你的所有数据仅保存在设备本地，不会上传至任何服务器'),
                        const SizedBox(height: 10),
                        _bullet('AI 生成的内容不代表任何事实或立场，开发者不承担相关责任'),
                        const SizedBox(height: 10),
                        _bullet('本应用仅限年满 18 周岁用户使用'),
                        const SizedBox(height: 10),
                        _bullet('本应用无官方实名认证资质，仅通过身份证编码规则进行基础年龄筛别，无法防范证件冒用'),
                        const SizedBox(height: 10),
                        _bullet('冒用他人身份证属于违法行为，如虚报年龄或冒用他人证件使用本应用，一切后果由用户本人及监护人承担'),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Checkboxes
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24, height: 24,
                        child: Checkbox(
                          value: _agreed,
                          onChanged: (v) => setState(() => _agreed = v ?? false),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '我已阅读并同意《用户协议》与《隐私政策》',
                          style: TextStyle(fontSize: 14, color: colorScheme.onSurface, height: 1.3),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 24, height: 24,
                        child: Checkbox(
                          value: _ageConfirmed,
                          onChanged: (v) => setState(() => _ageConfirmed = v ?? false),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '我已年满 18 周岁',
                              style: TextStyle(fontSize: 14, color: colorScheme.onSurface, height: 1.3),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '我承诺如实提供年龄信息，虚报年龄导致的后果由我本人承担',
                              style: TextStyle(fontSize: 11, color: colorScheme.onSurface.withOpacity(0.5), height: 1.3),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            // Bottom button
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _canConfirm ? _onConfirm : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canConfirm ? colorScheme.primary : null,
                    foregroundColor: _canConfirm ? colorScheme.onPrimary : null,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: Text('确认并继续',
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600,
                      color: _canConfirm ? null : colorScheme.onSurface.withOpacity(0.3),
                    )),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bullet(String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.check, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13, height: 1.4))),
      ],
    );
  }
}
