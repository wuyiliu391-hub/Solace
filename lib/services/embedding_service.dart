// 【对标来源：KouriChat-1.4.3.2 — modules/memory/embedding.py 嵌入向量服务】
// 1:1 转译自 KouriChat EmbeddingService 类
// 参考文件：modules/memory/embedding.py

import "dart:convert";
import "dart:math";
import "package:http/http.dart" as http;
import "../models/app_config_data.dart";
import "../utils/response_decoder.dart";

/// 嵌入向量服务（对标 KouriChat EmbeddingService）
/// 提供文本向量化能力，用于记忆检索
class EmbeddingService {
  final LlmSettings settings;

  /// 向量缓存（对标 KouriChat embedding_cache）
  final Map<String, List<double>> _cache = {};

  EmbeddingService({required this.settings});

  /// 获取文本的嵌入向量（对标 KouriChat get_embedding）
  Future<List<double>> getEmbedding(String text) async {
    if (text.isEmpty) return [];

    // 检查缓存
    final cacheKey = text.hashCode.toString();
    if (_cache.containsKey(cacheKey)) {
      return _cache[cacheKey]!;
    }

    try {
      final url = Uri.parse('${settings.baseUrl}/embeddings');
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${settings.apiKey}',
        },
        body: jsonEncode({
          'model': 'text-embedding-v3',
          'input': text,
        }),
      );

      if (response.statusCode == 200) {
        final decoded = await ResponseDecoder.decode(response.headers['content-type'], response.bodyBytes);
        final json = jsonDecode(decoded) as Map<String, dynamic>;
        final data = json['data'] as List<dynamic>;
        if (data.isNotEmpty) {
          final embedding =
              (data[0]['embedding'] as List<dynamic>)
                  .map((e) => (e as num).toDouble())
                  .toList();
          _cache[cacheKey] = embedding;
          return embedding;
        }
      }
    } catch (_) {}

    // 回退：使用简单的文本哈希作为伪向量
    return _generatePseudoEmbedding(text);
  }

  /// 批量获取嵌入向量（对标 KouriChat batch_embedding）
  Future<List<List<double>>> getEmbeddings(List<String> texts) async {
    final results = <List<double>>[];
    for (final text in texts) {
      results.add(await getEmbedding(text));
    }
    return results;
  }

  /// 计算两个向量的余弦相似度（对标 KouriChat cosine_similarity）
  static double cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length) return 0.0;
    double dot = 0, normA = 0, normB = 0;
    for (int i = 0; i < a.length; i++) {
      dot += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }
    if (normA == 0 || normB == 0) return 0.0;
    return dot / (sqrt(normA) * sqrt(normB));
  }

  /// 生成伪嵌入向量（回退方案）
  List<double> _generatePseudoEmbedding(String text) {
    final hash = text.hashCode;
    final random = Random(hash);
    final vector = List<double>.generate(
      128,
      (_) => random.nextDouble() * 2 - 1,
    );
    // 归一化
    final norm = sqrt(vector.fold(0.0, (sum, v) => sum + v * v));
    if (norm > 0) {
      for (int i = 0; i < vector.length; i++) {
        vector[i] /= norm;
      }
    }
    _cache[text.hashCode.toString()] = vector;
    return vector;
  }

  /// 清空缓存
  void clearCache() {
    _cache.clear();
  }
}
