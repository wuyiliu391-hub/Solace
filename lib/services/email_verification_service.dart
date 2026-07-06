import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import '../repositories/local_storage_repository.dart';
import '../utils/response_decoder.dart';

class EmailVerificationService {
  static const String _brevoApiUrl = 'https://api.brevo.com/v3/smtp/email';
  static const int _codeLength = 6;
  static const int _codeExpiryMinutes = 10;
  static const int _resendCooldownSeconds = 60;

  final LocalStorageRepository _storage;
  String? _apiKey;
  String? _senderEmail;
  String? _senderName;

  EmailVerificationService(this._storage);

  Future<void> initialize() async {
    _apiKey = await _storage.getBrevoApiKey();
    _senderEmail = await _storage.getBrevoSenderEmail();
    _senderName = await _storage.getBrevoSenderName();
  }

  bool get isConfigured => _apiKey != null && _apiKey!.isNotEmpty;

  String _generateCode() {
    final random = Random.secure();
    final code = List.generate(_codeLength, (_) => random.nextInt(10)).join();
    return code;
  }

  String _getStorageKey(String email) => 'email_vcode_${email.hashCode}';
  String _getTimestampKey(String email) => 'email_vtime_${email.hashCode}';
  String _getCooldownKey(String email) => 'email_vcool_${email.hashCode}';

  Future<bool> canResend(String email) async {
    final cooldownKey = _getCooldownKey(email);
    final lastSent = _storage.getInt(cooldownKey);
    if (lastSent == null) return true;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastSent;
    return elapsed > _resendCooldownSeconds * 1000;
  }

  int getRemainingCooldown(String email) {
    final cooldownKey = _getCooldownKey(email);
    final lastSent = _storage.getInt(cooldownKey);
    if (lastSent == null) return 0;
    final elapsed = DateTime.now().millisecondsSinceEpoch - lastSent;
    final remaining = _resendCooldownSeconds * 1000 - elapsed;
    return remaining > 0 ? (remaining / 1000).ceil() : 0;
  }

  Future<EmailVerificationResult> sendVerificationCode(String email) async {
    if (!isConfigured) {
      return EmailVerificationResult.success(
        message: '服务未配置，使用本地模拟验证码：123456',
        simulated: true,
      );
    }

    if (!await canResend(email)) {
      return EmailVerificationResult.failure(
        '请等待 ${getRemainingCooldown(email)} 秒后重试',
      );
    }

    final code = _generateCode();
    final storageKey = _getStorageKey(email);
    final timestampKey = _getTimestampKey(email);
    final cooldownKey = _getCooldownKey(email);

    try {
      final response = await http.post(
        Uri.parse(_brevoApiUrl),
        headers: {
          'accept': 'application/json',
          'api-key': _apiKey!,
          'content-type': 'application/json',
        },
        body: jsonEncode({
          'sender': {
            'name': _senderName ?? 'Solace',
            'email': _senderEmail ?? 'noreply@solace.app',
          },
          'to': [
            {'email': email},
          ],
          'subject': 'Solace 验证码',
          'htmlContent': _buildEmailTemplate(code),
        }),
      );

      if (response.statusCode == 201 || response.statusCode == 200) {
        await _storage.setString(storageKey, code);
        await _storage.setInt(timestampKey, DateTime.now().millisecondsSinceEpoch);
        await _storage.setInt(cooldownKey, DateTime.now().millisecondsSinceEpoch);

        debugPrint('验证码已发送至 $email: $code');
        return EmailVerificationResult.success(
          message: '验证码已发送',
          simulated: false,
        );
      } else {
        final errBody = await ResponseDecoder.decode(response.headers['content-type'], response.bodyBytes);
        debugPrint('Brevo API 错误: ${response.statusCode} $errBody');
        return EmailVerificationResult.failure(
          '发送失败，请稍后重试 (${response.statusCode})',
        );
      }
    } catch (e) {
      debugPrint('发送验证码异常: $e');
      return EmailVerificationResult.failure('网络错误，请检查网络连接');
    }
  }

  Future<EmailVerificationResult> verifyCode(String email, String inputCode) async {
    final storageKey = _getStorageKey(email);
    final timestampKey = _getTimestampKey(email);

    final storedCode = _storage.getString(storageKey);
    if (storedCode == null) {
      return EmailVerificationResult.failure('验证码已过期，请重新获取');
    }

    final timestamp = _storage.getInt(timestampKey);
    if (timestamp != null) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - timestamp;
      if (elapsed > _codeExpiryMinutes * 60 * 1000) {
        await _storage.remove(storageKey);
        await _storage.remove(timestampKey);
        return EmailVerificationResult.failure('验证码已过期，请重新获取');
      }
    }

    if (storedCode != inputCode.trim()) {
      return EmailVerificationResult.failure('验证码错误');
    }

    await _storage.remove(storageKey);
    await _storage.remove(timestampKey);

    return EmailVerificationResult.success(message: '验证成功');
  }

  String _buildEmailTemplate(String code) {
    return '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Solace 验证码</title>
</head>
<body style="margin:0;padding:0;background-color:#f5f5f5;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Roboto,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" border="0">
    <tr>
      <td align="center" style="padding:40px 20px;">
        <table width="100%" max-width="480" cellpadding="0" cellspacing="0" border="0" style="max-width:480px;background:#ffffff;border-radius:16px;overflow:hidden;box-shadow:0 4px 20px rgba(0,0,0,0.08);">
          <tr>
            <td style="padding:40px 32px 24px;text-align:center;">
              <div style="font-size:32px;margin-bottom:16px;color:#6366f1;">S</div>
              <h1 style="margin:0;font-size:22px;color:#1a1a1a;font-weight:600;">Solace 验证码</h1>
            </td>
          </tr>
          <tr>
            <td style="padding:0 32px 24px;text-align:center;">
              <p style="margin:0 0 24px;font-size:14px;color:#666;line-height:1.6;">您正在进行邮箱验证，请在应用中输入以下验证码：</p>
              <div style="display:inline-block;background:#f8f4ff;border-radius:12px;padding:20px 40px;margin-bottom:24px;">
                <span style="font-size:36px;font-weight:700;color:#7c3aed;letter-spacing:8px;font-family:'Courier New',monospace;">$code</span>
              </div>
              <p style="margin:0;font-size:13px;color:#999;">验证码有效期 10 分钟，请勿泄露给他人</p>
            </td>
          </tr>
          <tr>
            <td style="padding:0 32px 40px;text-align:center;">
              <p style="margin:0;font-size:12px;color:#bbb;line-height:1.5;">如非本人操作，请忽略此邮件。<br>Solace 团队</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>
''';
  }
}

class EmailVerificationResult {
  final bool success;
  final String message;
  final bool simulated;

  EmailVerificationResult._({required this.success, required this.message, this.simulated = false});

  factory EmailVerificationResult.success({required String message, bool simulated = false}) {
    return EmailVerificationResult._(success: true, message: message, simulated: simulated);
  }

  factory EmailVerificationResult.failure(String message) {
    return EmailVerificationResult._(success: false, message: message);
  }
}
