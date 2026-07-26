import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart' show debugPrint;
import '../config/claw_dolls.dart';
import '../config/constants.dart';
import '../models/owned_doll.dart';
import '../repositories/local_storage_repository.dart';

/// 抓娃娃机业务逻辑：娃娃柜存取（本地 KV）+ 机台随机 + 抓取判定。
class ClawService {
  final LocalStorageRepository _storage;
  final Random _random;

  ClawService(this._storage, {Random? random}) : _random = random ?? Random();

  String get _userId => _storage.getString(PrefKeys.currentUserId) ?? 'default';
  String get _key => 'claw_cabinet_$_userId';

  /// 读取娃娃柜（最新抓到的在前）
  List<OwnedDoll> getCabinet() {
    try {
      final raw = _storage.getString(_key);
      if (raw == null || raw.isEmpty) return [];
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => OwnedDoll.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('读取娃娃柜失败: $e');
      return [];
    }
  }

  Future<void> _saveCabinet(List<OwnedDoll> dolls) async {
    final raw = jsonEncode(dolls.map((d) => d.toJson()).toList());
    await _storage.setString(_key, raw);
  }

  /// 抓到一只娃娃 → 加入娃娃柜，返回该实例
  Future<OwnedDoll> addDoll(
    ClawDoll doll, {
    String? characterId,
    String? characterName,
  }) async {
    final owned = OwnedDoll(
      uid: '${DateTime.now().microsecondsSinceEpoch}_${_random.nextInt(9999)}',
      dollId: doll.id,
      name: doll.name,
      emoji: doll.emoji,
      rarity: doll.rarity.name,
      obtainedAt: DateTime.now(),
      characterId: characterId,
      characterName: characterName,
    );
    final list = getCabinet();
    list.insert(0, owned);
    await _saveCabinet(list);
    return owned;
  }

  /// 标记某只娃娃已送给角色
  Future<void> markGifted(String uid) async {
    final list = getCabinet();
    final idx = list.indexWhere((d) => d.uid == uid);
    if (idx == -1) return;
    list[idx] = list[idx].copyWith(gifted: true);
    await _saveCabinet(list);
  }

  /// 按稀有度权重随机挑选机台上要摆的娃娃
  List<ClawDoll> rollStageDolls([int count = ClawConfig.dollsOnStage]) {
    final weighted = <ClawDoll>[];
    for (final d in ClawConfig.pool) {
      for (var i = 0; i < d.rarity.spawnWeight; i++) {
        weighted.add(d);
      }
    }
    if (weighted.isEmpty) return const [];
    return List.generate(
        count, (_) => weighted[_random.nextInt(weighted.length)]);
  }

  /// 爪子对准娃娃后，判定是否成功抓起（按稀有度成功率）
  bool rollCatch(DollRarity rarity) => _random.nextDouble() < rarity.catchRate;
}
