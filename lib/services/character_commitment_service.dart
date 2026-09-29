import 'package:uuid/uuid.dart';

import '../models/character_commitment.dart';
import '../repositories/local_storage_repository.dart';

/// 从用户明确给出的近期安排中创建和维护角色待跟进事项。
class CharacterCommitmentService {
  final LocalStorageRepository _storage;
  final Uuid _uuid;

  CharacterCommitmentService(this._storage, {Uuid? uuid})
      : _uuid = uuid ?? const Uuid();

  static final RegExp _futureSignal = RegExp(
    r'(明天|后天|今晚|下周|周末|过几天).{0,24}(考试|考研|答辩|面试|比赛|演出|手术|复诊|加班|出差|搬家|发布|结果|成绩)',
  );

  Future<CharacterCommitment?> createFromUserMessage({
    required String characterId,
    required String userId,
    required String chatId,
    required String message,
    DateTime? now,
  }) async {
    final match = _futureSignal.firstMatch(message.trim());
    if (match == null) return null;

    final createdAt = now ?? DateTime.now();
    final content = match.group(0)!.trim();
    final commitment = CharacterCommitment(
      id: _uuid.v4(),
      characterId: characterId,
      userId: userId,
      chatId: chatId,
      content: content,
      dueAt: _dueAtFor(content, createdAt),
      createdAt: createdAt,
      updatedAt: createdAt,
    );
    await _storage.saveCharacterCommitment(commitment);
    return commitment;
  }

  Future<CharacterCommitment?> getActive({
    required String characterId,
    required String userId,
  }) async {
    final commitment = await _storage.getActiveCharacterCommitment(
      characterId: characterId,
      userId: userId,
    );
    if (commitment == null || !commitment.isActive) return null;
    if (commitment.isExpired) {
      await _storage.saveCharacterCommitment(commitment.copyWith(
        status: CharacterCommitmentStatus.expired,
        updatedAt: DateTime.now(),
      ));
      return null;
    }
    return commitment;
  }

  Future<void> fulfill(CharacterCommitment commitment) {
    return _storage.saveCharacterCommitment(commitment.copyWith(
      status: CharacterCommitmentStatus.fulfilled,
      updatedAt: DateTime.now(),
    ));
  }

  Future<CommitmentResolution?> resolveFromUserMessage({
    required CharacterCommitment? commitment,
    required String message,
  }) async {
    if (commitment == null) return null;
    final text = message.trim();
    if (_containsAny(text, ['不想谈', '别问', '不要再问', '让我静静'])) {
      await _storage.saveCharacterCommitment(commitment.copyWith(
        status: CharacterCommitmentStatus.cancelled,
        updatedAt: DateTime.now(),
      ));
      return CommitmentResolution('用户不想继续谈这件事', true);
    }
    if (_containsAny(text, ['考完了', '结束了', '完成了', '办完了', '结果出来了', '成绩出来了'])) {
      await fulfill(commitment);
      return CommitmentResolution(_outcomeFor(text), false);
    }
    if (_containsAny(text, ['没考好', '考砸了', '失败了', '没通过', '不顺利'])) {
      await fulfill(commitment);
      return CommitmentResolution(_outcomeFor(text), false);
    }
    return null;
  }

  String buildPrompt(CharacterCommitment? commitment) {
    if (commitment == null) return '';
    final timing = commitment.isDue ? '现在已到适合自然跟进的时间' : '现在还未到跟进时间';
    return '【你在等的一件事】\n'
        '用户明确提到：${commitment.content}\n'
        '$timing。不要假装事情已经发生；当用户主动提起或时机合适时，自然关心结果，不要重复追问。';
  }

  DateTime _dueAtFor(String content, DateTime now) {
    if (content.contains('明天')) {
      return DateTime(now.year, now.month, now.day + 1, 18);
    }
    if (content.contains('后天')) {
      return DateTime(now.year, now.month, now.day + 2, 18);
    }
    if (content.contains('今晚')) {
      return DateTime(now.year, now.month, now.day, 20);
    }
    if (content.contains('下周')) {
      return DateTime(now.year, now.month, now.day + 7, 18);
    }
    if (content.contains('周末')) {
      final daysUntilWeekend = (DateTime.saturday - now.weekday + 7) % 7;
      return DateTime(now.year, now.month, now.day + daysUntilWeekend, 14);
    }
    return now.add(const Duration(days: 3));
  }

  String _outcomeFor(String message) => '用户反馈了你们约定跟进的事项：$message';

  bool _containsAny(String text, List<String> values) =>
      values.any(text.contains);
}

class CommitmentResolution {
  final String summary;
  final bool respectedBoundary;

  const CommitmentResolution(this.summary, this.respectedBoundary);
}
