import 'package:flutter/material.dart';
import '../../models/ai_character.dart';
import '../../models/group_relationship.dart';

class RelationshipEditor extends StatelessWidget {
  final List<AICharacter> participants;
  final List<GroupRelationship> relationships;
  final String groupChatId;
  final void Function(String characterIdA, String characterIdB, CharacterRelationship newRel) onRelationshipChanged;

  const RelationshipEditor({
    super.key,
    required this.participants,
    required this.relationships,
    required this.groupChatId,
    required this.onRelationshipChanged,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (participants.length < 2) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            '需要至少两个角色才能设置关系',
            style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeader(context, colorScheme),
        const SizedBox(height: 12),
        _buildMatrix(context, colorScheme),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.purple.withOpacity(0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.device_hub, size: 20, color: Colors.purple),
        ),
        const SizedBox(width: 12),
        const Expanded(
          child: Text(
            '角色关系',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }

  Widget _buildMatrix(BuildContext context, ColorScheme colorScheme) {
    final isDark = colorScheme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withOpacity(0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeaderRow(colorScheme),
              ...List.generate(participants.length, (i) {
                return _buildDataRow(context, i, colorScheme);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(ColorScheme colorScheme) {
    return Row(
      children: [
        SizedBox(
          width: 64,
          child: Text(
            '',
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
        ),
        ...participants.map((p) => SizedBox(
          width: 80,
          child: Center(
            child: Text(
              p.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        )),
      ],
    );
  }

  Widget _buildDataRow(BuildContext context, int rowIndex, ColorScheme colorScheme) {
    final rowChar = participants[rowIndex];

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        children: [
          SizedBox(
            width: 64,
            child: Text(
              rowChar.name,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          ...List.generate(participants.length, (colIndex) {
            if (rowIndex == colIndex) {
              return const SizedBox(
                width: 80,
                child: Center(
                  child: Text('—', style: TextStyle(fontSize: 13, color: Colors.grey)),
                ),
              );
            }
            final colChar = participants[colIndex];
            final rel = _findRelationship(rowChar.id, colChar.id);
            return SizedBox(
              width: 80,
              child: Center(
                child: GestureDetector(
                  onTap: () => _showRelationshipPicker(context, rowChar, colChar, rel),
                  child: _buildRelationshipChip(rel, colorScheme),
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  CharacterRelationship _findRelationship(String idA, String idB) {
    for (final rel in relationships) {
      if (rel.pairContains(idA, idB)) {
        return rel.relationship;
      }
    }
    return CharacterRelationship.stranger;
  }

  Widget _buildRelationshipChip(CharacterRelationship rel, ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: _getRelationshipColor(rel),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        rel.label,
        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  void _showRelationshipPicker(
    BuildContext context,
    AICharacter charA,
    AICharacter charB,
    CharacterRelationship current,
  ) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '${charA.name} → ${charB.name}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 4),
              Text(
                '选择关系类型',
                style: TextStyle(fontSize: 13, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              ...CharacterRelationship.values.map((rel) {
                final isSelected = rel == current;
                return ListTile(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: _getRelationshipColor(rel),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Icon(
                        _getRelationshipIcon(rel),
                        size: 18,
                        color: _getRelationshipIconColor(rel),
                      ),
                    ),
                  ),
                  title: Text(
                    rel.label,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                  subtitle: Text(
                    rel.dialogueStyle,
                    style: TextStyle(fontSize: 12, color: Theme.of(ctx).colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check_circle, color: Theme.of(ctx).colorScheme.primary)
                      : null,
                  onTap: () {
                    Navigator.pop(ctx);
                    onRelationshipChanged(charA.id, charB.id, rel);
                  },
                );
              }),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Color _getRelationshipColor(CharacterRelationship rel) {
    switch (rel) {
      case CharacterRelationship.enemy:
        return Colors.red.shade100;
      case CharacterRelationship.rival:
        return Colors.orange.shade100;
      case CharacterRelationship.ally:
        return Colors.green.shade100;
      case CharacterRelationship.lover:
        return Colors.pink.shade100;
      case CharacterRelationship.friend:
        return Colors.blue.shade100;
      case CharacterRelationship.stranger:
        return Colors.grey.shade200;
      case CharacterRelationship.subordinate:
        return Colors.teal.shade100;
      case CharacterRelationship.superior:
        return Colors.amber.shade100;
    }
  }

  IconData _getRelationshipIcon(CharacterRelationship rel) {
    switch (rel) {
      case CharacterRelationship.enemy:
        return Icons.dangerous_outlined;
      case CharacterRelationship.rival:
        return Icons.sports_mma_outlined;
      case CharacterRelationship.ally:
        return Icons.handshake_outlined;
      case CharacterRelationship.lover:
        return Icons.favorite_outline;
      case CharacterRelationship.friend:
        return Icons.people_outline;
      case CharacterRelationship.stranger:
        return Icons.person_outline;
      case CharacterRelationship.subordinate:
        return Icons.arrow_downward;
      case CharacterRelationship.superior:
        return Icons.arrow_upward;
    }
  }

  Color _getRelationshipIconColor(CharacterRelationship rel) {
    switch (rel) {
      case CharacterRelationship.enemy:
        return Colors.red.shade400;
      case CharacterRelationship.rival:
        return Colors.orange.shade400;
      case CharacterRelationship.ally:
        return Colors.green.shade400;
      case CharacterRelationship.lover:
        return Colors.pink.shade400;
      case CharacterRelationship.friend:
        return Colors.blue.shade400;
      case CharacterRelationship.stranger:
        return Colors.grey.shade500;
      case CharacterRelationship.subordinate:
        return Colors.teal.shade400;
      case CharacterRelationship.superior:
        return Colors.amber.shade700;
    }
  }
}
