enum ToolIntentKind {
  conversation,
  directTool,
  agentToolTask,
  continueToolTask,
  clarificationRequired,
  confirmationRequired,
  notAllowed,
}

/// A constrained interpretation of a user message before any device action.
/// This is intentionally separate from execution permissions and tool calls.
class ToolIntentDecision {
  final ToolIntentKind kind;
  final String? toolName;
  final Map<String, dynamic> args;
  final List<String> candidateTools;
  final double confidence;
  final String reason;
  final List<String> missingSlots;
  final String source;
  final bool isReadOnly;

  const ToolIntentDecision({
    required this.kind,
    this.toolName,
    this.args = const {},
    this.candidateTools = const [],
    this.confidence = 0,
    this.reason = '',
    this.missingSlots = const [],
    this.source = 'llm',
    this.isReadOnly = false,
  });

  const ToolIntentDecision.conversation({String reason = ''})
      : this(kind: ToolIntentKind.conversation, reason: reason);

  factory ToolIntentDecision.fromJson(Map<String, dynamic> json) {
    final rawKind = json['decision']?.toString() ?? 'conversation';
    final kind = ToolIntentKind.values.firstWhere(
      (value) => value.name == rawKind,
      orElse: () => ToolIntentKind.conversation,
    );
    final rawArgs = json['args'];
    final args = rawArgs is Map
        ? Map<String, dynamic>.from(rawArgs)
        : <String, dynamic>{};
    final rawCandidates = json['candidate_tools'];
    final rawTool = json['tool']?.toString().trim() ?? '';
    return ToolIntentDecision(
      kind: kind,
      toolName: rawTool.isEmpty ? null : rawTool,
      args: args,
      candidateTools: rawCandidates is List
          ? rawCandidates.map((item) => item.toString()).toList()
          : const [],
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0,
      reason: json['reason']?.toString() ?? '',
      missingSlots: json['missing_slots'] is List
          ? (json['missing_slots'] as List)
              .map((item) => item.toString())
              .toList()
          : const [],
      source: json['source']?.toString() ?? 'llm',
      isReadOnly: json['is_read_only'] == true,
    );
  }
}
