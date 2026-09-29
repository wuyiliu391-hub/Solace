// MomentsFeedBloc 单元测试。
//
// 沿用本项目 group_chat 系列测试的 mocktail 风格：
// - _MockStorage 模拟 LocalStorageRepository；
// - 手动 add 事件 + Future.delayed 等待事件级联完成后断言最终状态；
// - 用 verify(captureAny()) 捕获写入参数。
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:solace/blocs/moments/moments_feed_bloc.dart';
import 'package:solace/models/moment.dart';
import 'package:solace/repositories/local_storage_repository.dart';

class _MockStorage extends Mock implements LocalStorageRepository {}

/// 构造一条测试用动态
Moment _moment(
  String id, {
  String userId = 'ai_1',
  String userName = 'AI 角色',
  String content = '今天的心情不错',
  List<MomentLike> likes = const [],
  MomentSource source = MomentSource.x,
  DateTime? createdAt,
}) {
  return Moment(
    id: id,
    userId: userId,
    userName: userName,
    content: content,
    likes: likes,
    source: source,
    createdAt: createdAt ?? DateTime(2026, 8, 1),
  );
}

/// 等待事件级联（Load 触发的静默 Refresh 等）处理完毕
Future<void> _pump([int milliseconds = 200]) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

void main() {
  setUpAll(() {
    // saveMoment(any()) 等调用需要注册 Moment 的 fallback 值
    registerFallbackValue(
      _moment('fallback', createdAt: DateTime(2026, 8, 1)),
    );
  });

  late _MockStorage storage;

  setUp(() {
    storage = _MockStorage();
  });

  /// 打通存储桩：信息流返回 [moments]，书签返回 [bookmarks]
  void stubFeed(List<Moment> moments, Set<String> bookmarks) {
    when(() => storage.getXMomentsFeed(viewerId: any(named: 'viewerId')))
        .thenAnswer((_) async => moments);
    when(() => storage.getBookmarkedMomentIds(any()))
        .thenAnswer((_) async => bookmarks);
  }

  MomentsFeedBloc buildBloc({String? currentUserId = 'u1'}) =>
      MomentsFeedBloc(storage, currentUserId: currentUserId);

  group('MomentsFeedBloc 初始状态', () {
    test('初始状态为 MomentsFeedInitial 且不访问存储', () {
      final bloc = buildBloc();
      expect(bloc.state, isA<MomentsFeedInitial>());
      verifyNever(() => storage.getXMomentsFeed(
          viewerId: any(named: 'viewerId')));
      bloc.close();
    });
  });

  group('MomentsFeedLoad', () {
    test('加载成功：返回动态列表并标记已点赞/已收藏', () async {
      final liked = MomentLike(
        userId: 'u1',
        userName: '用户甲',
        createdAt: DateTime(2026, 8, 1),
      );
      final m1 = _moment('m1', likes: [liked]);
      final m2 = _moment('m2', userId: 'ai_2', userName: 'AI 乙');
      stubFeed([m1, m2], {'m1'});

      final bloc = buildBloc();
      bloc.add(MomentsFeedLoad());
      await _pump();

      final state = bloc.state;
      expect(state, isA<MomentsFeedLoaded>());
      final loaded = state as MomentsFeedLoaded;
      expect(loaded.moments.length, 2);
      expect(loaded.likedIds, {'m1'});
      expect(loaded.bookmarkedIds, {'m1'});
      // 以当前用户身份查询信息流
      verify(() => storage.getXMomentsFeed(viewerId: 'u1')).called(greaterThanOrEqualTo(1));

      await bloc.close();
    });

    test('加载空数据：状态为 Loaded 且列表为空', () async {
      stubFeed([], {});

      final bloc = buildBloc();
      bloc.add(MomentsFeedLoad());
      await _pump();

      final loaded = bloc.state as MomentsFeedLoaded;
      expect(loaded.moments, isEmpty);
      expect(loaded.likedIds, isEmpty);
      expect(loaded.bookmarkedIds, isEmpty);

      await bloc.close();
    });

    test('加载失败：状态为 MomentsFeedError 并携带异常信息', () async {
      when(() => storage.getXMomentsFeed(viewerId: any(named: 'viewerId')))
          .thenThrow(Exception('数据库打开失败'));

      final bloc = buildBloc();
      bloc.add(MomentsFeedLoad());
      await _pump();

      expect(bloc.state, isA<MomentsFeedError>());
      expect((bloc.state as MomentsFeedError).message, contains('数据库打开失败'));

      await bloc.close();
    });

    test('未登录（currentUserId 为 null）时不查询书签且 likedIds 为空', () async {
      final m1 = _moment('m1', likes: [
        MomentLike(
          userId: 'someone_else',
          userName: '路人',
          createdAt: DateTime(2026, 8, 1),
        ),
      ]);
      stubFeed([m1], {'m1'});

      final bloc = buildBloc(currentUserId: null);
      bloc.add(MomentsFeedLoad());
      await _pump();

      final loaded = bloc.state as MomentsFeedLoaded;
      expect(loaded.likedIds, isEmpty);
      expect(loaded.bookmarkedIds, isEmpty);
      verifyNever(() => storage.getBookmarkedMomentIds(any()));

      await bloc.close();
    });
  });

  group('MomentsFeedRefresh', () {
    test('刷新成功：更新为最新数据', () async {
      final m1 = _moment('m1');
      stubFeed([m1], {});

      final bloc = buildBloc();
      bloc.add(MomentsFeedLoad());
      await _pump();
      expect((bloc.state as MomentsFeedLoaded).moments.length, 1);

      // 存储出现新动态后刷新
      final m2 = _moment('m2');
      when(() => storage.getXMomentsFeed(viewerId: any(named: 'viewerId')))
          .thenAnswer((_) async => [m1, m2]);
      when(() => storage.getBookmarkedMomentIds(any()))
          .thenAnswer((_) async => <String>{});

      bloc.add(MomentsFeedRefresh());
      await _pump();

      expect((bloc.state as MomentsFeedLoaded).moments.length, 2);

      await bloc.close();
    });

    test('刷新失败：静默吞掉异常并保持当前状态', () async {
      final m1 = _moment('m1');
      stubFeed([m1], {});

      final bloc = buildBloc();
      bloc.add(MomentsFeedLoad());
      await _pump();

      // 刷新时存储抛异常
      when(() => storage.getXMomentsFeed(viewerId: any(named: 'viewerId')))
          .thenThrow(Exception('刷新崩溃'));
      bloc.add(MomentsFeedRefresh());
      await _pump();

      // 状态保持 Loaded 且内容不变，不进入 Error
      final loaded = bloc.state as MomentsFeedLoaded;
      expect(loaded.moments.length, 1);
      expect(loaded.moments.first.id, 'm1');

      await bloc.close();
    });
  });

  group('MomentLikeToggled', () {
    test('点赞：likedIds 添加该动态并持久化 likes 变化', () async {
      final m1 = _moment('m1');
      stubFeed([m1], {});
      when(() => storage.saveMoment(any())).thenAnswer((_) async {});

      final bloc = buildBloc();
      bloc.add(MomentsFeedLoad());
      await _pump();

      bloc.add(MomentLikeToggled('m1', 'u1', '用户甲'));
      await _pump();

      final loaded = bloc.state as MomentsFeedLoaded;
      expect(loaded.likedIds, contains('m1'));
      expect(loaded.moments.first.likes.length, 1);
      expect(loaded.moments.first.likes.first.userId, 'u1');

      // 持久化的 Moment 带上了新点赞
      final saved = verify(() => storage.saveMoment(captureAny()))
          .captured
          .cast<Moment>()
          .last;
      expect(saved.likes.length, 1);
      expect(saved.likes.first.userId, 'u1');

      await bloc.close();
    });

    test('再次点赞：取消点赞并移除 likes 记录', () async {
      final liked = MomentLike(
        userId: 'u1',
        userName: '用户甲',
        createdAt: DateTime(2026, 8, 1),
      );
      final m1 = _moment('m1', likes: [liked]);
      stubFeed([m1], {});
      when(() => storage.saveMoment(any())).thenAnswer((_) async {});

      final bloc = buildBloc();
      bloc.add(MomentsFeedLoad());
      await _pump();

      bloc.add(MomentLikeToggled('m1', 'u1', '用户甲'));
      await _pump();

      final loaded = bloc.state as MomentsFeedLoaded;
      expect(loaded.likedIds, isNot(contains('m1')));
      expect(loaded.moments.first.likes, isEmpty);

      final saved = verify(() => storage.saveMoment(captureAny()))
          .captured
          .cast<Moment>()
          .last;
      expect(saved.likes, isEmpty);

      await bloc.close();
    });

    test('对不在列表中的动态点赞：状态不变化且不落库', () async {
      final m1 = _moment('m1');
      stubFeed([m1], {});
      when(() => storage.saveMoment(any())).thenAnswer((_) async {});

      final bloc = buildBloc();
      bloc.add(MomentsFeedLoad());
      await _pump();
      verifyNever(() => storage.saveMoment(any()));

      bloc.add(MomentLikeToggled('not_exist', 'u1', '用户甲'));
      await _pump();

      final loaded = bloc.state as MomentsFeedLoaded;
      expect(loaded.likedIds, isEmpty);
      verifyNever(() => storage.saveMoment(any()));

      await bloc.close();
    });
  });

  group('MomentRetweeted', () {
    test('转发：写入转发帖（retweetKey 指向原帖）并累加转发数', () async {
      final original = _moment('m1');
      stubFeed([original], {});
      when(() => storage.saveMoment(any())).thenAnswer((_) async {});
      when(() => storage.incrementRetweetCount(any()))
          .thenAnswer((_) async {});

      final bloc = buildBloc();
      bloc.add(MomentsFeedLoad());
      await _pump();

      bloc.add(MomentRetweeted(original, 'u1', '用户甲'));
      await _pump();

      final saved = verify(() => storage.saveMoment(captureAny()))
          .captured
          .cast<Moment>()
          .last;
      expect(saved.retweetKey, 'm1');
      expect(saved.userId, 'u1');
      expect(saved.userName, '用户甲');
      expect(saved.source, MomentSource.x);
      verify(() => storage.incrementRetweetCount('m1')).called(1);

      await bloc.close();
    });
  });

  group('MomentBookmarked', () {
    test('收藏：加入 bookmarkedIds 并调用 addBookmark', () async {
      final m1 = _moment('m1');
      stubFeed([m1], {});
      when(() => storage.addBookmark(any(), any()))
          .thenAnswer((_) async {});
      when(() => storage.removeBookmark(any(), any()))
          .thenAnswer((_) async {});

      final bloc = buildBloc();
      bloc.add(MomentsFeedLoad());
      await _pump();

      bloc.add(MomentBookmarked('m1', 'u1'));
      await _pump();

      final loaded = bloc.state as MomentsFeedLoaded;
      expect(loaded.bookmarkedIds, contains('m1'));
      verify(() => storage.addBookmark('m1', 'u1')).called(1);
      verifyNever(() => storage.removeBookmark(any(), any()));

      await bloc.close();
    });

    test('再次点击：取消收藏并调用 removeBookmark', () async {
      final m1 = _moment('m1');
      stubFeed([m1], {'m1'}); // 已收藏
      when(() => storage.addBookmark(any(), any()))
          .thenAnswer((_) async {});
      when(() => storage.removeBookmark(any(), any()))
          .thenAnswer((_) async {});

      final bloc = buildBloc();
      bloc.add(MomentsFeedLoad());
      await _pump();
      expect((bloc.state as MomentsFeedLoaded).bookmarkedIds, {'m1'});

      bloc.add(MomentBookmarked('m1', 'u1'));
      await _pump();

      final loaded = bloc.state as MomentsFeedLoaded;
      expect(loaded.bookmarkedIds, isNot(contains('m1')));
      verify(() => storage.removeBookmark('m1', 'u1')).called(1);
      verifyNever(() => storage.addBookmark(any(), any()));

      await bloc.close();
    });
  });

  group('MomentDeleted', () {
    test('删除：调用 deleteMoment 并触发刷新', () async {
      final m1 = _moment('m1');
      stubFeed([m1], {});
      when(() => storage.deleteMoment(any())).thenAnswer((_) async {});

      final bloc = buildBloc();
      bloc.add(MomentsFeedLoad());
      await _pump();
      expect((bloc.state as MomentsFeedLoaded).moments.length, 1);

      // 删除后存储里的信息流变空
      when(() => storage.getXMomentsFeed(viewerId: any(named: 'viewerId')))
          .thenAnswer((_) async => <Moment>[]);
      bloc.add(MomentDeleted('m1'));
      await _pump();

      verify(() => storage.deleteMoment('m1')).called(1);
      // 删除后触发 Refresh → 列表变空
      expect((bloc.state as MomentsFeedLoaded).moments, isEmpty);

      await bloc.close();
    });
  });
}
