import 'package:flutter/material.dart';

class TopicSuggestions extends StatelessWidget {
  final List<String> topics;
  final ValueChanged<String> onTap;

  const TopicSuggestions({super.key, required this.topics, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (topics.isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Row(
        children: [
          Icon(Icons.lightbulb_outline, size: 14, color: colorScheme.primary.withOpacity(0.6)),
          const SizedBox(width: 6),
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: topics.map((topic) => Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => onTap(topic),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer.withOpacity(0.4),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.primary.withOpacity(0.2)),
                      ),
                      child: Text(
                        topic,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                )).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
