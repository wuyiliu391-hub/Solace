// 【对标来源：SillyTavern-1.18.0 — script.js 角色操作 + char-data.js 数据结构】
// BLoC 状态管理，角色仓库层对标 SillyTavern CRUD
// 参考文件：public/script.js (角色创建/编辑/删除/保存)

import 'dart:async';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../models/character_card_v2.dart';
import '../../repositories/character_repository.dart';
import '../../repositories/avatar_manager.dart';

// ──────────── Events ────────────

abstract class CharacterEvent {}

class LoadCharacters extends CharacterEvent {}

class CreateCharacter extends CharacterEvent {
  final CharacterCardV2 card;
  CreateCharacter(this.card);
}

class UpdateCharacter extends CharacterEvent {
  final String id;
  final CharacterCardV2 card;
  UpdateCharacter(this.id, this.card);
}

class DeleteCharacter extends CharacterEvent {
  final String id;
  DeleteCharacter(this.id);
}

class SearchCharacters extends CharacterEvent {
  final String? nameQuery;
  final List<String>? tags;
  SearchCharacters({this.nameQuery, this.tags});
}

class LoadAvatarSections extends CharacterEvent {
  final String characterId;
  LoadAvatarSections(this.characterId);
}

class SaveAvatarSections extends CharacterEvent {
  final String characterId;
  final Map<String, String> sections;
  SaveAvatarSections(this.characterId, this.sections);
}

// ──────────── States ────────────

abstract class CharacterState {}

class CharacterInitial extends CharacterState {}

class CharacterLoading extends CharacterState {}

class CharactersLoaded extends CharacterState {
  final List<CharacterCardV2> characters;
  CharactersLoaded(this.characters);
}

class CharacterLoaded extends CharacterState {
  final CharacterCardV2 character;
  CharacterLoaded(this.character);
}

class AvatarSectionsLoaded extends CharacterState {
  final String characterId;
  final Map<String, String> sections;
  AvatarSectionsLoaded(this.characterId, this.sections);
}

class CharacterError extends CharacterState {
  final String message;
  CharacterError(this.message);
}

// ──────────── BLoC ────────────

/// 角色 BLoC（对标 SillyTavern 角色管理流程）
class CharacterBloc extends Bloc<CharacterEvent, CharacterState> {
  final CharacterRepository _characterRepo;
  final AvatarManager _avatarManager;

  CharacterBloc({
    CharacterRepository? characterRepo,
    AvatarManager? avatarManager,
  })  : _characterRepo = characterRepo ?? CharacterRepository.instance,
        _avatarManager = avatarManager ?? AvatarManager.instance,
        super(CharacterInitial()) {
    on<LoadCharacters>(_onLoadCharacters);
    on<CreateCharacter>(_onCreateCharacter);
    on<UpdateCharacter>(_onUpdateCharacter);
    on<DeleteCharacter>(_onDeleteCharacter);
    on<SearchCharacters>(_onSearchCharacters);
    on<LoadAvatarSections>(_onLoadAvatarSections);
    on<SaveAvatarSections>(_onSaveAvatarSections);
  }

  Future<void> _onLoadCharacters(
    LoadCharacters event,
    Emitter<CharacterState> emit,
  ) async {
    emit(CharacterLoading());
    try {
      final characters = await _characterRepo.getAllCharacters();
      emit(CharactersLoaded(characters));
    } catch (e) {
      emit(CharacterError('加载角色失败: $e'));
    }
  }

  Future<void> _onCreateCharacter(
    CreateCharacter event,
    Emitter<CharacterState> emit,
  ) async {
    emit(CharacterLoading());
    try {
      await _characterRepo.createCharacter(event.card);
      final characters = await _characterRepo.getAllCharacters();
      emit(CharactersLoaded(characters));
    } catch (e) {
      emit(CharacterError('创建角色失败: $e'));
    }
  }

  Future<void> _onUpdateCharacter(
    UpdateCharacter event,
    Emitter<CharacterState> emit,
  ) async {
    emit(CharacterLoading());
    try {
      await _characterRepo.updateCharacter(event.id, event.card);
      final characters = await _characterRepo.getAllCharacters();
      emit(CharactersLoaded(characters));
    } catch (e) {
      emit(CharacterError('更新角色失败: $e'));
    }
  }

  Future<void> _onDeleteCharacter(
    DeleteCharacter event,
    Emitter<CharacterState> emit,
  ) async {
    emit(CharacterLoading());
    try {
      await _characterRepo.deleteCharacter(event.id);
      final characters = await _characterRepo.getAllCharacters();
      emit(CharactersLoaded(characters));
    } catch (e) {
      emit(CharacterError('删除角色失败: $e'));
    }
  }

  Future<void> _onSearchCharacters(
    SearchCharacters event,
    Emitter<CharacterState> emit,
  ) async {
    emit(CharacterLoading());
    try {
      final characters = await _characterRepo.searchCharacters(
        nameQuery: event.nameQuery,
        tags: event.tags,
      );
      emit(CharactersLoaded(characters));
    } catch (e) {
      emit(CharacterError('搜索角色失败: $e'));
    }
  }

  Future<void> _onLoadAvatarSections(
    LoadAvatarSections event,
    Emitter<CharacterState> emit,
  ) async {
    emit(CharacterLoading());
    try {
      final sections = await _avatarManager.loadAvatar(event.characterId);
      emit(AvatarSectionsLoaded(event.characterId, sections));
    } catch (e) {
      emit(CharacterError('加载角色设定失败: $e'));
    }
  }

  Future<void> _onSaveAvatarSections(
    SaveAvatarSections event,
    Emitter<CharacterState> emit,
  ) async {
    emit(CharacterLoading());
    try {
      await _avatarManager.saveAvatar(event.characterId, event.sections);
      emit(CharacterInitial());
    } catch (e) {
      emit(CharacterError('保存角色设定失败: $e'));
    }
  }
}
