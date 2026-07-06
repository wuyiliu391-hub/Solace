import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../config/moments_theme.dart';

/// 可点击的 @提及 / #话题 / URL 文本组件
class UrlText extends StatelessWidget {
  final String text;
  final TextStyle? style;
  final int? maxLines;
  final ValueChanged<String>? onMentionTap;
  final ValueChanged<String>? onHashtagTap;
  final ValueChanged<String>? onUrlTap;

  const UrlText({
    super.key,
    required this.text,
    this.style,
    this.maxLines,
    this.onMentionTap,
    this.onHashtagTap,
    this.onUrlTap,
  });

  static final _regex = RegExp(
    r'([@#])\w+|(https?|ftp)://[-A-Za-z0-9+&@#/%?=~_|!:,.;]+[-A-Za-z0-9+&@#/%=~_|]*',
  );

  @override
  Widget build(BuildContext context) {
    final defaultStyle = style ??
        TextStyle(
          fontSize: 16,
          color: MomentsTheme.textPrimary(context),
          height: 1.3,
        );

    final spans = <TextSpan>[];
    var lastEnd = 0;

    for (final match in _regex.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(
          text: text.substring(lastEnd, match.start),
          style: defaultStyle,
        ));
      }

      final matched = match.group(0)!;
      TextStyle linkStyle;
      VoidCallback? onTap;

      if (matched.startsWith('@')) {
        linkStyle = defaultStyle.copyWith(
          color: MomentsTheme.mention(context),
          fontWeight: FontWeight.w500,
        );
        onTap = () => onMentionTap?.call(matched.substring(1));
      } else if (matched.startsWith('#')) {
        linkStyle = defaultStyle.copyWith(
          color: MomentsTheme.hashtag(context),
          fontWeight: FontWeight.w500,
        );
        onTap = () => onHashtagTap?.call(matched.substring(1));
      } else {
        linkStyle = defaultStyle.copyWith(
          color: MomentsTheme.urlColor(context),
          decoration: TextDecoration.underline,
        );
        onTap = () => onUrlTap?.call(matched);
      }

      spans.add(TextSpan(
        text: matched,
        style: linkStyle,
        recognizer: TapGestureRecognizer()..onTap = onTap,
      ));
      lastEnd = match.end;
    }

    if (lastEnd < text.length) {
      spans.add(TextSpan(
        text: text.substring(lastEnd),
        style: defaultStyle,
      ));
    }

    return RichText(
      text: TextSpan(children: spans),
      maxLines: maxLines,
      overflow: maxLines != null ? TextOverflow.ellipsis : TextOverflow.clip,
    );
  }
}
