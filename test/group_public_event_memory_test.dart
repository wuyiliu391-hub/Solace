import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/models/ai_config.dart';
import 'package:solace/models/chat_message.dart';
import 'package:solace/models/group_public_event_memory.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/ai_service.dart';
import 'package:solace/services/group_public_event_memory.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

http.Response _llmResponse(String text) => http.Response.bytes(
      utf8.encode(jsonEncode({
        'choices': [
          {'message': {'content': text}}
        ],
      })),
      200,
      headers: {'content-type': 'application/json'},
    );

GroupPublicEventMemory event({
  String id = 'event-1',
  String content = '群聊事件',
  List<String> keywords = const [],
  List<String> speakerNames = const [],
  String? sourceGroupName,
  GroupEventImportance importance = GroupEventImportance.normal,
  bool pinned = false,
  double weight = 1,
  DateTime? createdAt,
}) {
  return GroupPublicEventMemory(
    id: id,
    characterId: 'char-a',
    groupId: 'group-1',
    chatId: 'chat-1',
    content: content,
    keywords: keywords,
    sourceMessageIds: const ['m-1'],
    speakerNames: speakerNames,
    sourceGroupName: sourceGroupName,
    importance: importance,
    pinned: pinned,
    weight: weight,
    createdAt: createdAt ?? DateTime(2026, 8, 4),
    lastRecalledAt: null,
  );
}

void main() {
  test('requires a validated source message id for extracted events', () async {
    final storage = _MockStorage();
    when(() => storage.getActiveAIConfig()).thenAnswer((_) async => AIConfig(
          id: 'cfg',
          providerName: 'test',
          baseUrl: 'https://test.local/v1',
          apiKey: 'test-key',
          modelName: 'test-model',
          createdAt: DateTime(2026, 8, 4),
        ));
    final service = AIService(
      storage,
      httpClient: MockClient((_) async => _llmResponse(jsonEncode([
            {'content': '仅靠说话人', 'speakerNames': ['阿强']},
            {
              'content': '有效来源',
              'sourceMessageIds': ['m1'],
              'speakerNames': ['阿强'],
            },
            {
              'content': '未知来源',
              'sourceMessageIds': ['missing'],
              'speakerNames': ['阿强'],
            },
          ]))),
    );

    final result = await service.extractGroupPublicEvents(
      groupName: '测试群',
      messages: [
        ChatMessage(
          id: 'm1',
          senderId: 'c1',
          senderName: '阿强',
          content: '周末去看展',
        ),
      ],
    );

    expect(result.map((event) => event.content), ['有效来源']);
    expect(result.single.sourceMessageIds, ['m1']);
  });

  test('matches a query against event keywords and speaker names', () {
    final memory = event(
      content: '用户和阿强约定周末去看展，展览地点尚未确定。',
      keywords: const ['周末', '看展'],
      speakerNames: const ['阿强'],
    );

    expect(eventMatchesQuery(memory, '周末和阿强去看展吗'), isTrue);
  });

  test('matching is case insensitive and includes event content', () {
    final memory = event(
      content: 'Meet at the Coffee Shop',
      keywords: const ['Coffee'],
    );

    expect(eventMatchesQuery(memory, 'coffee'), isTrue);
    expect(eventMatchesQuery(memory, 'unrelated'), isFalse);
  });

  test('unrelated events are excluded and pinned events rank first', () {
    final unrelated = event(id: 'unrelated', keywords: const ['旅行']);
    final pinned = event(
      id: 'pinned',
      content: '去咖啡馆',
      keywords: const ['咖啡馆'],
      pinned: true,
    );
    final normal = event(
      id: 'normal',
      content: '咖啡馆见',
      keywords: const ['咖啡馆'],
    );

    expect(
      buildRelevantGroupEventMemories(
        query: '咖啡馆',
        memories: [unrelated, normal, pinned],
        limit: 2,
      ),
      [pinned, normal],
    );
  });

  test('important events are not eligible for decay deletion', () {
    expect(
      canDecayGroupEvent(
        importance: GroupEventImportance.important,
        pinned: true,
      ),
      isFalse,
    );
    expect(
      canDecayGroupEvent(
        importance: GroupEventImportance.important,
        pinned: false,
      ),
      isFalse,
    );
    expect(
      canDecayGroupEvent(
        importance: GroupEventImportance.normal,
        pinned: false,
      ),
      isTrue,
    );
  });

  test('round trips event fields and metadata through map conversion', () {
    final original = event(
      content: '周末看展',
      keywords: const ['周末', '看展'],
      speakerNames: const ['用户', '阿强'],
      sourceGroupName: '周末计划',
      importance: GroupEventImportance.important,
      pinned: true,
      weight: 1.5,
      createdAt: DateTime(2026, 8, 4, 12),
    );

    final restored = GroupPublicEventMemory.fromMap(original.toMap());
    expect(restored.id, original.id);
    expect(restored.keywords, original.keywords);
    expect(restored.sourceMessageIds, original.sourceMessageIds);
    expect(restored.speakerNames, original.speakerNames);
    expect(restored.sourceGroupName, original.sourceGroupName);
    expect(restored.importance, original.importance);
    expect(restored.pinned, original.pinned);
    expect(restored.weight, original.weight);
  });

  test('writes metadata and reads legacy metadata without throwing', () {
    final original = event(
      sourceGroupName: '周末计划',
      speakerNames: const ['阿强'],
    );

    final encoded = original.toMap();
    expect(encoded['metadata'], isA<String>());
    final restored = GroupPublicEventMemory.fromMap({
      ...encoded,
      'sourceMessageIds': null,
      'speakerNames': null,
      'sourceGroupName': null,
      'metadata':
          '{"sourceMessageIds":["legacy-m"],"speakerNames":["旧阿强"],"sourceGroupName":"旧群"}',
      'createdAt': 1770000000000,
    });

    expect(restored.sourceMessageIds, ['legacy-m']);
    expect(restored.speakerNames, ['旧阿强']);
    expect(restored.sourceGroupName, '旧群');
  });

  test('tolerates damaged metadata and legacy scalar values', () {
    final map = {
      'id': 'legacy',
      'pinned': 'true',
      'weight': '1.25',
      'createdAt': 1770000000000,
      'lastRecalledAt': '1770000001000',
      'metadata': '{not json',
      'importance': 'important',
    };
    expect(() => GroupPublicEventMemory.fromMap(map), returnsNormally);
    final restored = GroupPublicEventMemory.fromMap(map);
    expect(restored.pinned, isTrue);
    expect(restored.weight, 1.25);
    expect(restored.createdAt.millisecondsSinceEpoch, 1770000000000);
    expect(restored.lastRecalledAt?.millisecondsSinceEpoch, 1770000001000);
  });

  test('accepts string numeric importance values', () {
    final restored = GroupPublicEventMemory.fromMap({'importance': '1'});

    expect(restored.importance, GroupEventImportance.important);
  });

  test('accepts legacy numeric and named important values', () {
    expect(
      GroupPublicEventMemory.fromMap({'importance': 2}).importance,
      GroupEventImportance.important,
    );
    expect(
      GroupPublicEventMemory.fromMap({'importance': 1.0}).importance,
      GroupEventImportance.important,
    );
    expect(
      GroupPublicEventMemory.fromMap({'importance': 'important'}).importance,
      GroupEventImportance.important,
    );
  });

  test('ignores non-string metadata keys without throwing', () {
    final restored = GroupPublicEventMemory.fromMap({
      'id': 'legacy',
      'metadata': <dynamic, dynamic>{
        1: 'ignored',
        'speakerNames': ['speaker'],
      },
    });

    expect(restored.speakerNames, ['speaker']);
  });

  test(
      'tolerates string fields with legacy scalar values and prefers valid metadata',
      () {
    final restored = GroupPublicEventMemory.fromMap({
      'id': 42,
      'characterId': true,
      'groupId': null,
      'chatId': 7,
      'content': 123,
      'keywords': '["顶层损坏"]',
      'sourceMessageIds': '{not json',
      'speakerNames': '',
      'sourceGroupName': '   ',
      'metadata': {
        'sourceMessageIds': ['metadata-message'],
        'speakerNames': ['metadata-speaker'],
        'sourceGroupName': '有效群名',
      },
    });

    expect(restored.id, '42');
    expect(restored.characterId, 'true');
    expect(restored.groupId, '');
    expect(restored.chatId, '7');
    expect(restored.content, '123');
    expect(restored.sourceMessageIds, ['metadata-message']);
    expect(restored.speakerNames, ['metadata-speaker']);
    expect(restored.sourceGroupName, '有效群名');
  });

  test('copyWith changes selected fields without changing the event identity',
      () {
    final original = event();
    final updated = original.copyWith(content: '新细节', weight: 1.8);

    expect(updated.id, original.id);
    expect(updated.characterId, original.characterId);
    expect(updated.content, '新细节');
    expect(updated.weight, 1.8);
    expect(updated.keywords, original.keywords);
  });

  test('matches Chinese content when query includes extra names and particles',
      () {
    final memory = event(content: '大家周末去看展，阿强也会来。');

    expect(eventMatchesQuery(memory, '周末和阿强去看展吗'), isTrue);
  });

  test('ignores empty and one-character query tokens', () {
    final memory = event(content: '我和你去看展');

    expect(eventMatchesQuery(memory, '我 你 吗'), isFalse);
  });

  test('uses event id as stable final ranking tie-breaker', () {
    final first = event(id: 'b', content: '咖啡馆');
    final second = event(id: 'a', content: '咖啡馆');

    expect(
      buildRelevantGroupEventMemories(query: '咖啡馆', memories: [first, second]),
      [second, first],
    );
  });
}
