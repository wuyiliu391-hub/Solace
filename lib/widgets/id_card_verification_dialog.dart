import 'package:flutter/material.dart';
import '../utils/id_card_validator.dart';

class IdCardVerificationDialog extends StatefulWidget {
  const IdCardVerificationDialog({super.key});

  @override
  State<IdCardVerificationDialog> createState() => _IdCardVerificationDialogState();
}

class _IdCardVerificationDialogState extends State<IdCardVerificationDialog> {
  final _controller = TextEditingController();
  String? _errorText;
  bool _isVerifying = false;
  bool _obscureText = true;

  void _verify() {
    setState(() {
      _isVerifying = true;
      _errorText = null;
    });

    final idCard = _controller.text.trim().toUpperCase();

    final result = IdCardValidator.validate(idCard);

    setState(() => _isVerifying = false);

    if (!result.isValid) {
      setState(() => _errorText = result.errorMessage);
      return;
    }

    if (!result.isAdult) {
      setState(() => _errorText = result.errorMessage);
      return;
    }

    final birthDate = result.birthDate;
    if (birthDate == null) {
      setState(() => _errorText = '无法解析出生日期');
      return;
    }

    final age = _calculateAge(birthDate);

    _controller.clear();

    Navigator.pop(context, age);
  }

  int _calculateAge(DateTime birthDate) {
    final now = DateTime.now();
    int age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age--;
    }
    return age;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return PopScope(
      canPop: false,
      child: Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.verified_user_outlined, size: 28, color: cs.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '身份验证',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                '请输入您的身份证号码进行年龄验证。验证完成后，系统仅记录您的周岁数字，不会保存身份证号码本身。',
                style: TextStyle(
                  fontSize: 14,
                  color: cs.onSurface.withOpacity(0.7),
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _controller,
                keyboardType: TextInputType.text,
                maxLength: 18,
                obscureText: _obscureText,
                textCapitalization: TextCapitalization.characters,
                decoration: InputDecoration(
                  hintText: '请输入18位身份证号码',
                  counterText: '',
                  prefixIcon: const Icon(Icons.badge_outlined),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscureText ? Icons.visibility_off : Icons.visibility,
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() => _obscureText = !_obscureText);
                    },
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  errorText: _errorText,
                ),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 8),
              Text(
                '身份证号码仅在前端内存中运算，验证完成后立即清空，仅保留周岁数字用于功能限制。',
                style: TextStyle(
                  fontSize: 12,
                  color: cs.onSurface.withOpacity(0.5),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: FilledButton(
                  onPressed: _isVerifying ? null : _verify,
                  child: _isVerifying
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('验证', style: TextStyle(fontSize: 15)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: OutlinedButton(
                  onPressed: () => Navigator.pop(context, null),
                  child: const Text('取消', style: TextStyle(fontSize: 15)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
