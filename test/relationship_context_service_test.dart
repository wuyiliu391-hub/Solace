import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/models/relationship_context.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/relationship_context_service.dart';
import 'package:solace/utils/sentiment_analyzer.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

class _FakeRelationshipContext extends Fake implements RelationshipContext {}

void main() {
  late _MockStorage storage;
  late RelationshipContextService service;

  setUpAll(() => registerFallbackValue(_FakeRelationshipContext()));

  setUp(() {
    storage = _MockStorage();
    service = RelationshipContextService(storage);
    when(() => storage.getRelationshipContext(any()))
        .thenAnswer((_) async => null);
    when(() => storage.saveRelationshipContext(any())).thenAnswer((_) async {});
  });

  test('a request for space creates a boundary and clears conflict', () async {
    final context = await service.updateFromUserMessage(
      chatId: 'chat1',
      message: '我现在不想谈这件事，让我静静。',
      sentiment: SentimentAnalyzer.analyze('我现在不想谈这件事，让我静静。'),
    );

    expect(context.boundary, contains('需要空间'));
    expect(context.hasConflict, isFalse);
  });

  test('an apology repairs an existing conflict', () async {
    when(() => storage.getRelationshipContext('chat1'))
        .thenAnswer((_) async => RelationshipContext(
              chatId: 'chat1',
              trust: 0.4,
              unresolvedConflict: '上次争执还没有说开。',
              updatedAt: DateTime.now(),
            ));

    final context = await service.updateFromUserMessage(
      chatId: 'chat1',
      message: '对不起，是我刚才说得太重了。',
      sentiment: SentimentAnalyzer.analyze('对不起，是我刚才说得太重了。'),
    );

    expect(context.trust, greaterThan(0.4));
    expect(context.hasConflict, isFalse);
  });
}
