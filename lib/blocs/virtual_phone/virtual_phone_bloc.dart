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
  String _userId = '';

  VirtualPhoneBloc(this._storage, AIService aiService)
      : _generator = VirtualPhoneGenerator(
          aiService: aiService,
          storage: _storage,
        ),
        super(const VirtualPhoneState.initial()) {
    on<VirtualPhoneOpened>(_onOpened);
    on<VirtualPhoneAdvanced>(_onAdvanced);
    on<VirtualPhoneRefreshed>(_onRefreshed);
  }

  /// 打开页面：只读本地缓存，绝不触发 LLM（省 token）。
  /// 内容由后台预生成或用户手动刷新产生。
  Future<void> _onOpened(
    VirtualPhoneOpened event,
    Emitter<VirtualPhoneState> emit,
  ) async {
    _character = event.character;
    _userNickname = event.userNickname;
    _userId = event.userId;
    emit(state.copyWith(status: VpStatus.loading));

    try {
      var phone =
          await _storage.getVirtualPhoneByCharacter(event.character.id);

      // 建档（仅落一条空记录，不生成内容）
      if (phone == null) {
        phone = VirtualPhone(
          id: _uuid.v4(),
          characterId: event.character.id,
          ownerName: event.character.name,
          createdAt: DateTime.now(),
        );
        await _storage.saveVirtualPhone(phone);
      }

      // 未就绪：显示「内容准备中」空态，不调用 LLM
      if (!phone.isReady) {
        emit(state.copyWith(status: VpStatus.notGenerated, phone: phone));
        return;
      }

      await _loadContent(phone, emit);
    } catch (e, st) {
      debugPrint('VirtualPhoneBloc._onOpened failed: $e\n$st');
      emit(state.copyWith(status: VpStatus.failed, error: e.toString()));
    }
  }

  /// 生活推进（增量）：追加少量新内容，不清空。手动触发时显示轻量 loading，
  /// 自动触发（auto=true）时静默进行，完成后再刷新展示。
  Future<void> _onAdvanced(
    VirtualPhoneAdvanced event,
    Emitter<VirtualPhoneState> emit,
  ) async {
    final phone = state.phone;
    final character = _character;
    if (phone == null || character == null || !phone.isReady) return;

    if (!event.auto) {
      emit(state.copyWith(status: VpStatus.generating));
    }
    try {
      final advanced = await _generator.advanceLife(
        phone: phone,
        character: character,
        userNickname: _userNickname,
        userId: _userId,
      );
      await _loadContent(advanced, emit);
    } catch (e, st) {
      debugPrint('VirtualPhoneBloc._onAdvanced failed: $e\n$st');
      // 增量失败不应破坏已有内容：回到就绪态展示旧内容
      if (state.phone != null) {
        await _loadContent(state.phone!, emit);
      }
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
        userId: _userId,
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
      final msgs = await _storage.getVpChatMessages(c.id);
      byChat[c.id] = msgs.reversed.toList(); // 倒序：新消息在上
    }

    // 倒序：新的在上，旧的在下
    final reversedChats = [...chats].reversed.toList();
    final reversedNotes = [...notes].reversed.toList();
    final reversedMoments = [...moments].reversed.toList();

    emit(state.copyWith(
      status: VpStatus.ready,
      phone: phone,
      contacts: contacts, // 通讯录保持原序（按 orderIndex）
      chats: reversedChats,
      messagesByChat: byChat,
      notes: reversedNotes,
      moments: reversedMoments,
    ));
  }
}
