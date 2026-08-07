import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/models/character_commitment.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/character_commitment_service.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

class _FakeCommitment extends Fake implements CharacterCommitment {}

void main() {
  late _MockStorage storage;
  late CharacterCommitmentService service;

  setUpAll(() {
    registerFallbackValue(_FakeCommitment());
  });

  setUp(() {
    storage = _MockStorage();
    service = CharacterCommitmentService(storage);
    when(() => storage.saveCharacterCommitment(any())).thenAnswer((_) async {});
    when(() => storage.getActiveCharacterCommitment(
          characterId: any(named: 'characterId'),
          userId: any(named: 'userId'),
        )).thenAnswer((_) async => null);
  });

  test('creates a commitment only from an explicit future event', () async {
    final commitment = await service.createFromUserMessage(
      characterId: 'c1',
      userId: 'u1',
      chatId: 'chat1',
      message: '我明天要考试，今晚得早点睡',
      now: DateTime(2026, 8, 6, 10),
    );

    expect(commitment, isNotNull);
    expect(commitment!.content, '明天要考试');
    expect(commitment.dueAt, DateTime(2026, 8, 7, 18));
    verify(() => storage.saveCharacterCommitment(commitment)).called(1);
  });

  test('ignores ordinary conversation without a future event', () async {
    final commitment = await service.createFromUserMessage(
      characterId: 'c1',
      userId: 'u1',
      chatId: 'chat1',
      message: '今天有点累，但和你聊天很开心',
    );

    expect(commitment, isNull);
    verifyNever(() => storage.saveCharacterCommitment(any()));
  });

  test('builds a prompt that prevents inventing the outcome', () {
    final commitment = CharacterCommitment(
      id: 'i1',
      characterId: 'c1',
      userId: 'u1',
      chatId: 'chat1',
      content: '明天要考试',
      dueAt: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final prompt = service.buildPrompt(commitment);
    expect(prompt, contains('明天要考试'));
    expect(prompt, contains('不要假装事情已经发生'));
  });

  test('fulfills a commitment after a successful follow-up', () async {
    final commitment = CharacterCommitment(
      id: 'i1',
      characterId: 'c1',
      userId: 'u1',
      chatId: 'chat1',
      content: '明天要考试',
      dueAt: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    await service.fulfill(commitment);

    final captured = verify(() => storage.saveCharacterCommitment(captureAny()))
        .captured
        .single as CharacterCommitment;
    expect(captured.status, CharacterCommitmentStatus.fulfilled);
  });

  test('records the user reported outcome as a fulfilled shared experience',
      () async {
    final commitment = CharacterCommitment(
      id: 'i1',
      characterId: 'c1',
      userId: 'u1',
      chatId: 'chat1',
      content: '明天要考试',
      dueAt: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final resolution = await service.resolveFromUserMessage(
      commitment: commitment,
      message: '我考完了，但是没考好。',
    );

    expect(resolution?.summary, contains('没考好'));
    final captured = verify(() => storage.saveCharacterCommitment(captureAny()))
        .captured
        .single as CharacterCommitment;
    expect(captured.status, CharacterCommitmentStatus.fulfilled);
  });

  test('cancels a commitment when the user asks for space', () async {
    final commitment = CharacterCommitment(
      id: 'i1',
      characterId: 'c1',
      userId: 'u1',
      chatId: 'chat1',
      content: '明天要考试',
      dueAt: DateTime.now(),
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );

    final resolution = await service.resolveFromUserMessage(
      commitment: commitment,
      message: '我现在不想谈这件事。',
    );

    expect(resolution?.respectedBoundary, isTrue);
    final captured = verify(() => storage.saveCharacterCommitment(captureAny()))
        .captured
        .single as CharacterCommitment;
    expect(captured.status, CharacterCommitmentStatus.cancelled);
  });
}
