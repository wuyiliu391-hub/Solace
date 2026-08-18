// NovelBloc 单元测试。
//
// 沿用本项目 mocktail 风格，并用可变 Map 模拟「内存数据库」，
// 让 saveNovel/saveNovelChapter 等 mock 具备真实读写语义，
// 从而能验证「事件级联后 state 反映最新数据」。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/blocs/novel/novel_bloc.dart';
import 'package:solace/models/novel.dart';
import 'package:solace/repositories/local_storage_repository.dart';
import 'package:solace/services/ai_service.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

class _MockAiService extends Mock implements AIService {}

Novel _novel(
  String id, {
  String userId = 'u1',
  String title = '星海旅人',
  bool isArchived = false,
}) {
  return Novel(
    id: id,
    userId: userId,
    title: title,
    createdAt: DateTime(2026, 8, 1),
    updatedAt: DateTime(2026, 8, 1),
  );
}

NovelChapter _chapter(
  String id,
  String novelId,
  int sortOrder, {
  String title = '第一章',
  String content = '旧的内容',
  bool isAiGenerated = false,
}) {
  return NovelChapter(
    id: id,
    novelId: novelId,
    sortOrder: sortOrder,
    title: title,
    content: content,
    wordCount: content.replaceAll(RegExp(r'\s+'), '').length,
    isAiGenerated: isAiGenerated,
    createdAt: DateTime(2026, 8, 1),
    updatedAt: DateTime(2026, 8, 1),
  );
}

/// 等待事件级联（Create → LoadList、Generate → LoadChapters 等）处理完毕
Future<void> _pump([int milliseconds = 200]) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

void main() {
  setUpAll(() {
    // saveNovel/saveNovelChapter(any()) 需要 fallback 值
    registerFallbackValue(_novel('fallback'));
    registerFallbackValue(_chapter('fallback', 'n', 0));
  });

  late _MockStorage storage;
  late _MockAiService aiService;

  // 「内存数据库」：模拟真实存储的读写语义
  final novelsById = <String, Novel>{};
  final chaptersById = <String, NovelChapter>{};

  setUp(() {
    storage = _MockStorage();
    aiService = _MockAiService();
    novelsById.clear();
    chaptersById.clear();

    when(() => storage.saveNovel(any())).thenAnswer((inv) async {
      final n = inv.positionalArguments[0] as Novel;
      novelsById[n.id] = n;
    });
    when(() => storage.getNovel(any()))
        .thenAnswer((inv) async => novelsById[inv.positionalArguments[0] as String]);
    when(() => storage.getNovels(any())).thenAnswer(
        (_) async => novelsById.values.toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt)));
    when(() => storage.deleteNovel(any())).thenAnswer((inv) async {
      final id = inv.positionalArguments[0] as String;
      novelsById.remove(id);
      chaptersById.removeWhere((_, c) => c.novelId == id);
    });
    when(() => storage.saveNovelChapter(any())).thenAnswer((inv) async {
      final c = inv.positionalArguments[0] as NovelChapter;
      chaptersById[c.id] = c;
    });
    when(() => storage.getNovelChapters(any())).thenAnswer((inv) async {
      final novelId = inv.positionalArguments[0] as String;
      return chaptersById.values
          .where((c) => c.novelId == novelId)
          .toList()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    });
    when(() => storage.deleteNovelChapter(any())).thenAnswer((inv) async {
      chaptersById.remove(inv.positionalArguments[0] as String);
    });
    when(() => storage.isFaModeEnabled()).thenReturn(false);
    when(() => storage.getActiveAIConfig()).thenAnswer((_) async => null);
  });

  NovelBloc buildBloc() => NovelBloc(storage, aiService);

  group('NovelBloc 初始状态', () {
    test('默认值：空书架、无加载、无错误', () {
      final bloc = buildBloc();
      expect(bloc.state.novels, isEmpty);
      expect(bloc.state.chapters, isEmpty);
      expect(bloc.state.currentNovel, isNull);
      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.isLoadingChapters, isFalse);
      expect(bloc.state.isGenerating, isFalse);
      expect(bloc.state.error, isNull);
      bloc.close();
    });
  });

  group('NovelLoadList', () {
    test('加载成功：返回书架列表并记录 userId', () async {
      novelsById['n1'] = _novel('n1');
      novelsById['n2'] = _novel('n2', title: '午夜文库');

      final bloc = buildBloc();
      bloc.add(const NovelLoadList('u1'));
      await _pump();

      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.userId, 'u1');
      expect(bloc.state.novels.length, 2);
      expect(bloc.state.novels.map((n) => n.id), containsAll(['n1', 'n2']));

      await bloc.close();
    });

    test('加载空数据：书架为空列表', () async {
      final bloc = buildBloc();
      bloc.add(const NovelLoadList('u1'));
      await _pump();

      expect(bloc.state.novels, isEmpty);
      expect(bloc.state.error, isNull);

      await bloc.close();
    });

    test('加载失败：error 携带「加载书架失败」', () async {
      when(() => storage.getNovels(any())).thenThrow(Exception('磁盘损坏'));

      final bloc = buildBloc();
      bloc.add(const NovelLoadList('u1'));
      await _pump();

      expect(bloc.state.isLoading, isFalse);
      expect(bloc.state.error, contains('加载书架失败'));
      expect(bloc.state.error, contains('磁盘损坏'));

      await bloc.close();
    });
  });

  group('NovelCreate / NovelUpdate / NovelDelete / NovelArchive', () {
    test('创建小说：落库后书架包含新小说', () async {
      final newNovel = _novel('n1', title: '海上钢琴师');

      final bloc = buildBloc();
      bloc.add(NovelCreate(newNovel));
      await _pump();

      verify(() => storage.saveNovel(newNovel)).called(1);
      expect(bloc.state.novels.length, 1);
      expect(bloc.state.novels.first.id, 'n1');
      expect(bloc.state.novels.first.title, '海上钢琴师');

      await bloc.close();
    });

    test('创建失败：saveNovel 抛异常时 error 携带「创建失败」', () async {
      when(() => storage.saveNovel(any()))
          .thenThrow(Exception('磁盘已满'));

      final bloc = buildBloc();
      bloc.add(NovelCreate(_novel('n1')));
      await _pump();

      expect(bloc.state.error, contains('创建失败'));

      await bloc.close();
    });

    test('更新小说：书架中标题被替换', () async {
      novelsById['n1'] = _novel('n1', title: '旧标题');

      final bloc = buildBloc();
      bloc.add(NovelUpdate(_novel('n1', title: '新标题')));
      await _pump();

      expect(novelsById['n1']!.title, '新标题');
      expect(bloc.state.novels.first.title, '新标题');

      await bloc.close();
    });

    test('删除小说：书架清空且级联清空章节', () async {
      novelsById['n1'] = _novel('n1');
      chaptersById['c1'] = _chapter('c1', 'n1', 0);

      final bloc = buildBloc();
      bloc.add(const NovelDelete(novelId: 'n1', userId: 'u1'));
      await _pump();

      verify(() => storage.deleteNovel('n1')).called(1);
      expect(bloc.state.novels, isEmpty);
      // 内存库的 deleteNovel 已级联删章节
      expect(chaptersById, isEmpty);

      await bloc.close();
    });

    test('归档小说：isArchived 置为 true 并刷新书架', () async {
      novelsById['n1'] = _novel('n1');

      final bloc = buildBloc();
      bloc.add(const NovelArchive(novelId: 'n1', archived: true));
      await _pump();

      expect(novelsById['n1']!.isArchived, isTrue);
      expect(bloc.state.novels.first.isArchived, isTrue);

      await bloc.close();
    });

    test('归档不存在的小说：不写入任何数据', () async {
      final bloc = buildBloc();
      bloc.add(const NovelArchive(novelId: 'ghost', archived: true));
      await _pump();

      verifyNever(() => storage.saveNovel(any()));
      expect(bloc.state.error, isNull);

      await bloc.close();
    });
  });

  group('NovelLoadChapters / NovelAddChapter / NovelUpdateChapter / NovelDeleteChapter', () {
    test('加载章节成功：填充 currentNovel 与 chapters', () async {
      novelsById['n1'] = _novel('n1');
      chaptersById['c1'] = _chapter('c1', 'n1', 0);
      chaptersById['c2'] = _chapter('c2', 'n1', 1);

      final bloc = buildBloc();
      bloc.add(const NovelLoadChapters('n1'));
      await _pump();

      expect(bloc.state.currentNovel?.id, 'n1');
      expect(bloc.state.chapters.length, 2);
      expect(bloc.state.isLoadingChapters, isFalse);
      // 按 sortOrder 升序
      expect(bloc.state.chapters.first.id, 'c1');

      await bloc.close();
    });

    test('加载章节失败：error 携带「加载章节失败」', () async {
      when(() => storage.getNovelChapters(any()))
          .thenThrow(Exception('表不存在'));

      final bloc = buildBloc();
      bloc.add(const NovelLoadChapters('n1'));
      await _pump();

      expect(bloc.state.error, contains('加载章节失败'));
      expect(bloc.state.isLoadingChapters, isFalse);

      await bloc.close();
    });

    test('新增空白章节：追加到章节列表并刷新小说元数据', () async {
      novelsById['n1'] = _novel('n1');

      final bloc = buildBloc();
      bloc.add(const NovelLoadChapters('n1'));
      await _pump();

      bloc.add(const NovelAddChapter(novelId: 'n1', title: '第二章 启程'));
      await _pump();

      expect(bloc.state.chapters.length, 1);
      expect(bloc.state.chapters.first.title, '第二章 启程');
      expect(bloc.state.chapters.first.content, isEmpty);
      expect(bloc.state.chapters.first.sortOrder, 0);
      // 元数据被刷新：章节数 = 1
      expect(novelsById['n1']!.chapterCount, 1);

      await bloc.close();
    });

    test('更新章节内容：wordCount 按新内容重算', () async {
      novelsById['n1'] = _novel('n1');
      final c1 = _chapter('c1', 'n1', 0, content: '旧的内容');
      chaptersById['c1'] = c1;

      final bloc = buildBloc();
      bloc.add(const NovelLoadChapters('n1'));
      await _pump();

      bloc.add(NovelUpdateChapter(c1.copyWith(content: '新的内容')));
      await _pump();

      expect(chaptersById['c1']!.content, '新的内容');
      expect(chaptersById['c1']!.wordCount, 4); // 「新的内容」4 个字符

      await bloc.close();
    });

    test('删除章节：从列表移除并刷新元数据', () async {
      novelsById['n1'] = _novel('n1');
      chaptersById['c1'] = _chapter('c1', 'n1', 0);

      final bloc = buildBloc();
      bloc.add(const NovelLoadChapters('n1'));
      await _pump();
      expect(bloc.state.chapters.length, 1);

      bloc.add(const NovelDeleteChapter(chapterId: 'c1', novelId: 'n1'));
      await _pump();

      verify(() => storage.deleteNovelChapter('c1')).called(1);
      expect(bloc.state.chapters, isEmpty);
      expect(novelsById['n1']!.chapterCount, 0);

      await bloc.close();
    });

    test('章节排序：新顺序写回 sortOrder', () async {
      novelsById['n1'] = _novel('n1');
      final c1 = _chapter('c1', 'n1', 0, title: '第一章');
      final c2 = _chapter('c2', 'n1', 1, title: '第二章');
      chaptersById['c1'] = c1;
      chaptersById['c2'] = c2;

      final bloc = buildBloc();
      bloc.add(const NovelLoadChapters('n1'));
      await _pump();

      // 用户把第二章拖到最前面
      bloc.add(NovelReorderChapters(novelId: 'n1', chapters: [c2, c1]));
      await _pump();

      expect(chaptersById['c2']!.sortOrder, 0);
      expect(chaptersById['c1']!.sortOrder, 1);
      expect(bloc.state.chapters.first.id, 'c2');

      await bloc.close();
    });
  });

  group('NovelGenerateChapter', () {
    test('AI 生成新章节：写入 AI 内容、标记 isAiGenerated 并计入字数', () async {
      novelsById['n1'] = _novel('n1');
      const generated = '风起了，少女推开木窗。';
      when(() => aiService.sendPromptMessage(
            messages: any(named: 'messages'),
            overrideMaxTokens: any(named: 'overrideMaxTokens'),
          )).thenAnswer((_) async => generated);

      final bloc = buildBloc();
      bloc.add(const NovelLoadChapters('n1'));
      await _pump();

      bloc.add(const NovelGenerateChapter(
        chapterTitle: '第一章 风起',
        targetWords: 100,
      ));
      await _pump();

      expect(bloc.state.isGenerating, isFalse);
      expect(bloc.state.error, isNull);
      expect(bloc.state.chapters.length, 1);
      final chapter = bloc.state.chapters.first;
      expect(chapter.title, '第一章 风起');
      expect(chapter.content, generated);
      expect(chapter.isAiGenerated, isTrue);
      expect(chapter.wordCount, generated.length);
      // 元数据同步：总字数与章节数
      expect(novelsById['n1']!.totalWords, generated.length);
      expect(novelsById['n1']!.chapterCount, 1);

      await bloc.close();
    });

    test('AI 覆写现有章节：替换正文而非新增', () async {
      novelsById['n1'] = _novel('n1');
      chaptersById['c1'] = _chapter('c1', 'n1', 0, title: '第一章');
      const generated = '全新生成的一章正文';
      when(() => aiService.sendPromptMessage(
            messages: any(named: 'messages'),
            overrideMaxTokens: any(named: 'overrideMaxTokens'),
          )).thenAnswer((_) async => generated);

      final bloc = buildBloc();
      bloc.add(const NovelLoadChapters('n1'));
      await _pump();

      bloc.add(const NovelGenerateChapter(
        chapterId: 'c1',
        targetWords: 100,
      ));
      await _pump();

      expect(bloc.state.chapters.length, 1);
      expect(bloc.state.chapters.first.id, 'c1');
      expect(bloc.state.chapters.first.content, generated);
      expect(bloc.state.chapters.first.isAiGenerated, isTrue);

      await bloc.close();
    });

    test('AI 生成失败：error 携带「AI 生成失败」并复位生成标记', () async {
      novelsById['n1'] = _novel('n1');
      when(() => aiService.sendPromptMessage(
            messages: any(named: 'messages'),
            overrideMaxTokens: any(named: 'overrideMaxTokens'),
          )).thenThrow(Exception('网络超时'));

      final bloc = buildBloc();
      bloc.add(const NovelLoadChapters('n1'));
      await _pump();

      bloc.add(const NovelGenerateChapter(targetWords: 100));
      await _pump();

      expect(bloc.state.isGenerating, isFalse);
      expect(bloc.state.generatingChapterId, isNull);
      expect(bloc.state.error, contains('AI 生成失败'));
      expect(bloc.state.chapters, isEmpty);

      await bloc.close();
    });

    test('未加载小说就生成：error 为「找不到小说信息」', () async {
      final bloc = buildBloc();
      bloc.add(const NovelGenerateChapter(targetWords: 100));
      await _pump();

      expect(bloc.state.error, '找不到小说信息');
      expect(bloc.state.isGenerating, isFalse);
      verifyNever(() => aiService.sendPromptMessage(
            messages: any(named: 'messages'),
            overrideMaxTokens: any(named: 'overrideMaxTokens'),
          ));

      await bloc.close();
    });
  });
}
