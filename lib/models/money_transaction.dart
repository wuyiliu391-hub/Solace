import 'package:equatable/equatable.dart';

/// 资金流水类型
enum MoneyKind {
  transfer, // 转账
  redPacket, // 红包
}

/// 流水状态机
///
/// 转账（transfer）：
///   pending（待收款）→ accepted（已收款）/ rejected（已拒收）/ expired（24h 超时退回）
/// 红包（redPacket）：
///   pending（未拆开）→ opened（已拆开）/ expired（24h 过期退回）
///
/// 注意：status 按 name 字符串持久化，新值只能追加不能插队/改名。
enum MoneyStatus {
  pending,
  accepted,
  rejected,
  expired,
  opened,
}

/// 一笔转账/红包流水（money_transactions 表）。
///
/// 与 chat_messages 的关联：
/// - 消息侧：MessageType.transfer / redPacket，金额与状态快照存
///   `metadata['money']`（字段见 [toMessageMetadata]），供气泡渲染。
/// - 流水侧：本表记录完整生命周期，收款/拆包/过期退回时只更新本表 +
///   消息 metadata 中的 status 快照。
class MoneyTransaction extends Equatable {
  final String id;

  /// transfer / redPacket
  final MoneyKind kind;

  /// 资金流向：true = 用户 → 角色；false = 角色 → 用户
  final bool userToCharacter;

  final String chatId;

  /// 关联的 chat_messages.id（气泡消息）
  final String messageId;

  final String characterId;
  final String userId;

  /// 金额（金币，整数体系与 users.coins / ai_wallets.balance 一致）
  final int amount;

  /// 转账备注 / 红包祝福语
  final String? note;

  final MoneyStatus status;

  /// 接收方昵称快照（收款展示用）
  final String? receiverName;

  final DateTime createdAt;

  /// 收款/拆开/拒收时间
  final DateTime? actedAt;

  /// 过期时间（默认创建后 24h）
  final DateTime expireAt;

  const MoneyTransaction({
    required this.id,
    required this.kind,
    required this.userToCharacter,
    required this.chatId,
    required this.messageId,
    required this.characterId,
    required this.userId,
    required this.amount,
    this.note,
    this.status = MoneyStatus.pending,
    this.receiverName,
    required this.createdAt,
    this.actedAt,
    required this.expireAt,
  });

  bool get isTerminal => status != MoneyStatus.pending;

  bool get isExpiredOrLater =>
      status == MoneyStatus.expired ||
      (expireAt.isBefore(DateTime.now()) && status == MoneyStatus.pending);

  /// 塞进 chat_messages.metadata['money'] 的快照（渲染契约，勿改字段名）
  Map<String, dynamic> toMessageMetadata() => {
        'kind': kind.name,
        'userToCharacter': userToCharacter,
        'amount': amount,
        if (note != null && note!.isNotEmpty) 'note': note,
        'txId': id,
        'status': status.name,
      };

  /// 从 metadata['money'] 解析快照（可能为空/字段缺失，全部防御）
  static MoneyMeta? fromMessageMetadata(Map<String, dynamic>? money) {
    if (money == null) return null;
    return MoneyMeta(
      kind: MoneyKind.values.firstWhere(
        (e) => e.name == money['kind'],
        orElse: () => MoneyKind.transfer,
      ),
      userToCharacter: money['userToCharacter'] == true,
      amount: (money['amount'] as num?)?.toInt() ?? 0,
      note: money['note'] as String?,
      txId: money['txId'] as String?,
      status: MoneyStatus.values.firstWhere(
        (e) => e.name == money['status'],
        orElse: () => MoneyStatus.pending,
      ),
    );
  }

  MoneyTransaction copyWith({
    MoneyKind? kind,
    bool? userToCharacter,
    String? chatId,
    String? messageId,
    String? characterId,
    String? userId,
    int? amount,
    String? note,
    MoneyStatus? status,
    String? receiverName,
    DateTime? createdAt,
    DateTime? actedAt,
    DateTime? expireAt,
  }) =>
      MoneyTransaction(
        id: id,
        kind: kind ?? this.kind,
        userToCharacter: userToCharacter ?? this.userToCharacter,
        chatId: chatId ?? this.chatId,
        messageId: messageId ?? this.messageId,
        characterId: characterId ?? this.characterId,
        userId: userId ?? this.userId,
        amount: amount ?? this.amount,
        note: note ?? this.note,
        status: status ?? this.status,
        receiverName: receiverName ?? this.receiverName,
        createdAt: createdAt ?? this.createdAt,
        actedAt: actedAt ?? this.actedAt,
        expireAt: expireAt ?? this.expireAt,
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'kind': kind.name,
        'userToCharacter': userToCharacter ? 1 : 0,
        'chatId': chatId,
        'messageId': messageId,
        'characterId': characterId,
        'userId': userId,
        'amount': amount,
        'note': note,
        'status': status.name,
        'receiverName': receiverName,
        'createdAt': createdAt.toIso8601String(),
        'actedAt': actedAt?.toIso8601String(),
        'expireAt': expireAt.toIso8601String(),
      };

  factory MoneyTransaction.fromMap(Map<String, dynamic> map) {
    final created =
        DateTime.tryParse(map['createdAt'] as String? ?? '') ?? DateTime.now();
    return MoneyTransaction(
      id: map['id'] as String? ?? '',
      kind: MoneyKind.values.firstWhere(
        (e) => e.name == map['kind'],
        orElse: () => MoneyKind.transfer,
      ),
      userToCharacter: (map['userToCharacter'] as int? ?? 1) == 1,
      chatId: map['chatId'] as String? ?? '',
      messageId: map['messageId'] as String? ?? '',
      characterId: map['characterId'] as String? ?? '',
      userId: map['userId'] as String? ?? '',
      amount: (map['amount'] as num?)?.toInt() ?? 0,
      note: map['note'] as String?,
      status: MoneyStatus.values.firstWhere(
        (e) => e.name == map['status'],
        orElse: () => MoneyStatus.pending,
      ),
      receiverName: map['receiverName'] as String?,
      createdAt: created,
      actedAt: DateTime.tryParse(map['actedAt'] as String? ?? ''),
      expireAt: DateTime.tryParse(map['expireAt'] as String? ?? '') ??
          created.add(const Duration(hours: 24)),
    );
  }

  @override
  List<Object?> get props => [id, kind, status, amount, messageId];
}

/// chat_messages.metadata 里的钱信息快照（轻量视图，渲染用）
class MoneyMeta {
  final MoneyKind kind;
  final bool userToCharacter;
  final int amount;
  final String? note;
  final String? txId;
  final MoneyStatus status;

  const MoneyMeta({
    required this.kind,
    required this.userToCharacter,
    required this.amount,
    this.note,
    this.txId,
    required this.status,
  });
}
