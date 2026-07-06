import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import '../../config/constants.dart';
import '../../models/ai_config.dart';
import '../../repositories/local_storage_repository.dart';
import '../../utils/response_decoder.dart';
import '../../utils/doh_client.dart';

class AIConfigScreen extends StatefulWidget {
  const AIConfigScreen({super.key});

  @override
  State<AIConfigScreen> createState() => _AIConfigScreenState();
}

class _AIConfigScreenState extends State<AIConfigScreen> {
  final _formKey = GlobalKey<FormState>();
  final _providerController = TextEditingController();
  final _baseUrlController = TextEditingController();
  final _apiKeyController = TextEditingController();
  final _modelController = TextEditingController();

  bool _isLoading = false;
  bool _tutorialExpanded = true;
  bool _isThinkingModel = true; // 表单中的推理模型开关
  int _selectedProvider = 0; // 0=硅基流动, 1=智谱AI
  List<AIConfig> _configs = [];

  static const String _builtinNvidiaId = BuiltInAIProviders.nvidiaStep37FlashId;
  static const String _builtinNvidiaProvider = BuiltInAIProviders.nvidiaStep37FlashProvider;
  static const String _builtinNvidiaBaseUrl = BuiltInAIProviders.nvidiaStep37FlashBaseUrl;
  static const String _builtinNvidiaApiKey = BuiltInAIProviders.nvidiaStep37FlashApiKey;
  static const String _builtinNvidiaApiKeyBackup = BuiltInAIProviders.nvidiaStep37FlashApiKeyBackup;
  static const String _builtinNvidiaModel = BuiltInAIProviders.nvidiaStep37FlashModel;
  static const String _builtinNvidiaRemark = BuiltInAIProviders.nvidiaStep37FlashRemark;

  static const String _builtinGlmId = BuiltInAIProviders.siliconflowGlmZ19BId;
  static const String _builtinGlmProvider = BuiltInAIProviders.siliconflowGlmZ19BProvider;
  static const String _builtinGlmBaseUrl = BuiltInAIProviders.siliconflowGlmZ19BBaseUrl;
  static const String _builtinGlmApiKey = BuiltInAIProviders.siliconflowGlmZ19BApiKey;
  static const String _builtinGlmModel = BuiltInAIProviders.siliconflowGlmZ19BModel;
  static const String _builtinGlmRemark = BuiltInAIProviders.siliconflowGlmZ19BRemark;
  String? _editingConfigId; // 正在编辑的配置 ID，null 表示新建模式

  // 探测 & 测试
  bool _isDiscovering = false;
  bool _isTesting = false;
  List<String> _discoveredModels = [];
  String? _detectedProtocol; // 'openai' 或 'anthropic'

  @override
  void initState() {
    super.initState();
    _loadConfigs();
  }

  @override
  void dispose() {
    _providerController.dispose();
    _baseUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    super.dispose();
  }

  Future<void> _loadConfigs() async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    final configs = await storage.getAllAIConfigs();
    setState(() {
      _configs = configs;
    });
  }

  AIConfig? get _builtinNvidiaConfig {
    for (final config in _configs) {
      if (config.id == _builtinNvidiaId ||
          (config.baseUrl == _builtinNvidiaBaseUrl &&
              config.modelName == _builtinNvidiaModel)) {
        return config;
      }
    }
    return null;
  }

  AIConfig? get _builtinGlmConfig {
    for (final config in _configs) {
      if (config.id == _builtinGlmId ||
          (config.baseUrl == _builtinGlmBaseUrl &&
              config.modelName == _builtinGlmModel)) {
        return config;
      }
    }
    return null;
  }

  bool get _isBuiltinNvidiaActive => _builtinNvidiaConfig?.isActive ?? false;
  bool get _isBuiltinGlmActive => _builtinGlmConfig?.isActive ?? false;

  Future<void> _activateBuiltinModel({
    required String id,
    required String provider,
    required String baseUrl,
    required String apiKey,
    required String model,
    required bool isThinkingModel,
    List<String> extraApiKeys = const [],
    AIConfig? existing,
    required String successMessage,
  }) async {
    setState(() => _isLoading = true);
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);
      final allConfigs = await storage.getAllAIConfigs();
      for (final c in allConfigs) {
        if (c.isActive) {
          await storage.saveAIConfig(c.copyWith(isActive: false));
        }
      }

      final config = AIConfig(
        id: existing?.id ?? id,
        providerName: provider,
        baseUrl: baseUrl,
        apiKey: apiKey,
        extraApiKeys: extraApiKeys,
        modelName: model,
        isThinkingModel: isThinkingModel,
        isActive: true,
        createdAt: existing?.createdAt ?? DateTime.now(),
        updatedAt: DateTime.now(),
      );
      await storage.saveAIConfig(config);
      await _loadConfigs();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(successMessage)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('切换失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _activateBuiltinNvidia() async {
    await _activateBuiltinModel(
      id: _builtinNvidiaId,
      provider: _builtinNvidiaProvider,
      baseUrl: _builtinNvidiaBaseUrl,
      apiKey: _builtinNvidiaApiKey,
      extraApiKeys: [_builtinNvidiaApiKeyBackup],
      model: _builtinNvidiaModel,
      isThinkingModel: false,
      existing: _builtinNvidiaConfig,
      successMessage: '已切换到内置最新 Step 模型',
    );
  }

  Future<void> _activateBuiltinGlm() async {
    await _activateBuiltinModel(
      id: _builtinGlmId,
      provider: _builtinGlmProvider,
      baseUrl: _builtinGlmBaseUrl,
      apiKey: _builtinGlmApiKey,
      model: _builtinGlmModel,
      isThinkingModel: true,
      existing: _builtinGlmConfig,
      successMessage: '已切换到内置硅基 GLM-Z1-9B',
    );
  }


  Future<void> _saveConfig() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isLoading = true);
    try {
      final storage = RepositoryProvider.of<LocalStorageRepository>(context);

      // 反激活所有现有配置
      final allConfigs = await storage.getAllAIConfigs();
      for (final c in allConfigs) {
        if (c.isActive) {
          await storage.saveAIConfig(c.copyWith(isActive: false));
        }
      }

      final modelName = _modelController.text.trim();
      final config = AIConfig(
        id: _editingConfigId ?? const Uuid().v4(),
        providerName: _providerController.text.trim(),
        baseUrl: _baseUrlController.text.trim(),
        apiKey: _apiKeyController.text.trim(),
        modelName: modelName,
        isThinkingModel: _isThinkingModel,
        createdAt: DateTime.now(),
      );
      await storage.saveAIConfig(config);
      await _loadConfigs();
      if (mounted) {
        final wasEditing = _editingConfigId != null;
        _clearForm();
        final msg = wasEditing
            ? '配置已更新（${_isThinkingModel ? "推理模型" : "非推理模型，语义伪装已开启"}）'
            : '配置已保存';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存失败: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _clearForm() {
    _providerController.clear();
    _baseUrlController.clear();
    _apiKeyController.clear();
    _modelController.clear();
    setState(() {
      _editingConfigId = null;
      _isThinkingModel = true;
      _discoveredModels.clear();
      _detectedProtocol = null;
    });
  }

  /// 将已保存的配置加载到表单中进行编辑
  void _loadConfigToForm(AIConfig config) {
    setState(() {
      _editingConfigId = config.id;
      _providerController.text = config.providerName;
      _baseUrlController.text = config.baseUrl;
      _apiKeyController.text = config.apiKey;
      _modelController.text = config.modelName;
      _isThinkingModel = config.isThinkingModel;
      _discoveredModels.clear();
      _detectedProtocol = null;
    });
    // 滚动到表单顶部
    Scrollable.ensureVisible(
      _formKey.currentContext!,
      duration: const Duration(milliseconds: 300),
      alignment: 0.0,
    );
  }

  // ─── 模型探测逻辑 ───

  /// 构建模型查询 URL（自动适配 /v1 后缀和完整路径）
  String _buildModelsUrl(String baseUrl) {
    final trimmed = baseUrl.trimRight().replaceAll(RegExp(r'/+$'), '');
    // 如果已包含 /chat/completions，提取基础路径
    if (trimmed.endsWith('/chat/completions')) {
      final base = trimmed.substring(0, trimmed.lastIndexOf('/chat/completions'));
      return '$base/models';
    }
    // 如果已包含版本路径（如 /v1, /v4），直接加 /models
    if (RegExp(r'/v\d+$').hasMatch(trimmed)) {
      return '$trimmed/models';
    }
    return '$trimmed/v1/models';
  }

  /// 探测全部可用模型（OpenAI 优先，404 后自动切 Anthropic）
  Future<void> _discoverModels() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty) {
      _showAlert('提示', '请先填写 Base URL 和 API Key');
      return;
    }
    if (!baseUrl.startsWith('http')) {
      _showAlert('提示', 'Base URL 必须以 http:// 或 https:// 开头');
      return;
    }

    setState(() {
      _isDiscovering = true;
      _discoveredModels.clear();
      _detectedProtocol = null;
    });

    try {
      // Step 1: 尝试 OpenAI 兼容格式
      final openaiUrl = _buildModelsUrl(baseUrl);
      final openaiResult = await _probeOpenAI(openaiUrl, apiKey);

      if (openaiResult == 'success') {
        setState(() => _detectedProtocol = 'openai');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content:
                    Text('探测成功（OpenAI协议），发现 ${_discoveredModels.length} 个模型')),
          );
        }
      } else if (openaiResult == '401') {
        _showAlert('密钥错误', 'API Key 无效，请检查后重试');
      } else if (openaiResult == '404') {
        // Step 2: OpenAI 404，自动切换 Anthropic 探测
        final anthropicUrl = _buildModelsUrl(baseUrl);
        final anthropicResult = await _probeAnthropic(anthropicUrl, apiKey);

        if (anthropicResult == 'success') {
          setState(() => _detectedProtocol = 'anthropic');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      '探测成功（Anthropic协议），发现 ${_discoveredModels.length} 个模型')),
            );
          }
        } else if (anthropicResult == '401') {
          _showAlert('密钥错误', 'Claude API Key 无效，请检查后重试');
        } else {
          _showAlert('探测失败', '当前服务商关闭了模型查询接口，请手动输入模型 ID');
        }
      } else if (openaiResult == 'empty') {
        _showAlert('无可用模型', '密钥无可用模型权限，请检查 API Key 或服务商配置');
      } else {
        // 网络错误等，直接尝试 Anthropic
        final anthropicUrl = _buildModelsUrl(baseUrl);
        final anthropicResult = await _probeAnthropic(anthropicUrl, apiKey);
        if (anthropicResult == 'success') {
          setState(() => _detectedProtocol = 'anthropic');
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content: Text(
                      '探测成功（Anthropic协议），发现 ${_discoveredModels.length} 个模型')),
            );
          }
        } else {
          _showAlert(
              '探测失败', '无法连接到模型查询接口，请检查 Base URL 是否正确\n\n错误: $openaiResult');
        }
      }
    } finally {
      if (mounted) setState(() => _isDiscovering = false);
    }
  }

  /// 探测 OpenAI 兼容接口
  Future<String> _probeOpenAI(String url, String apiKey) async {
    try {
      final response = await DohResolver.get(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = await ResponseDecoder.decode(
            response.headers['content-type'], response.bodyBytes);
        final json = jsonDecode(decoded);
        final data = json['data'];
        if (data is List && data.isNotEmpty) {
          final models = data
              .map((m) => m['id']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .cast<String>()
              .toList();
          models.sort();
          setState(() {
            _discoveredModels = models;
            if (models.isNotEmpty && !_modelController.text.trim().isNotEmpty) {
              _modelController.text = models.first;
            }
          });
          return 'success';
        } else {
          return 'empty';
        }
      } else if (response.statusCode == 401) {
        return '401';
      } else if (response.statusCode == 404) {
        return '404';
      } else {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  /// 探测 Anthropic 原生接口
  Future<String> _probeAnthropic(String url, String apiKey) async {
    try {
      final response = await DohResolver.get(
        Uri.parse(url),
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'Accept': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final decoded = await ResponseDecoder.decode(
            response.headers['content-type'], response.bodyBytes);
        final json = jsonDecode(decoded);
        final data = json['data'];
        if (data is List && data.isNotEmpty) {
          final models = data
              .map((m) => m['id']?.toString() ?? m['model']?.toString() ?? '')
              .where((id) => id.isNotEmpty)
              .cast<String>()
              .toList();
          models.sort();
          setState(() {
            _discoveredModels = models;
            if (models.isNotEmpty && !_modelController.text.trim().isNotEmpty) {
              _modelController.text = models.first;
            }
          });
          return 'success';
        } else {
          return 'empty';
        }
      } else if (response.statusCode == 401) {
        return '401';
      } else if (response.statusCode == 404) {
        return '404';
      } else {
        return 'HTTP ${response.statusCode}';
      }
    } catch (e) {
      return e.toString();
    }
  }

  // ─── 连通性测试逻辑 ───

  /// 测试当前配置的连通性
  Future<void> _testConnection() async {
    final baseUrl = _baseUrlController.text.trim();
    final apiKey = _apiKeyController.text.trim();
    final model = _modelController.text.trim();

    if (baseUrl.isEmpty || apiKey.isEmpty || model.isEmpty) {
      _showAlert('提示', '请先填写 Base URL、API Key 和模型名称');
      return;
    }

    setState(() => _isTesting = true);

    try {
      final protocol = _detectedProtocol ?? 'openai';

      if (protocol == 'anthropic') {
        await _testAnthropicConnection(baseUrl, apiKey, model);
      } else {
        await _testOpenAIConnection(baseUrl, apiKey, model);
      }
    } finally {
      if (mounted) setState(() => _isTesting = false);
    }
  }

  /// 测试 OpenAI 兼容接口连通性
  Future<void> _testOpenAIConnection(
      String baseUrl, String apiKey, String model) async {
    final trimmed = baseUrl.trimRight().replaceAll(RegExp(r'/+$'), '');
    // 兼容完整路径（如 /v4/chat/completions）和基础路径（如 /v1）
    final url = trimmed.endsWith('/chat/completions')
        ? trimmed
        : '$trimmed/chat/completions';

    try {
      final response = await DohResolver.post(
        Uri.parse(url),
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'model': model,
          'messages': [
            {'role': 'user', 'content': 'hi'}
          ],
          'max_tokens': 10,
        }),
      );

      final decoded = await ResponseDecoder.decode(
          response.headers['content-type'], response.bodyBytes);
      if (response.statusCode == 200) {
        final json = jsonDecode(decoded);
        final content = json['choices']?[0]?['message']?['content'];
        if (content != null) {
          _showAlert('连通成功',
              '模型「$model」响应正常\n\n回复: ${(content as String).substring(0, content.length.clamp(0, 100))}');
        } else {
          _showAlert('连通成功', '模型「$model」已响应（返回格式异常但连接正常）');
        }
      } else if (response.statusCode == 401) {
        _showAlert('密钥错误', 'API Key 无效，请检查后重试');
      } else if (response.statusCode == 404) {
        _showAlert('接口地址错误', '请求地址不存在: $url\n\n请检查 Base URL 是否正确');
      } else {
        _showAlert('测试失败',
            'HTTP ${response.statusCode}\n\n${decoded.substring(0, decoded.length.clamp(0, 200))}');
      }
    } catch (e) {
      _showAlert('连接失败', '无法连接到服务器，请检查 Base URL 是否正确\n\n错误: $e');
    }
  }

  /// 测试 Anthropic 原生接口连通性
  Future<void> _testAnthropicConnection(
      String baseUrl, String apiKey, String model) async {
    String url;
    final trimmed = baseUrl.trimRight().replaceAll(RegExp(r'/+$'), '');
    if (trimmed.endsWith('/v1')) {
      url = '$trimmed/messages';
    } else {
      url = '$trimmed/v1/messages';
    }

    try {
      final response = await http
          .post(
            Uri.parse(url),
            headers: {
              'x-api-key': apiKey,
              'anthropic-version': '2023-06-01',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({
              'model': model,
              'max_tokens': 10,
              'messages': [
                {'role': 'user', 'content': 'hi'}
              ],
            }),
          )
          .timeout(const Duration(seconds: 30));

      final decoded = await ResponseDecoder.decode(
          response.headers['content-type'], response.bodyBytes);
      if (response.statusCode == 200) {
        final json = jsonDecode(decoded);
        final content = json['content']?[0]?['text'];
        if (content != null) {
          _showAlert('连通成功',
              'Claude 模型「$model」响应正常\n\n回复: ${(content as String).substring(0, content.length.clamp(0, 100))}');
        } else {
          _showAlert('连通成功', 'Claude 模型「$model」已响应（连接正常）');
        }
      } else if (response.statusCode == 401) {
        _showAlert('密钥错误', 'Claude API Key 无效，请检查后重试');
      } else if (response.statusCode == 404) {
        _showAlert('接口地址错误', '请求地址不存在: $url\n\n请检查 Base URL 是否正确');
      } else {
        _showAlert('测试失败',
            'HTTP ${response.statusCode}\n\n${decoded.substring(0, decoded.length.clamp(0, 200))}');
      }
    } catch (e) {
      _showAlert('连接失败', '无法连接到服务器，请检查 Base URL 是否正确\n\n错误: $e');
    }
  }

  void _showAlert(String title, String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('确定'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteConfig(AIConfig config) async {
    final isActive = config.isActive;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isActive ? '删除当前使用配置' : '删除配置'),
        content: Text(
          isActive
              ? '「${config.providerName}」正在使用中，删除后将自动切换到其他可用配置。\n\n确定要删除吗？'
              : '确定要删除「${config.providerName}」配置吗？',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    await storage.deleteAIConfig(config.id);

    if (isActive) {
      final remaining = _configs.where((c) => c.id != config.id).toList();
      if (remaining.isNotEmpty) {
        await storage.saveAIConfig(remaining.first.copyWith(isActive: true));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('已删除并切换到「${remaining.first.providerName}」')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('已删除，请手动添加新配置')),
          );
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('配置已删除')),
        );
      }
    }

    await _loadConfigs();
  }

  Future<void> _toggleThinkingModel(AIConfig config, bool isThinking) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    await storage.saveAIConfig(config.copyWith(isThinkingModel: isThinking));
    await _loadConfigs();
  }

  Future<void> _setActiveConfig(AIConfig config) async {
    final storage = RepositoryProvider.of<LocalStorageRepository>(context);
    for (final c in _configs) {
      if (c.id != config.id && c.isActive) {
        await storage.saveAIConfig(c.copyWith(isActive: false));
      }
    }
    await storage.saveAIConfig(config.copyWith(isActive: true));
    await _loadConfigs();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已切换配置')),
      );
    }
  }

  Future<void> _openUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    // 过滤掉内置模型，只显示用户手动添加的配置
    final userConfigs = _configs.where((c) =>
        c.id != _builtinNvidiaId &&
        c.id != _builtinGlmId &&
        c.providerName != _builtinNvidiaProvider &&
        c.providerName != _builtinGlmProvider).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Hero(
          tag: 'app_icon_ai_config',
          child: Text('设置助手'),
        ),
        centerTitle: true,
        elevation: 0,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ─── 新手教程 ───
          _buildSectionTitle(context, '新手配置教程'),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: colorScheme.primary.withOpacity(0.15)),
            ),
            child: Column(
              children: [
                // 供应商切换标签
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: SegmentedButton<int>(
                    segments: const [
                      ButtonSegment(value: 0, label: Text('硅基流动')),
                      ButtonSegment(value: 1, label: Text('智谱AI')),
                    ],
                    selected: {_selectedProvider},
                    onSelectionChanged: (Set<int> newSelection) {
                      setState(() {
                        _selectedProvider = newSelection.first;
                      });
                    },
                  ),
                ),
                InkWell(
                  onTap: () =>
                      setState(() => _tutorialExpanded = !_tutorialExpanded),
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(16)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Text(
                          _selectedProvider == 0
                              ? '以硅基流动(SiliconFlow)为例'
                              : '以智谱AI(Zhipu)为例',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          _tutorialExpanded
                              ? Icons.expand_less
                              : Icons.expand_more,
                          color: colorScheme.primary,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_tutorialExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: _selectedProvider == 0
                          ? _buildSiliconflowTutorial(colorScheme)
                          : _buildZhipuTutorial(colorScheme),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // ─── 内置模型 ───
          _buildSectionTitle(context, '内置模型'),
          const SizedBox(height: 12),
          _buildBuiltinModelCard(
            colorScheme,
            provider: _builtinNvidiaProvider,
            model: _builtinNvidiaModel,
            baseUrl: _builtinNvidiaBaseUrl,
            remark: _builtinNvidiaRemark,
            isActive: _isBuiltinNvidiaActive,
            activate: _activateBuiltinNvidia,
          ),
          const SizedBox(height: 12),
          _buildBuiltinModelCard(
            colorScheme,
            provider: _builtinGlmProvider,
            model: _builtinGlmModel,
            baseUrl: _builtinGlmBaseUrl,
            remark: _builtinGlmRemark,
            isActive: _isBuiltinGlmActive,
            activate: _activateBuiltinGlm,
          ),
          const SizedBox(height: 24),

          // ─── 配置表单 ───
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSectionTitle(context, '配置信息'),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _providerController,
                  decoration: InputDecoration(
                    labelText: '名称',
                    hintText: '硅基流动',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入名称' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _baseUrlController,
                  decoration: InputDecoration(
                    labelText: 'Base URL',
                    hintText: 'https://api.siliconflow.cn/v1 或完整路径 /v4/chat/completions',
                    helperText: '支持 /v1 或完整路径如 /v4/chat/completions',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '请输入Base URL';
                    if (!v.startsWith('http'))
                      return 'URL必须以http://或https://开头';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _apiKeyController,
                  keyboardType: TextInputType.text,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const <String>[],
                  decoration: InputDecoration(
                    labelText: 'API Key',
                    hintText: 'sk-...',
                    helperText: '使用普通键盘输入，不调用系统安全键盘',
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.paste_outlined),
                      onPressed: () async {
                        final data = await Clipboard.getData('text/plain');
                        if (data?.text != null) {
                          _apiKeyController.text = data!.text!;
                        }
                      },
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.trim().isEmpty) ? '请输入API Key' : null,
                ),
                const SizedBox(height: 16),
                // ─── 探测模型按钮 ───
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _isDiscovering ? null : _discoverModels,
                        icon: _isDiscovering
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.search, size: 18),
                        label: Text(_isDiscovering ? '探测中...' : '探测全部模型'),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    if (_detectedProtocol != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: _detectedProtocol == 'anthropic'
                              ? Colors.orange.withOpacity(0.15)
                              : Colors.blue.withOpacity(0.15),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _detectedProtocol == 'anthropic'
                              ? 'Claude'
                              : 'OpenAI',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _detectedProtocol == 'anthropic'
                                ? Colors.orange
                                : Colors.blue,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 16),
                // ─── 模型选择（下拉 + 手动输入） ───
                if (_discoveredModels.isNotEmpty) ...[
                  DropdownButtonFormField<String>(
                    value:
                        _discoveredModels.contains(_modelController.text.trim())
                            ? _modelController.text.trim()
                            : null,
                    items: _discoveredModels
                        .map((m) => DropdownMenuItem(
                              value: m,
                              child: Text(m, overflow: TextOverflow.ellipsis),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) {
                        final detected = !AIConfig.isKnownNonThinkingModel(v);
                        setState(() {
                          _modelController.text = v;
                          _isThinkingModel = detected;
                        });
                      }
                    },
                    decoration: InputDecoration(
                      labelText: '模型名称（已探测 ${_discoveredModels.length} 个）',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    isExpanded: true,
                    validator: (v) => (_modelController.text.trim().isEmpty)
                        ? '请选择或输入模型名称'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () {
                      setState(() {
                        _discoveredModels.clear();
                        _detectedProtocol = null;
                      });
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.edit,
                              size: 14, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Text('切换为手动输入',
                              style: TextStyle(
                                  fontSize: 12, color: colorScheme.primary)),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  TextFormField(
                    controller: _modelController,
                    decoration: InputDecoration(
                      labelText: '模型名称',
                      hintText: 'deepseek-ai/DeepSeek-R1-Distill-Qwen-7B',
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    validator: (v) =>
                        (v == null || v.trim().isEmpty) ? '请输入模型名称' : null,
                    onChanged: (v) {
                      // 输入模型名时自动建议推理/非推理
                      final detected =
                          !AIConfig.isKnownNonThinkingModel(v.trim());
                      if (detected != _isThinkingModel) {
                        setState(() => _isThinkingModel = detected);
                      }
                    },
                  ),
                ],
                const SizedBox(height: 12),
                // ─── 推理模型开关 ───
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colorScheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _isThinkingModel
                            ? Icons.psychology
                            : Icons.chat_bubble_outline,
                        size: 20,
                        color: _isThinkingModel
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _isThinkingModel ? '推理模型（有思考过程）' : '非推理模型（直接回复）',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _isThinkingModel
                                  ? '模型会在内部思考后回复，已启用推理标签过滤'
                                  : '模型直接输出回复，已启用语义伪装防审查',
                              style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _isThinkingModel,
                        onChanged: (v) => setState(() => _isThinkingModel = v),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // ─── 测试连接按钮 ───
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isTesting ? null : _testConnection,
                    icon: _isTesting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering, size: 18),
                    label: Text(_isTesting ? '测试中...' : '测试连接'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    if (_editingConfigId != null) ...[
                      Expanded(
                        child: SizedBox(
                          height: 56,
                          child: OutlinedButton(
                            onPressed: _isLoading ? null : _clearForm,
                            style: OutlinedButton.styleFrom(
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16)),
                            ),
                            child: const Text('取消编辑',
                                style: TextStyle(fontSize: 16)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      flex: _editingConfigId != null ? 2 : 1,
                      child: SizedBox(
                        height: 56,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _saveConfig,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: colorScheme.primary,
                            foregroundColor: colorScheme.onPrimary,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16)),
                          ),
                          child: _isLoading
                              ? SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    valueColor: AlwaysStoppedAnimation(
                                        colorScheme.onPrimary),
                                  ),
                                )
                              : Text(_editingConfigId != null ? '更新配置' : '保存配置',
                                  style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),

          if (userConfigs.isNotEmpty) ...[
            _buildSectionTitle(context, '已保存的配置'),
            const SizedBox(height: 12),
            ...userConfigs.map((config) => _ConfigCard(
                  config: config,
                  isActive: config.isActive,
                  onTap: () => _setActiveConfig(config),
                  onEdit: () => _loadConfigToForm(config),
                  onDelete: () => _deleteConfig(config),
                  onThinkingModelChanged: (v) =>
                      _toggleThinkingModel(config, v),
                )),
            const SizedBox(height: 32),
          ],

          // ─── 底部说明 ───
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withOpacity(0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Icon(Icons.info_outline,
                      size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('小贴士',
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: colorScheme.primary)),
                ]),
                const SizedBox(height: 8),
                Text(
                  '1. 硅基流动为新用户提供免费额度，足够日常使用\n'
                  '2. 配置仅保存在本地设备，不会上传到任何服务器\n'
                  '3. 也支持其他 OpenAI 兼容的 API 服务\n'
                  '4. API Key 请妥善保管，不要分享给他人',
                  style: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurface.withOpacity(0.6),
                      height: 1.8),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildBuiltinModelCard(
    ColorScheme colorScheme, {
    required String provider,
    required String model,
    required String baseUrl,
    required String remark,
    required bool isActive,
    required VoidCallback activate,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isActive
            ? colorScheme.primaryContainer.withOpacity(0.35)
            : colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive ? colorScheme.primary : colorScheme.outlineVariant,
          width: isActive ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.auto_awesome, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            provider,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.onSurface,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isActive) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colorScheme.primary,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              '使用中',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '模型：$model',
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            baseUrl,
            style: TextStyle(
              fontSize: 12,
              color: colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withOpacity(0.45),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.outlineVariant.withOpacity(0.65),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline,
                  size: 16,
                  color: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    remark,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.45,
                      color: colorScheme.onSecondaryContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed:
                  _isLoading || isActive ? null : activate,
              icon: Icon(isActive ? Icons.check_circle : Icons.swap_horiz),
              label: Text(isActive ? '当前已启用' : '一键切换'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tutorialStep(int step, String title, String detail) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: colorScheme.primary,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text('$step',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface)),
                const SizedBox(height: 4),
                Text(detail,
                    style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurface.withOpacity(0.6),
                        height: 1.6)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: Theme.of(context).colorScheme.primary,
      ),
    );
  }

  List<Widget> _buildSiliconflowTutorial(ColorScheme colorScheme) {
    return [
      _tutorialStep(
          1,
          '注册账号',
          '打开硅基流动官网 cloud.siliconflow.cn\n'
              '点击右上角「注册」，用手机号或邮箱注册账号'),
      _tutorialStep(
          2,
          '获取 API Key',
          '登录后，在左侧菜单找到「API 密钥」\n'
              '点击「新建 API 密钥」，复制生成的密钥（sk-...）'),
      _tutorialStep(
          3,
          '选择模型',
          '在「模型广场」搜索以下推荐模型（9B 以下）：\n'
              '• deepseek-ai/DeepSeek-R1-Distill-Qwen-7B\n'
              '• Qwen/Qwen2.5-7B-Instruct\n'
              '• THUDM/glm-4-9b-chat\n'
              '点击模型进入详情页，复制「模型ID」'),
      _tutorialStep(
          4,
          '填写配置',
          '把上面获取的信息填入下方表单：\n'
              '• 名称：随便起个名，如「硅基流动」\n'
              '• Base URL：https://api.siliconflow.cn/v1\n'
              '• API Key：粘贴你复制的密钥\n'
              '• 模型名：粘贴你复制的模型ID'),
      const SizedBox(height: 8),
      Row(
        children: [
          Icon(Icons.link, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _openUrl('https://cloud.siliconflow.cn'),
            child: Text(
              '打开硅基流动 →',
              style: TextStyle(
                color: colorScheme.primary,
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    ];
  }

  List<Widget> _buildZhipuTutorial(ColorScheme colorScheme) {
    return [
      _tutorialStep(
          1,
          '注册账号',
          '打开智谱AI官网 bigmodel.cn\n'
              '点击右上角「登录/注册」，用手机号注册账号'),
      _tutorialStep(
          2,
          '获取 API Key',
          '登录后，进入「用户中心」→「API 密钥」\n'
              '点击「添加新的 API Key」，复制生成的密钥'),
      _tutorialStep(
          3,
          '选择模型',
          '在「模型广场」选择推荐模型：\n'
              '• glm-4-flash（免费，适合日常对话）\n'
              '• glm-4-plus（更强，需付费）\n'
              '• glm-4.7-flash（最新，200K上下文）\n'
              '直接复制模型名称即可'),
      _tutorialStep(
          4,
          '填写配置',
          '把上面获取的信息填入下方表单：\n'
              '• 名称：随便起个名，如「智谱AI」\n'
              '• Base URL：https://open.bigmodel.cn/api/paas/v4\n'
              '• API Key：粘贴你复制的密钥\n'
              '• 模型名：如 glm-4-flash'),
      const SizedBox(height: 8),
      Row(
        children: [
          Icon(Icons.link, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _openUrl('https://bigmodel.cn'),
            child: Text(
              '打开智谱AI →',
              style: TextStyle(
                color: colorScheme.primary,
                fontSize: 13,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    ];
  }
}

class _ConfigCard extends StatelessWidget {
  final AIConfig config;
  final bool isActive;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool>? onThinkingModelChanged;

  const _ConfigCard({
    required this.config,
    required this.isActive,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.onThinkingModelChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: isActive ? colorScheme.primaryContainer.withOpacity(0.2) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isActive
            ? BorderSide(color: colorScheme.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(config.providerName,
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                  if (isActive)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                          color: colorScheme.primary,
                          borderRadius: BorderRadius.circular(8)),
                      child: const Text('使用中',
                          style: TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.w500)),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text('模型: ${config.modelName}',
                  style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.6))),
              const SizedBox(height: 4),
              Text('URL: ${config.baseUrl}',
                  style: TextStyle(
                      fontSize: 13,
                      color: colorScheme.onSurface.withOpacity(0.6)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              if (isActive) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.psychology_outlined,
                        size: 16,
                        color: colorScheme.onSurface.withOpacity(0.5)),
                    const SizedBox(width: 8),
                    Text('思考模型',
                        style: TextStyle(
                            fontSize: 13,
                            color: colorScheme.onSurface.withOpacity(0.7))),
                    const Spacer(),
                    Text(
                      config.isThinkingModel ? '开启' : '关闭',
                      style: TextStyle(
                        fontSize: 12,
                        color: config.isThinkingModel
                            ? Colors.green
                            : Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Switch(
                      value: config.isThinkingModel,
                      onChanged: onThinkingModelChanged,
                      activeColor: Colors.green,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isActive)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.swap_horiz,
                                size: 14, color: colorScheme.primary),
                            const SizedBox(width: 4),
                            Text('点击卡片切换',
                                style: TextStyle(
                                    fontSize: 11, color: colorScheme.primary)),
                          ],
                        ),
                      ),
                    ),
                  TextButton.icon(
                    icon: Icon(Icons.delete_outline,
                        size: 18,
                        color: isActive ? Colors.orange : colorScheme.error),
                    label: Text(
                      isActive ? '删除并切换' : '删除',
                      style: TextStyle(
                          fontSize: 13,
                          color: isActive ? Colors.orange : colorScheme.error),
                    ),
                    onPressed: onDelete,
                  ),
                  TextButton.icon(
                    icon: Icon(Icons.edit_outlined,
                        size: 18, color: colorScheme.primary),
                    label: Text(
                      '编辑',
                      style:
                          TextStyle(fontSize: 13, color: colorScheme.primary),
                    ),
                    onPressed: onEdit,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
