// 【对标来源：KouriChat-1.4.3.2 — data/config/config.json.template API配置】
// 1:1 转译自 KouriChat 配置面板为 Flutter 设置页面

import "dart:convert";
import "dart:io";

import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";
import "../../../models/app_config_data.dart";

/// API 配置页面（对标 KouriChat config 面板）
/// 支持用户自由配置 API Key、Base URL、模型等
class ApiConfigScreen extends StatefulWidget {
  const ApiConfigScreen({super.key});

  @override
  State<ApiConfigScreen> createState() => _ApiConfigScreenState();
}

class _ApiConfigScreenState extends State<ApiConfigScreen> {
  late TextEditingController _apiKeyController;
  late TextEditingController _baseUrlController;
  late TextEditingController _modelController;
  late TextEditingController _maxTokensController;
  late TextEditingController _temperatureController;
  late TextEditingController _ttsApiKeyController;
  late TextEditingController _ttsApiUrlController;
  late TextEditingController _ttsModelIdController;
  late TextEditingController _agnesApiKeyController;
  late TextEditingController _agnesBaseUrlController;
  late TextEditingController _agnesModelController;
  late TextEditingController _agnesPromptController;

  bool _autoModelSwitch = false;
  bool _loading = true;
  bool _agnesTesting = false;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _baseUrlController = TextEditingController();
    _modelController = TextEditingController();
    _maxTokensController = TextEditingController();
    _temperatureController = TextEditingController();
    _ttsApiKeyController = TextEditingController();
    _ttsApiUrlController = TextEditingController();
    _ttsModelIdController = TextEditingController();
    _agnesApiKeyController = TextEditingController();
    _agnesBaseUrlController = TextEditingController();
    _agnesModelController = TextEditingController();
    _agnesPromptController = TextEditingController();
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _apiKeyController.text = prefs.getString('llm_apiKey') ?? '';
      _baseUrlController.text = prefs.getString('llm_baseUrl') ?? 'https://api.deepseek.com/v1';
      _modelController.text = prefs.getString('llm_model') ?? 'deepseek-chat';
      _maxTokensController.text = (prefs.getInt('llm_maxTokens') ?? 2048).toString();
      _temperatureController.text = (prefs.getDouble('llm_temperature') ?? 0.7).toString();
      _autoModelSwitch = prefs.getBool('llm_autoModelSwitch') ?? false;
      _ttsApiKeyController.text = prefs.getString('tts_apiKey') ?? '';
      _ttsApiUrlController.text = prefs.getString('tts_apiUrl') ?? '';
      _ttsModelIdController.text = prefs.getString('tts_modelId') ?? '';
      _agnesApiKeyController.text = prefs.getString('agnes_api_key') ?? '';
      _agnesBaseUrlController.text = prefs.getString('agnes_base_url') ?? 'https://apihub.agnes-ai.com/v1';
      _agnesModelController.text = prefs.getString('agnes_model') ?? 'agnes-2.0-flash';
      _agnesPromptController.text = prefs.getString('agnes_prompt') ?? '请详细描述这张图片的内容，包括场景、人物、物品、文字、氛围等所有你能看到的细节。';
      _loading = false;
    });
  }

  Future<void> _saveConfig() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('llm_apiKey', _apiKeyController.text.trim());
    await prefs.setString('llm_baseUrl', _baseUrlController.text.trim());
    await prefs.setString('llm_model', _modelController.text.trim());
    await prefs.setInt('llm_maxTokens', int.tryParse(_maxTokensController.text) ?? 2048);
    await prefs.setDouble('llm_temperature', double.tryParse(_temperatureController.text) ?? 0.7);
    await prefs.setBool('llm_autoModelSwitch', _autoModelSwitch);
    await prefs.setString('tts_apiKey', _ttsApiKeyController.text.trim());
    await prefs.setString('tts_apiUrl', _ttsApiUrlController.text.trim());
    await prefs.setString('tts_modelId', _ttsModelIdController.text.trim());
    await prefs.setString('agnes_api_key', _agnesApiKeyController.text.trim());
    await prefs.setString('agnes_base_url', _agnesBaseUrlController.text.trim());
    await prefs.setString('agnes_model', _agnesModelController.text.trim());
    await prefs.setString('agnes_prompt', _agnesPromptController.text.trim());

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('配置已保存')),
      );
    }
  }

  @override
  void dispose() {
    _apiKeyController.dispose();
    _baseUrlController.dispose();
    _modelController.dispose();
    _maxTokensController.dispose();
    _temperatureController.dispose();
    _ttsApiKeyController.dispose();
    _ttsApiUrlController.dispose();
    _ttsModelIdController.dispose();
    _agnesApiKeyController.dispose();
    _agnesBaseUrlController.dispose();
    _agnesModelController.dispose();
    _agnesPromptController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        appBar: AppBar(title: const Text('API 配置')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('API 配置'),
        actions: [
          IconButton(icon: const Icon(Icons.save), onPressed: _saveConfig),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSectionTitle('LLM 模型配置'),
            _buildTextField(_apiKeyController, 'API Key', '输入你的 API Key', obscure: true),
            _buildTextField(_baseUrlController, 'Base URL', 'https://api.deepseek.com/v1'),
            _buildTextField(_modelController, '模型名称', 'deepseek-chat'),
            _buildTextField(_maxTokensController, '最大 Token 数', '2048', keyboardType: TextInputType.number),
            _buildTextField(_temperatureController, '温度 (0-2)', '0.7', keyboardType: TextInputType.number),
            SwitchListTile(
              title: const Text('自动模型切换'),
              subtitle: const Text('API 失败时自动切换到备用模型'),
              value: _autoModelSwitch,
              onChanged: (v) => setState(() => _autoModelSwitch = v),
            ),
            const Divider(height: 32),
            _buildSectionTitle('TTS 语音配置'),
            _buildTextField(_ttsApiKeyController, 'TTS API Key', '输入 TTS API Key', obscure: true),
            _buildTextField(_ttsApiUrlController, 'TTS API URL', 'https://api.fish.audio/v1/tts'),
            _buildTextField(_ttsModelIdController, 'TTS 模型 ID', 'Fish Audio 模型 ID'),
            const Divider(height: 32),
            _buildSectionTitle('Agnes 多模态识图'),
            _buildTextField(_agnesApiKeyController, 'Agnes API Key', '输入 Agnes API Key', obscure: true),
            _buildTextField(_agnesBaseUrlController, 'Base URL', 'https://apihub.agnes-ai.com/v1'),
            _buildTextField(_agnesModelController, '模型名称', 'agnes-2.0-flash'),
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: TextField(
                controller: _agnesPromptController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: '识图 Prompt',
                  hintText: '描述图片时使用的提示词',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _agnesTesting ? null : _testAgnesConnection,
                icon: _agnesTesting
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.wifi_find),
                label: Text(_agnesTesting ? '测试中...' : '测试 Agnes 连接'),
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, String hint, {
    bool obscure = false,
    TextInputType? keyboardType,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        decoration: InputDecoration(
          labelText: label, hintText: hint,
          border: const OutlineInputBorder(),
          suffixIcon: obscure ? const Icon(Icons.visibility_off) : null,
        ),
      ),
    );
  }

  Future<void> _testAgnesConnection() async {
    final apiKey = _agnesApiKeyController.text.trim();
    if (apiKey.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先填写 Agnes API Key')),
      );
      return;
    }

    setState(() => _agnesTesting = true);

    try {
      final baseUrl = _agnesBaseUrlController.text.trim();
      final model = _agnesModelController.text.trim();
      final prompt = _agnesPromptController.text.trim();

      // 构建一个最小测试请求：用 1x1 透明 PNG
      final testBase64 = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';
      final body = jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {'type': 'image_url', 'image_url': {'url': 'data:image/png;base64,$testBase64'}},
            ],
          },
        ],
        'max_tokens': 100,
      });

      final client = HttpClient();
      client.connectionTimeout = const Duration(seconds: 15);
      final uri = Uri.parse('$baseUrl/chat/completions');
      final request = await client.postUrl(uri);
      request.headers.set('Content-Type', 'application/json');
      request.headers.set('Authorization', 'Bearer $apiKey');
      request.write(body);

      final response = await request.close().timeout(const Duration(seconds: 15));
      final responseBody = await response.transform(utf8.decoder).join();
      client.close(force: true);

      if (response.statusCode == 200) {
        final data = jsonDecode(responseBody);
        final reply = data['choices']?[0]?['message']?['content'] ?? '';
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('连接成功！模型返回: ${reply.length > 50 ? reply.substring(0, 50) + '...' : reply}'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('请求失败 (${response.statusCode}): $responseBody'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('连接失败: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _agnesTesting = false);
    }
  }
}
