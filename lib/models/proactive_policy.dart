class ProactivePolicyInput {
  final bool enabled;
  final int frequencyHours;
  final DateTime now;
  final DateTime? lastUserMessageAt;
  final DateTime? lastProactiveAt;
  final int deliveredToday;
  final bool hasDueCommitment;
  final bool respectsBoundary;

  const ProactivePolicyInput({
    required this.enabled,
    required this.frequencyHours,
    required this.now,
    this.lastUserMessageAt,
    this.lastProactiveAt,
    required this.deliveredToday,
    required this.hasDueCommitment,
    required this.respectsBoundary,
  });
}

class ProactivePolicyDecision {
  final bool allowed;
  final String reason;
  const ProactivePolicyDecision(this.allowed, this.reason);
}
