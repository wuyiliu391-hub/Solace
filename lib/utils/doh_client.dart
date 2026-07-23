import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// DNS-over-HTTPS 解析器
///
/// 绕过系统 DNS 拦截（如国内网络无法解析境外域名），
/// 通过 Cloudflare 的 DoH 接口直接解析域名。
class DohResolver {
  DohResolver._();

  /// Cloudflare DNS-over-HTTPS 端点
  static const String _dohEndpoint = 'https://cloudflare-dns.com/dns-query';

  /// 尝试通过 DoH 解析 [host] 的 IPv4 地址。
  ///
  /// 返回第一个 A 记录 IP，解析失败返回 `null`。
  static Future<String?> resolveIPv4(String host) async {
    // 已经是 IP 直连，不需要解析
    if (_isIpAddress(host)) return host;

    try {
      final uri = Uri.parse(_dohEndpoint).replace(
        queryParameters: {
          'name': host,
          'type': 'A',
        },
      );

      final response = await http
          .get(uri, headers: {'Accept': 'application/dns-json'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final answer = json['Answer'] as List<dynamic>?;
      if (answer == null || answer.isEmpty) return null;

      for (final item in answer) {
        if (item is Map<String, dynamic> && item['type'] == 1) {
          return item['data'] as String?;
        }
      }
      return null;
    } catch (e) {
      debugPrint('DohResolver: resolve failed for $host — $e');
      return null;
    }
  }

  /// 带 DoH 回退的 HTTP GET
  static Future<http.Response> get(Uri uri, {Map<String, String>? headers}) async {
    try {
      return await http.get(uri, headers: headers).timeout(const Duration(seconds: 15));
    } on SocketException catch (_) {
      // DNS 解析失败，走 DoH
      final resolved = await _dohResolveAndRequest(uri, headers: headers, method: 'GET');
      if (resolved != null) return resolved;
      rethrow;
    }
  }

  /// 带 DoH 回退的 HTTP POST
  static Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    dynamic body,
  }) async {
    try {
      return await http
          .post(uri, headers: headers, body: body)
          .timeout(const Duration(seconds: 30));
    } on SocketException catch (_) {
      // DNS 解析失败，走 DoH
      final resolved = await _dohResolveAndRequest(uri, headers: headers, body: body, method: 'POST');
      if (resolved != null) return resolved;
      rethrow;
    }
  }

  /// DoH 解析后用 IP 直连
  static Future<http.Response?> _dohResolveAndRequest(
    Uri uri, {
    Map<String, String>? headers,
    dynamic body,
    required String method,
  }) async {
    final host = uri.host;
    final ip = await resolveIPv4(host);
    if (ip == null) return null;

    // 替换 host 为 IP，保留端口与路径
    final ipUri = uri.replace(host: ip);
    final mergedHeaders = Map<String, String>.from(headers ?? {});
    mergedHeaders['Host'] = host; // 必须保留原始 Host

    debugPrint('DohResolver: $method $host → $ip');

    if (method == 'GET') {
      return http.get(ipUri, headers: mergedHeaders).timeout(const Duration(seconds: 15));
    } else {
      return http
          .post(ipUri, headers: mergedHeaders, body: body)
          .timeout(const Duration(seconds: 30));
    }
  }

  static bool _isIpAddress(String host) {
    return RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(host);
  }
}
