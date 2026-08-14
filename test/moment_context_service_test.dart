import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:solace/models/moment.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/moment_context_service.dart';

/// 最小假存储：只覆写 getAllMoments，其余方法抛出即可（不会被调用）。
class _FakeStorage extends LocalStorageRepository {
  final List<Moment> moments;
  _FakeStorage(this.moments);

  @override
  Future<List<Moment>> getAllMoments({String? viewerId}) async => moments;
}

Moment _moment({
  required String id,
  required String userId,
  String content = '内容',
  MomentVisibility visibility = MomentVisibility.public,
  bool isFromAI = false,
  List<MomentComment> comments = const [],
  List<String> blockedUserIds = const [],
}) {
  return Moment(
    id: id,
    userId: userId,
    userName: userId == 'char-1' ? '角色一' : '用户',
    content: content,
    createdAt: DateTime.now(),
    visibility: visibility,
    isFromAI: isFromAI,
    comments: comments,
    blockedUserIds: blockedUserIds,
  );
}

void main() {
  group('Moment.blockedUserIds 序列化', () {
    test('toMap / fromMap 往返一致', () {
      final m = _moment(
        id: 'm1',
        userId: 'u1',
        blockedUserIds: const ['char-1', 'char-2'],
      );
      final restored = Moment.fromMap(m.toMap());
      expect(restored.blockedUserIds, containsAll(['char-1', 'char-2']));
    });

    test('缺列/空值安全降级为空列表', () {
      final restored = Moment.fromMap({
        'id': 'm2',
        'userId': 'u1',
        'userName': 'n',
        'content': 'x',
        'createdAt': DateTime.now().toIso8601String(),
      });
      expect(restored.blockedUserIds, isEmpty);
      // JSON 字符串形式
      final restored2 = Moment.fromMap({
        'id': 'm3',
        'userId': 'u1',
        'userName': 'n',
        'content': 'x',
        'createdAt': DateTime.now().toIso8601String(),
        'blockedUserIds': jsonEncode(['c1']),
      });
      expect(restored2.blockedUserIds, ['c1']);
    });
  });

  group('MomentContextService.canCharacterSeeMoment', () {
    test('公开动态所有人都可见', () {
      final m = _moment(id: 'm', userId: 'u', visibility: MomentVisibility.public);
      expect(MomentContextService.canCharacterSeeMoment(m, 'c1', 0), isTrue);
    });

    test('私密动态角色不可见', () {
      final m = _moment(id: 'm', userId: 'u', visibility: MomentVisibility.private);
      expect(MomentContextService.canCharacterSeeMoment(m, 'c1', 100), isFalse);
    });

    test('好友可见需要亲密度 ≥ 阈值', () {
      final m = _moment(id: 'm', userId: 'u', visibility: MomentVisibility.normal);
      expect(MomentContextService.canCharacterSeeMoment(m, 'c1', 20), isFalse);
      expect(MomentContextService.canCharacterSeeMoment(m, 'c1', 30), isTrue);
    });

    test('亲密可见需要更高亲密度', () {
      final m = _moment(id: 'm', userId: 'u', visibility: MomentVisibility.intimate);
      expect(MomentContextService.canCharacterSeeMoment(m, 'c1', 30), isFalse);
      expect(MomentContextService.canCharacterSeeMoment(m, 'c1', 60), isTrue);
    });

    test('被拉黑者看不到公开动态', () {
      final m = _moment(
        id: 'm',
        userId: 'u',
        visibility: MomentVisibility.public,
        blockedUserIds: const ['c1'],
      );
      expect(MomentContextService.canCharacterSeeMoment(m, 'c1', 100), isFalse);
      expect(MomentContextService.canCharacterSeeMoment(m, 'c2', 100), isTrue);
    });
  });

  group('MomentContextService.buildCharacterMomentContext', () {
    test('包含自己发过的动态、评论过的内容、看到的用户动态', () async {
      final storage = _FakeStorage([
        _moment(id: 'm1', userId: 'char-1', content: '今晚的月亮很好看'),
        _moment(
          id: 'm2',
          userId: 'user-1',
          content: '今天被领导骂了呜呜',
          comments: [
            MomentComment(
              id: 'c1',
              userId: 'char-1',
              userName: '角色一',
              content: '别难过，我给你点个赞',
              createdAt: DateTime.now(),
            ),
          ],
        ),
        _moment(id: 'm3', userId: 'user-1', content: '周末去看海'),
      ]);

      final ctx = await MomentContextService(storage)
          .buildCharacterMomentContext(
        characterId: 'char-1',
        characterName: '角色一',
        userId: 'user-1',
        intimacyLevel: 80,
      );

      expect(ctx, contains('你最近发过这些动态'));
      expect(ctx, contains('今晚的月亮很好看'));
      expect(ctx, contains('你在朋友圈说过的话'));
      expect(ctx, contains('别难过，我给你点个赞'));
      expect(ctx, contains('你最近看到的'));
      expect(ctx, contains('周末去看海'));
      expect(ctx, contains('不是编造的'));
    });

    test('私密动态在低亲密度下不注入（角色看不到）', () async {
      final storage = _FakeStorage([
        _moment(
          id: 'm1',
          userId: 'user-1',
          content: '只给我一个人看的心事',
          visibility: MomentVisibility.private,
        ),
        _moment(
          id: 'm2',
          userId: 'user-1',
          content: '好友动态',
          visibility: MomentVisibility.normal,
        ),
      ]);

      final ctx = await MomentContextService(storage)
          .buildCharacterMomentContext(
        characterId: 'char-1',
        characterName: '角色一',
        userId: 'user-1',
        intimacyLevel: 10,
      );

      expect(ctx, isNot(contains('只给我一个人看的心事')));
      expect(ctx, isNot(contains('好友动态'))); // 亲密度不足 30
    });

    test('被拉黑时角色看不到该动态', () async {
      final storage = _FakeStorage([
        _moment(
          id: 'm1',
          userId: 'user-1',
          content: '这条不想让角色一看到',
          blockedUserIds: const ['char-1'],
        ),
      ]);

      final ctx = await MomentContextService(storage)
          .buildCharacterMomentContext(
        characterId: 'char-1',
        characterName: '角色一',
        userId: 'user-1',
        intimacyLevel: 100,
      );

      expect(ctx, isNot(contains('这条不想让角色一看到')));
    });

    test('没有相关内容时返回空串', () async {
      final storage = _FakeStorage([]);
      final ctx = await MomentContextService(storage)
          .buildCharacterMomentContext(
        characterId: 'char-1',
        characterName: '角色一',
        userId: 'user-1',
      );
      expect(ctx, isEmpty);
    });
  });
}
