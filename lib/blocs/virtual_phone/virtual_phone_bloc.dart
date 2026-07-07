import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';

import '../../models/ai_character.dart';
import '../../models/virtual_phone/virtual_phone.dart';
import '../../models/virtual_phone/vp_contact.dart';
import '../../models/virtual_phone/vp_chat.dart';
import '../../models/virtual_phone/vp_note.dart';
import '../../models/virtual_phone/vp_moment.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../../services/virtual_phone_generator.dart';

part 'virtual_phone_event.dart';
part 'virtual_phone_state.dart';

/// 虚拟手机 Bloc：打开 / 首次生成 / 载入 / 刷新。
class VirtualPhoneBloc extends Bloc<VirtualPhoneEvent, VirtualPhoneState> {
  final LocalStorageRepository _storage;
  final VirtualPhoneGenerator _generator;
  final _uuid = const Uuid();

  AICharacter? _character;
  String _userNickname = '';

  VirtualPhoneBloc(this._storage, AIService aiService)
      : _generator = VirtualPhoneGenerator(
          aiService: aiService,
          storage: _storage,
        ),
        super(const VirtualPhoneState.initial()) {
    on<VirtualPhoneOpened>(_onOpened);
    on<VirtualPhoneRefreshed>(_onRefreshed);
  }

  Future<void> _onOpened(
    VirtualPhoneOpened event,
    Emitter<VirtualPhoneState> emit,
  ) async {
    _character = event.character;
    _userNickname = event.userNickname;
    emit(state.copyWith(status: VpStatus.loading));

    try {
      var phone =
          await _storage.getVirtualPhoneByCharacter(event.character.id);

      // 建档
      if (phone == null) {
        phone = VirtualPhone(
          id: _uuid.v4(),
          characterId: event.character.id,
          ownerName: event.character.name,
          createdAt: DateTime.now(),
        );
        await _storage.saveVirtualPhone(phone);
      }

      // 首次全量生成
      if (!phone.isReady) {
        emit(state.copyWith(status: VpStatus.generating, phone: phone));
        phone = await _generator.generateAll(
          phone: phone,
          character: event.character,
          userNickname: event.userNickname,
        );
        if (phone.status == 'failed') {
          emit(state.copyWith(
              status: VpStatus.failed,
              phone: phone,
              error: '生成失败，请检查 AI 配置后重试'));
          return;
        }
      }

      await _loadContent(phone, emit);
    } catch (e, st) {
      debugPrint('VirtualPhoneBloc._onOpened failed: $e\n$st');
      emit(state.copyWith(status: VpStatus.failed, error: e.toString()));
    }
  }

  Future<void> _onRefreshed(
    VirtualPhoneRefreshed event,
    Emitter<VirtualPhoneState> emit,
  ) async {
    final phone = state.phone;
    final character = _character;
    if (phone == null || character == null) return;

    emit(state.copyWith(status: VpStatus.generating));
    try {
      final regenerated = await _generator.generateAll(
        phone: phone,
        character: character,
        userNickname: _userNickname,
      );
      if (regenerated.status == 'failed') {
        emit(state.copyWith(
            status: VpStatus.failed,
            phone: regenerated,
            error: '生成失败，请检查 AI 配置后重试'));
        return;
      }
      await _loadContent(regenerated, emit);
    } catch (e, st) {
      debugPrint('VirtualPhoneBloc._onRefreshed failed: $e\n$st');
      emit(state.copyWith(status: VpStatus.failed, error: e.toString()));
    }
  }

  Future<void> _loadContent(
    VirtualPhone phone,
    Emitter<VirtualPhoneState> emit,
  ) async {
    final contacts = await _storage.getVpContacts(phone.id);
    final chats = await _storage.getVpChats(phone.id);
    final notes = await _storage.getVpNotes(phone.id);
    final moments = await _storage.getVpMoments(phone.id);

    final byChat = <String, List<VpChatMessage>>{};
    for (final c in chats) {
      byChat[c.id] = await _storage.getVpChatMessages(c.id);
    }

    emit(state.copyWith(
      status: VpStatus.ready,
      phone: phone,
      contacts: contacts,
      chats: chats,
      messagesByChat: byChat,
      notes: notes,
      moments: moments,
    ));
  }
}
