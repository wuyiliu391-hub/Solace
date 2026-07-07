part of 'virtual_phone_bloc.dart';

enum VpStatus { initial, loading, generating, ready, failed }

class VirtualPhoneState extends Equatable {
  final VpStatus status;
  final VirtualPhone? phone;
  final List<VpContact> contacts;
  final List<VpChat> chats;
  final Map<String, List<VpChatMessage>> messagesByChat;
  final List<VpNote> notes;
  final List<VpMoment> moments;
  final String? error;

  const VirtualPhoneState({
    this.status = VpStatus.initial,
    this.phone,
    this.contacts = const [],
    this.chats = const [],
    this.messagesByChat = const {},
    this.notes = const [],
    this.moments = const [],
    this.error,
  });

  const VirtualPhoneState.initial() : this();

  VirtualPhoneState copyWith({
    VpStatus? status,
    VirtualPhone? phone,
    List<VpContact>? contacts,
    List<VpChat>? chats,
    Map<String, List<VpChatMessage>>? messagesByChat,
    List<VpNote>? notes,
    List<VpMoment>? moments,
    String? error,
  }) {
    return VirtualPhoneState(
      status: status ?? this.status,
      phone: phone ?? this.phone,
      contacts: contacts ?? this.contacts,
      chats: chats ?? this.chats,
      messagesByChat: messagesByChat ?? this.messagesByChat,
      notes: notes ?? this.notes,
      moments: moments ?? this.moments,
      error: error,
    );
  }

  bool get isBusy =>
      status == VpStatus.loading || status == VpStatus.generating;

  @override
  List<Object?> get props => [
        status,
        phone,
        contacts,
        chats,
        messagesByChat,
        notes,
        moments,
        error,
      ];
}
