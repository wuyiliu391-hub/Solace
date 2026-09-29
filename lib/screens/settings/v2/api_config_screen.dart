// 【对标来源：KouriChat-1.4.3.2 — data/config/config.json.template API配置】
// 1:1 转译自 KouriChat 配置面板为 Flutter 设置页面

import "package:flutter/material.dart";
import "package:shared_preferences/shared_preferences.dart";

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

  bool _autoModelSwitch = false;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _apiKeyController = TextEditingController();
    _baseUrlController = TextEditingController();
    _modelController = TextEditingController();
    _maxTokensController = TextEditingController();
    _temperatureController = TextEditingController();
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
}
