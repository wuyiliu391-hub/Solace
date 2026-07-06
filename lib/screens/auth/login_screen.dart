import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import '../../blocs/auth/auth_bloc.dart';
import '../../repositories/local_storage_repository.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [cs.primary.withOpacity(0.1), cs.surface],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.favorite_rounded, size: 72, color: cs.primary),
                  const SizedBox(height: 12),
                  Text('Solace', style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold, color: cs.primary)),
                  const SizedBox(height: 4),
                  Text('输入 QQ 号，创建你的云端账号',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withOpacity(0.5))),
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: _importBackup,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.file_download_outlined, size: 16, color: cs.primary.withOpacity(0.7)),
                        const SizedBox(width: 4),
                        Text('从备份文件恢复账号',
                          style: TextStyle(fontSize: 13, color: cs.primary.withOpacity(0.7))),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: 220,
                    child: TabBar(
                      controller: _tabCtrl,
                      labelColor: cs.primary,
                      unselectedLabelColor: cs.onSurface.withOpacity(0.5),
                      indicatorColor: cs.primary,
                      tabs: const [
                        Tab(text: '登录'),
                        Tab(text: '注册'),
                      ],
                    ),
                  ),

                  SizedBox(
                    height: 340,
                    child: TabBarView(
                      controller: _tabCtrl,
                      children: [
                        _LoginTab(),
                        _RegisterTab(),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }



  Future<void> _importBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        allowMultiple: false,
      );
      if (result == null || result.files.isEmpty) return;

      final file = File(result.files.single.path!);
      if (!file.existsSync()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('文件不存在'), backgroundColor: Colors.red),
          );
        }
        return;
      }

      final bytes = await file.readAsBytes();

      // 验证文件格式
      final validationResult = await RepositoryProvider.of<LocalStorageRepository>(context)
          .importFromBytes(bytes, validateOnly: true);

      if (!mounted) return;

      final accountInfo = validationResult['accountInfo'] as String?;
      final version = validationResult['version'] as int;
      final exportTime = validationResult['exportTime'] as String?;

      // 显示备份信息并确认导入
      final confirm = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: const Row(
            children: [
              Icon(Icons.restore_page_outlined, size: 22),
              SizedBox(width: 8),
              Text('发现备份文件'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '检测到有效的 Solace 备份文件',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              _infoRow('版本', '$version'),
              _infoRow('导出时间', exportTime ?? '未知'),
              if (accountInfo != null) _infoRow('账号', accountInfo),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.blue[700], size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '导入后自动登录该账号，所有数据将被恢复。',
                        style: TextStyle(fontSize: 12, color: Colors.blue[900]),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.restore, size: 18),
              label: const Text('恢复数据'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
              ),
            ),
          ],
        ),
      );

      if (confirm != true || !mounted) return;

      // 显示加载中
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      try {
        await RepositoryProvider.of<LocalStorageRepository>(context)
            .importFromBytes(bytes);

        if (mounted) {
          Navigator.pop(context); // 关闭加载提示

          // 导入成功后自动登录
          final currentUserId = RepositoryProvider.of<LocalStorageRepository>(context)
              .getString('current_user_id');

          if (currentUserId != null) {
            final user = await RepositoryProvider.of<LocalStorageRepository>(context)
                .getUser(currentUserId);
            if (user != null) {
              context.read<AuthBloc>().add(AuthCheckRequested());

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('数据恢复成功！欢迎回来，${user.nickname}'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            }
          }
        }
      } catch (e) {
        if (mounted) {
          Navigator.pop(context);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('导入失败: $e'), backgroundColor: Colors.red),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法读取备份文件: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _LoginTab extends StatefulWidget {
  const _LoginTab();

  @override
  State<_LoginTab> createState() => _LoginTabState();
}

class _LoginTabState extends State<_LoginTab> {
  final _qqCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscure = true;
  String _qqPreview = '';

  @override
  void dispose() {
    _qqCtrl.dispose();
    _pwCtrl.dispose();
    super.dispose();
  }

  String? _valQq(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return '请输入QQ号';
    if (t.length < 5) return 'QQ号至少5位';
    if (t.length > 11) return 'QQ号不能超过11位';
    if (!RegExp(r'^\d+$').hasMatch(t)) return 'QQ号只能包含数字';
    return null;
  }

  String? _valPw(String? v) {
    if (v == null || v.isEmpty) return '请输入密码';
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    context.read<AuthBloc>().add(AuthLoginRequested(
      qqNumber: _qqCtrl.text.trim(),
      password: _pwCtrl.text,
    ));
  }

  void _forgotPassword() async {
    final qq = _qqCtrl.text.trim();
    if (qq.isEmpty || qq.length < 5) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请先输入QQ号')));
      return;
    }
    final pwCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final obscure = ValueNotifier<bool>(true);
    final obscure2 = ValueNotifier<bool>(true);

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重置密码'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text('重置密码后需重新登录，本地数据不受影响。', style: TextStyle(fontSize: 13, color: Colors.orange[900]))),
                ],
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<bool>(
              valueListenable: obscure,
              builder: (_, o, __) => TextField(
                controller: pwCtrl,
                obscureText: o,
                decoration: InputDecoration(
                  labelText: '新密码',
                  hintText: '至少6位',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffix: GestureDetector(
                    onTap: () => obscure.value = !obscure.value,
                    child: Icon(o ? Icons.visibility_off : Icons.visibility, size: 20),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ValueListenableBuilder<bool>(
              valueListenable: obscure2,
              builder: (_, o, __) => TextField(
                controller: confirmCtrl,
                obscureText: o,
                decoration: InputDecoration(
                  labelText: '确认新密码',
                  border: const OutlineInputBorder(),
                  isDense: true,
                  suffix: GestureDetector(
                    onTap: () => obscure2.value = !obscure2.value,
                    child: Icon(o ? Icons.visibility_off : Icons.visibility, size: 20),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          ElevatedButton(onPressed: () {
            if (pwCtrl.text.length < 6) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('密码至少6位')));
              return;
            }
            if (pwCtrl.text != confirmCtrl.text) {
              ScaffoldMessenger.of(ctx).showSnackBar(const SnackBar(content: Text('两次密码不一致')));
              return;
            }
            Navigator.pop(ctx, true);
          }, child: const Text('确认重置')),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      setState(() => _loading = true);
      context.read<AuthBloc>().add(AuthPasswordResetRequested(
        qqNumber: qq,
        newPassword: pwCtrl.text,
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocListener<AuthBloc, AuthState>(
      listener: (ctx, state) async {
        if (state is AuthAuthenticated) {
          setState(() => _loading = false);
        } else if (state is AuthError) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red[700]),
          );
        }
      },
      child: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            children: [
              if (_qqPreview.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ClipOval(
                    child: Image.network(
                      'https://q1.qlogo.cn/g?b=qq&nk=$_qqPreview&s=640',
                      width: 48, height: 48,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              TextFormField(
                controller: _qqCtrl,
                enabled: !_loading,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                decoration: _inputDeco(cs, 'QQ号', const Icon(Icons.tag)),
                onChanged: (v) => setState(() => _qqPreview = v.trim()),
                validator: _valQq,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pwCtrl,
                enabled: !_loading,
                obscureText: _obscure,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: _inputDeco(cs, '密码', const Icon(Icons.lock_outline), suffix: GestureDetector(
                  onTap: () => setState(() => _obscure = !_obscure),
                  child: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 20),
                )),
                validator: _valPw,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('登录', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              GestureDetector(
                onTap: _forgotPassword,
                child: Text('忘记密码？', style: TextStyle(fontSize: 13, color: cs.primary.withOpacity(0.7))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RegisterTab extends StatefulWidget {
  @override
  State<_RegisterTab> createState() => _RegisterTabState();
}

class _RegisterTabState extends State<_RegisterTab> {
  final _qqCtrl = TextEditingController();
  final _pwCtrl = TextEditingController();
  final _confirmCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _loading = false;
  bool _obscure = true;
  bool _obscure2 = true;
  String _qqPreview = '';

  @override
  void dispose() {
    _qqCtrl.dispose();
    _pwCtrl.dispose();
    _confirmCtrl.dispose();
    super.dispose();
  }

  String? _valQq(String? v) {
    final t = (v ?? '').trim();
    if (t.isEmpty) return '请输入QQ号';
    if (t.length < 5) return 'QQ号至少5位';
    if (t.length > 11) return 'QQ号不能超过11位';
    if (!RegExp(r'^\d+$').hasMatch(t)) return 'QQ号只能包含数字';
    return null;
  }

  String? _valPw(String? v) {
    if (v == null || v.isEmpty) return '请设置密码';
    if (v.length < 6) return '密码至少6位';
    return null;
  }

  String? _valConfirm(String? v) {
    if (v == null || v.isEmpty) return '请确认密码';
    if (v != _pwCtrl.text) return '两次密码不一致';
    return null;
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _loading = true);
    context.read<AuthBloc>().add(AuthRegisterRequested(
      qqNumber: _qqCtrl.text.trim(),
      password: _pwCtrl.text,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return BlocListener<AuthBloc, AuthState>(
      listener: (ctx, state) {
        if (state is AuthAuthenticated) {
          setState(() => _loading = false);
        } else if (state is AuthError) {
          setState(() => _loading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message), backgroundColor: Colors.red[700]),
          );
        }
      },
      child: Form(
        key: _formKey,
        child: Padding(
          padding: const EdgeInsets.only(top: 20),
          child: Column(
            children: [
              if (_qqPreview.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: ClipOval(
                    child: Image.network(
                      'https://q1.qlogo.cn/g?b=qq&nk=$_qqPreview&s=640',
                      width: 48, height: 48,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                  ),
                ),
              TextFormField(
                controller: _qqCtrl,
                enabled: !_loading,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.next,
                decoration: _inputDeco(cs, 'QQ号', const Icon(Icons.tag)),
                onChanged: (v) => setState(() => _qqPreview = v.trim()),
                validator: _valQq,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pwCtrl,
                enabled: !_loading,
                obscureText: _obscure,
                textInputAction: TextInputAction.next,
                decoration: _inputDeco(cs, '设置密码', const Icon(Icons.lock_outline), suffix: GestureDetector(
                  onTap: () => setState(() => _obscure = !_obscure),
                  child: Icon(_obscure ? Icons.visibility_off : Icons.visibility, size: 20),
                )),
                validator: _valPw,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _confirmCtrl,
                enabled: !_loading,
                obscureText: _obscure2,
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _submit(),
                decoration: _inputDeco(cs, '确认密码', const Icon(Icons.lock), suffix: GestureDetector(
                  onTap: () => setState(() => _obscure2 = !_obscure2),
                  child: Icon(_obscure2 ? Icons.visibility_off : Icons.visibility, size: 20),
                )),
                validator: _valConfirm,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity, height: 48,
                child: ElevatedButton(
                  onPressed: _loading ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: _loading
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('注册', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

InputDecoration _inputDeco(ColorScheme cs, String label, Widget icon, {Widget? suffix}) {
  return InputDecoration(
    labelText: label,
    prefixIcon: icon,
    suffix: suffix,
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.outline.withOpacity(0.3)),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: cs.primary, width: 2),
    ),
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
  );
}
