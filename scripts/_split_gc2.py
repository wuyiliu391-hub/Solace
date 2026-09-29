from pathlib import Path

ROOT = Path(r"C:\Users\Administrator\Desktop\Solace")
SRC = ROOT / "lib/blocs/group_chat/group_chat_bloc.dart"
OUT = ROOT / "lib/blocs/group_chat/group_chat_bloc_parts"
OUT.mkdir(exist_ok=True)

lines = SRC.read_text(encoding="utf-8").splitlines(keepends=True)


def sl(a, b):
    return "".join(lines[a - 1 : b])


def to_mixin_body(a, b):
    body = sl(a, b)
    out = []
    for l in body.splitlines():
        out.append(l[2:] if l.startswith("  ") else l)
    return "\n".join(out)


header = "// 群聊 BLoC 拆分 part\npart of '../group_chat_bloc.dart';\n\n"

# Fields: lines 36-71 (inside class)
fields = to_mixin_body(36, 71)
core = header + "mixin _GcCore {\n" + fields + "\n}\n"
(OUT / "bloc_core.dart").write_text(core, encoding="utf-8")

chain = []


def write_mixin(file_name, cls, ranges):
    parts = []
    for a, b in ranges:
        parts.append(to_mixin_body(a, b))
    body = "\n\n".join(parts)
    chain.append(cls)
    on_list = ["Bloc<GroupChatEvent, GroupChatState>", "_GcCore"] + [
        c for c in chain[:-1]
    ]
    text = (
        header
        + f"mixin {cls} on {', '.join(on_list)} {{\n"
        + body
        + "\n}\n"
    )
    (OUT / file_name).write_text(text, encoding="utf-8")
    print(f"{cls}: ranges={ranges} on={on_list}")


write_mixin("gc_sessions.dart", "_GcSessions", [(102, 187)])
write_mixin("gc_messages.dart", "_GcMessages", [(188, 552)])
# shared helpers used by AI reply
write_mixin(
    "gc_helpers.dart",
    "_GcHelpers",
    [
        (1309, 1348),  # aggregate + loadMembers + isNovel
        (1451, 1517),  # buildMemberNames + merge + toChatHistory
    ],
)
write_mixin("gc_ai_reply.dart", "_GcAiReply", [(553, 1062)])
write_mixin(
    "gc_config_memory.dart",
    "_GcConfigMemory",
    [(1063, 1308), (1349, 1450)],
)
write_mixin("gc_session_config.dart", "_GcSessionConfig", [(1518, 1854)])

with_line = ",\n        ".join(chain)
shell = f"""import 'dart:async';
import 'dart:math';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:uuid/uuid.dart';
import '../../models/group_chat_session.dart';
import '../../models/group_chat_message.dart';
import '../../models/group_chat_branch.dart';
import '../../models/chat_message.dart';
import '../../models/memory.dart';
import '../../models/group_chat_summary.dart';
import '../../models/group_chat_lorebook_entry.dart';
import '../../models/group_public_event_memory.dart';
import '../../models/ai_character.dart';
import '../../models/ai_config.dart';
import '../../models/ai_stream_chunk.dart';
import '../../repositories/local_storage_repository.dart';
import '../../services/ai_service.dart';
import '../../services/log_service.dart';
import '../../services/memory_engine.dart';
import '../../services/moment_context_service.dart';
import '../../utils/message_sanitizer.dart';
import '../../utils/content_filter.dart';
import 'group_chat_speaker.dart';
import 'group_chat_prompts.dart';
import '../../services/group_chat_rolling_summary.dart';
import '../../services/group_chat_prompt_pipeline.dart';

part 'group_chat_event.dart';
part 'group_chat_state.dart';
part 'group_chat_bloc_parts/bloc_core.dart';
part 'group_chat_bloc_parts/gc_sessions.dart';
part 'group_chat_bloc_parts/gc_messages.dart';
part 'group_chat_bloc_parts/gc_helpers.dart';
part 'group_chat_bloc_parts/gc_ai_reply.dart';
part 'group_chat_bloc_parts/gc_config_memory.dart';
part 'group_chat_bloc_parts/gc_session_config.dart';

/// AI 群聊 BLoC
class GroupChatBloc extends Bloc<GroupChatEvent, GroupChatState>
    with
        _GcCore,
        {with_line} {{
  GroupChatBloc(LocalStorageRepository storage, AIService aiService,
      {{MemoryEngine? memoryEngine}})
      : super(GroupChatInitial()) {{
    _storage = storage;
    _aiService = aiService;
    _memoryEngine = memoryEngine ?? MemoryEngine(storage);

    on<GroupChatLoadSessions>(_onLoadSessions);
    on<GroupChatCreate>(_onCreate);
    on<GroupChatDelete>(_onDelete);
    on<GroupChatLoadMessages>(_onLoadMessages);
    on<GroupChatLoadMoreMessages>(_onLoadMoreMessages);
    on<GroupChatSendMessage>(_onSendMessage);
    on<GroupChatUpdateSession>(_onUpdateSession);
    on<GroupChatAddMember>(_onAddMember);
    on<GroupChatRemoveMember>(_onRemoveMember);
    on<GroupChatMarkRead>(_onMarkRead);
    on<GroupChatSetSpeakers>(_onSetSpeakers);
    on<GroupChatAIMessageSaved>(_onAIMessageSaved);
    on<GroupChatUpdateConfig>(_onUpdateConfig);
    on<GroupChatCreateBranch>(_onCreateBranch);
    on<GroupChatSwitchBranch>(_onSwitchBranch);
    on<GroupChatDeleteBranch>(_onDeleteBranch);
    on<GroupChatDeleteMessage>(_onDeleteMessage);
    on<GroupChatToggleBookmark>(_onToggleBookmark);
    on<GroupChatEditAIReply>(_onEditAIReply);
    on<GroupChatRegenerateMessage>(_onRegenerateMessage);
    on<GroupChatSelectSwipe>(_onSelectSwipe);
    on<GroupChatSaveLorebookEntry>(_onSaveLorebookEntry);
    on<GroupChatDeleteLorebookEntry>(_onDeleteLorebookEntry);
    on<GroupChatRecallMessage>(_onRecallMessage);
  }}

  @override
  Future<void> close() {{
    _autoModeTimer?.cancel();
    return super.close();
  }}
}}
"""
# fields that were constructor-initialized as finals need to become late in core
# _groupSummaryRefreshes and _promptPipeline were inline final - keep as late in core
core_t = (OUT / "bloc_core.dart").read_text(encoding="utf-8")
core_t = core_t.replace(
    "final _groupSummaryRefreshes = GroupSummaryRefreshCoordinator();",
    "late final GroupSummaryRefreshCoordinator _groupSummaryRefreshes;",
)
core_t = core_t.replace(
    "final _promptPipeline = const GroupChatPromptPipeline();",
    "late final GroupChatPromptPipeline _promptPipeline;",
)
# _storage etc were final fields - change to late final
for f in [
    "final LocalStorageRepository _storage;",
    "final AIService _aiService;",
    "final MemoryEngine _memoryEngine;",
]:
    core_t = core_t.replace(f, f.replace("final ", "late final "))
(OUT / "bloc_core.dart").write_text(core_t, encoding="utf-8")

shell = shell.replace(
    "    _memoryEngine = memoryEngine ?? MemoryEngine(storage);\n",
    "    _memoryEngine = memoryEngine ?? MemoryEngine(storage);\n"
    "    _groupSummaryRefreshes = GroupSummaryRefreshCoordinator();\n"
    "    _promptPipeline = const GroupChatPromptPipeline();\n",
)
SRC.write_text(shell, encoding="utf-8")
print("shell OK")
