import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/moment.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_moment_service.dart';

// ─── Events ───

abstract class MomentsFeedEvent extends Equatable {
  @override
  List<Object?> get props => [];
}

class MomentsFeedLoad extends MomentsFeedEvent {}

class MomentsFeedRefresh extends MomentsFeedEvent {}

class MomentLikeToggled extends MomentsFeedEvent {
  final String momentId;
  final String userId;
  final String userName;
  MomentLikeToggled(this.momentId, this.userId, this.userName);
  @override
  List<Object?> get props => [momentId, userId];
}

class MomentRetweeted extends MomentsFeedEvent {
  final Moment original;
  final String userId;
  final String userName;
  MomentRetweeted(this.original, this.userId, this.userName);
  @override
  List<Object?> get props => [original.id, userId];
}

class MomentBookmarked extends MomentsFeedEvent {
  final String momentId;
  final String userId;
  MomentBookmarked(this.momentId, this.userId);
  @override
  List<Object?> get props => [momentId, userId];
}

class MomentDeleted extends MomentsFeedEvent {
  final String momentId;
  MomentDeleted(this.momentId);
  @override
  List<Object?> get props => [momentId];
}

// ─── States ───

abstract class MomentsFeedState extends Equatable {
  @override
  List<Object?> get props => [];
}

class MomentsFeedInitial extends MomentsFeedState {}

class MomentsFeedLoading extends MomentsFeedState {}

class MomentsFeedLoaded extends MomentsFeedState {
  final List<Moment> moments;
  final Set<String> likedIds;
  final Set<String> bookmarkedIds;

  MomentsFeedLoaded({
    required this.moments,
    this.likedIds = const {},
    this.bookmarkedIds = const {},
  });

  @override
  List<Object?> get props => [moments, likedIds, bookmarkedIds];
}

class MomentsFeedError extends MomentsFeedState {
  final String message;
  MomentsFeedError(this.message);
  @override
  List<Object?> get props => [message];
}

// ─── BLoC ───

class MomentsFeedBloc extends Bloc<MomentsFeedEvent, MomentsFeedState> {
  final LocalStorageRepository _storage;
  final String? _currentUserId;

  MomentsFeedBloc(this._storage, {String? currentUserId})
      : _currentUserId = currentUserId,
        super(MomentsFeedInitial()) {
    on<MomentsFeedLoad>(_onLoad);
    on<MomentsFeedRefresh>(_onRefresh);
    on<MomentLikeToggled>(_onLikeToggled);
    on<MomentRetweeted>(_onRetweeted);
    on<MomentBookmarked>(_onBookmarked);
    on<MomentDeleted>(_onDeleted);
  }

  Future<void> _onLoad(
      MomentsFeedLoad event, Emitter<MomentsFeedState> emit) async {
    emit(MomentsFeedLoading());
    try {
      await _emitLoadedFeed(emit);
      // 首屏先展示已有 X 动态，不让 AI 调度阻塞切换页面。
      // AI 调度完成后再通过普通事件静默刷新，避免在事件处理结束后继续使用 emit。
      unawaited(_triggerAI().then((_) {
        if (!isClosed) {
          add(MomentsFeedRefresh());
        }
      }).catchError((_) {}));
    } catch (e) {
      emit(MomentsFeedError(e.toString()));
    }
  }

  Future<void> _onRefresh(
      MomentsFeedRefresh event, Emitter<MomentsFeedState> emit) async {
    try {
      await _emitLoadedFeed(emit);
    } catch (e) {
      // 保持当前状态
    }
  }

  Future<void> _emitLoadedFeed(Emitter<MomentsFeedState> emit) async {
    final moments = await _storage.getXMomentsFeed();
    final likedIds = <String>{};
    var bookmarkedIds = <String>{};

    if (_currentUserId != null) {
      for (final m in moments) {
        if (m.likes.any((l) => l.userId == _currentUserId)) {
          likedIds.add(m.id);
        }
      }
      bookmarkedIds = await _storage.getBookmarkedMomentIds(_currentUserId!);
    }

    if (emit.isDone) return;
    emit(MomentsFeedLoaded(
      moments: moments,
      likedIds: likedIds,
      bookmarkedIds: bookmarkedIds,
    ));
  }

  Future<void> _onLikeToggled(
      MomentLikeToggled event, Emitter<MomentsFeedState> emit) async {
    final current = state;
    if (current is! MomentsFeedLoaded) return;

    final idx = current.moments.indexWhere((m) => m.id == event.momentId);
    if (idx == -1) return;

    final moment = current.moments[idx];
    final newLikedIds = Set<String>.from(current.likedIds);
    final newLikes = List<MomentLike>.from(moment.likes);

    if (newLikedIds.contains(event.momentId)) {
      newLikedIds.remove(event.momentId);
      newLikes.removeWhere((l) => l.userId == event.userId);
    } else {
      newLikedIds.add(event.momentId);
      newLikes.add(MomentLike(
        userId: event.userId,
        userName: event.userName,
        createdAt: DateTime.now(),
      ));
    }

    final updated = moment.copyWith(likes: newLikes);
    final newList = List<Moment>.from(current.moments);
    newList[idx] = updated;

    emit(MomentsFeedLoaded(
      moments: newList,
      likedIds: newLikedIds,
      bookmarkedIds: current.bookmarkedIds,
    ));

    await _storage.saveMoment(updated);
  }

  Future<void> _onRetweeted(
      MomentRetweeted event, Emitter<MomentsFeedState> emit) async {
    final retweet = Moment(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      userId: event.userId,
      userName: event.userName,
      content: '',
      source: MomentSource.x,
      retweetKey: event.original.id,
      createdAt: DateTime.now(),
    );
    await _storage.saveMoment(retweet);
    await _storage.incrementRetweetCount(event.original.id);
    add(MomentsFeedRefresh());
  }

  Future<void> _onBookmarked(
      MomentBookmarked event, Emitter<MomentsFeedState> emit) async {
    final current = state;
    if (current is! MomentsFeedLoaded) return;

    final newBookmarkedIds = Set<String>.from(current.bookmarkedIds);
    if (newBookmarkedIds.contains(event.momentId)) {
      newBookmarkedIds.remove(event.momentId);
      await _storage.removeBookmark(event.momentId, event.userId);
    } else {
      newBookmarkedIds.add(event.momentId);
      await _storage.addBookmark(event.momentId, event.userId);
    }

    emit(MomentsFeedLoaded(
      moments: current.moments,
      likedIds: current.likedIds,
      bookmarkedIds: newBookmarkedIds,
    ));
  }

  Future<void> _onDeleted(
      MomentDeleted event, Emitter<MomentsFeedState> emit) async {
    await _storage.deleteMoment(event.momentId);
    add(MomentsFeedRefresh());
  }

  Future<void> _triggerAI() async {
    try {
      final service = AIMomentService(_storage);
      await service.scheduleAIMomentsForAllCharacters();
    } catch (_) {}
  }
}
