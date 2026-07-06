import 'package:equatable/equatable.dart';

class AIWallet extends Equatable {
  final String characterId;
  final int balance;
  final int totalEarned;
  final int totalSpent;
  final int dailySpent;
  final String dailySpentDate;
  final int spendingPersonality; // 1-10, 1=节俭, 10=大方
  final int syncSeq;

  const AIWallet({
    required this.characterId,
    this.balance = 50,
    this.totalEarned = 50,
    this.totalSpent = 0,
    this.dailySpent = 0,
    this.dailySpentDate = '',
    this.spendingPersonality = 5,
    this.syncSeq = 0,
  });

  AIWallet copyWith({
    String? characterId,
    int? balance,
    int? totalEarned,
    int? totalSpent,
    int? dailySpent,
    String? dailySpentDate,
    int? spendingPersonality,
    int? syncSeq,
  }) {
    return AIWallet(
      characterId: characterId ?? this.characterId,
      balance: balance ?? this.balance,
      totalEarned: totalEarned ?? this.totalEarned,
      totalSpent: totalSpent ?? this.totalSpent,
      dailySpent: dailySpent ?? this.dailySpent,
      dailySpentDate: dailySpentDate ?? this.dailySpentDate,
      spendingPersonality: spendingPersonality ?? this.spendingPersonality,
      syncSeq: syncSeq ?? this.syncSeq,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'characterId': characterId,
      'balance': balance,
      'totalEarned': totalEarned,
      'totalSpent': totalSpent,
      'dailySpent': dailySpent,
      'dailySpentDate': dailySpentDate,
      'spendingPersonality': spendingPersonality,
      'sync_seq': syncSeq,
    };
  }

  factory AIWallet.fromMap(Map<String, dynamic> map) {
    return AIWallet(
      characterId: map['characterId'] as String,
      balance: map['balance'] as int? ?? 50,
      totalEarned: map['totalEarned'] as int? ?? 50,
      totalSpent: map['totalSpent'] as int? ?? 0,
      dailySpent: map['dailySpent'] as int? ?? 0,
      dailySpentDate: map['dailySpentDate'] as String? ?? '',
      spendingPersonality: map['spendingPersonality'] as int? ?? 5,
      syncSeq: (map['sync_seq'] ?? map['syncSeq']) as int? ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        characterId,
        balance,
        totalEarned,
        totalSpent,
        dailySpent,
        dailySpentDate,
        spendingPersonality,
        syncSeq,
      ];
}
