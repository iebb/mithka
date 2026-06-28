import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../profile/profile_detail_view.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'link_handler.dart';

class TelegramRichText extends StatefulWidget {
  const TelegramRichText({
    super.key,
    required this.text,
    this.entities = const [],
    this.style,
    this.linkColor,
    this.maxLines,
    this.overflow = TextOverflow.clip,
    this.onBotCommandTap,
    this.quoteBackgroundColor,
  });

  final String text;
  final List<MessageTextEntity> entities;
  final TextStyle? style;
  final Color? linkColor;
  final int? maxLines;
  final TextOverflow overflow;
  final ValueChanged<String>? onBotCommandTap;
  final Color? quoteBackgroundColor;

  @override
  State<TelegramRichText> createState() => _TelegramRichTextState();
}

class _TelegramRichTextState extends State<TelegramRichText> {
  static final _linkRegExp = RegExp(
    r'((?:https?:\/\/|www\.|t\.me\/|telegram\.me\/|tg:\/\/)[^\s]+)|(?<![\w@])(@[A-Za-z0-9_]{4,32})',
    caseSensitive: false,
  );

  final _recognizers = <GestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final baseStyle =
        widget.style ??
        DefaultTextStyle.of(
          context,
        ).style.copyWith(color: context.colors.textPrimary);
    final linkColor = widget.linkColor ?? context.colors.linkBlue;
    if (widget.quoteBackgroundColor != null && _hasBlockQuote()) {
      return _richTextWithQuoteBlocks(context, baseStyle, linkColor);
    }
    return RichText(
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      text: TextSpan(
        style: baseStyle,
        children: _spans(context, baseStyle, linkColor),
      ),
    );
  }

  bool _hasBlockQuote() =>
      _validEntities(widget.text.length).any((entity) => entity.isBlockQuote);

  Widget _richTextWithQuoteBlocks(
    BuildContext context,
    TextStyle baseStyle,
    Color linkColor,
  ) {
    final text = widget.text;
    final entities = _validEntities(text.length);
    final blocks = entities.where((entity) => entity.isBlockQuote).toList()
      ..sort((a, b) => a.offset.compareTo(b.offset));
    final children = <Widget>[];
    var cursor = 0;
    for (final block in blocks) {
      final start = block.offset.clamp(0, text.length).toInt();
      final end = block.end.clamp(start, text.length).toInt();
      if (end <= cursor) continue;
      if (start > cursor) {
        children.add(
          _richTextSegment(text, cursor, start, entities, baseStyle, linkColor),
        );
      }
      children.add(
        Padding(
          padding: EdgeInsets.only(
            top: children.isEmpty ? 0 : 6,
            bottom: end < text.length ? 6 : 0,
          ),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 7),
            decoration: BoxDecoration(
              color: widget.quoteBackgroundColor,
              borderRadius: BorderRadius.circular(8),
            ),
            child: _richTextSegment(
              text,
              start,
              end,
              entities.where((entity) => !entity.isBlockQuote).toList(),
              baseStyle,
              linkColor,
            ),
          ),
        ),
      );
      cursor = end;
    }
    if (cursor < text.length) {
      children.add(
        _richTextSegment(
          text,
          cursor,
          text.length,
          entities,
          baseStyle,
          linkColor,
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }

  Widget _richTextSegment(
    String source,
    int start,
    int end,
    List<MessageTextEntity> sourceEntities,
    TextStyle baseStyle,
    Color linkColor,
  ) {
    final text = source.substring(start, end);
    return TelegramRichText(
      text: text,
      entities: _sliceEntities(sourceEntities, start, end),
      style: baseStyle,
      linkColor: linkColor,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
      onBotCommandTap: widget.onBotCommandTap,
    );
  }

  List<MessageTextEntity> _sliceEntities(
    List<MessageTextEntity> source,
    int start,
    int end,
  ) {
    final sliced = <MessageTextEntity>[];
    for (final entity in source) {
      if (entity.end <= start || entity.offset >= end || entity.isBlockQuote) {
        continue;
      }
      final nextStart = entity.offset.clamp(start, end).toInt();
      final nextEnd = entity.end.clamp(nextStart, end).toInt();
      if (nextEnd <= nextStart) continue;
      sliced.add(
        MessageTextEntity(
          offset: nextStart - start,
          length: nextEnd - nextStart,
          type: entity.type,
          url: entity.url,
          userId: entity.userId,
          customEmojiId: entity.customEmojiId,
          language: entity.language,
        ),
      );
    }
    return sliced;
  }

  List<InlineSpan> _spans(
    BuildContext context,
    TextStyle baseStyle,
    Color linkColor,
  ) {
    final text = widget.text;
    if (text.isEmpty) return const [];
    final entities = _validEntities(text.length);
    if (entities.isEmpty) {
      return _autoLinkSpans(context, text, baseStyle, linkColor);
    }

    final cuts = <int>{0, text.length};
    for (final entity in entities) {
      cuts.add(entity.offset);
      cuts.add(entity.end);
    }
    final orderedCuts = cuts.toList()..sort();
    final spans = <InlineSpan>[];
    for (var i = 0; i < orderedCuts.length - 1; i++) {
      final start = orderedCuts[i];
      final end = orderedCuts[i + 1];
      if (start >= end) continue;
      final segment = text.substring(start, end);
      final active = entities
          .where((entity) => entity.offset < end && entity.end > start)
          .toList(growable: false);
      spans.addAll(
        _entitySpans(context, segment, active, baseStyle, linkColor),
      );
    }
    return spans;
  }

  List<MessageTextEntity> _validEntities(int textLength) {
    return widget.entities
        .where(
          (entity) =>
              entity.length > 0 &&
              entity.offset >= 0 &&
              entity.offset < textLength &&
              entity.end <= textLength,
        )
        .toList()
      ..sort((a, b) {
        final start = a.offset.compareTo(b.offset);
        return start != 0 ? start : b.length.compareTo(a.length);
      });
  }

  List<InlineSpan> _entitySpans(
    BuildContext context,
    String segment,
    List<MessageTextEntity> active,
    TextStyle baseStyle,
    Color linkColor,
  ) {
    final style = _entityStyle(active, baseStyle, linkColor);
    final mentionUserId = _mentionUserId(active);
    if (mentionUserId != null) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  ProfileDetailView(userId: mentionUserId, name: segment),
            ),
          );
        };
      _recognizers.add(recognizer);
      return [TextSpan(text: segment, style: style, recognizer: recognizer)];
    }

    final target = _entityTapTarget(segment, active);
    if (target == '__bot_command__') {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.onBotCommandTap?.call(segment.trim());
      _recognizers.add(recognizer);
      return [TextSpan(text: segment, style: style, recognizer: recognizer)];
    }
    if (target != null) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => openLink(context, target);
      _recognizers.add(recognizer);
      return [TextSpan(text: segment, style: style, recognizer: recognizer)];
    }

    if (_hasCode(active)) return [TextSpan(text: segment, style: style)];
    return _autoLinkSpans(context, segment, style, linkColor);
  }

  TextStyle _entityStyle(
    List<MessageTextEntity> active,
    TextStyle baseStyle,
    Color linkColor,
  ) {
    var style = baseStyle;
    final decorations = <TextDecoration>[];
    for (final entity in active) {
      switch (entity.type) {
        case 'textEntityTypeBold':
          style = style.copyWith(fontWeight: FontWeight.w700);
        case 'textEntityTypeItalic':
          style = style.copyWith(fontStyle: FontStyle.italic);
        case 'textEntityTypeUnderline':
          decorations.add(TextDecoration.underline);
        case 'textEntityTypeStrikethrough':
          decorations.add(TextDecoration.lineThrough);
        case 'textEntityTypeCode':
        case 'textEntityTypePre':
        case 'textEntityTypePreCode':
          style = style.copyWith(
            fontFamily: 'monospace',
            backgroundColor: (style.color ?? Colors.black).withValues(
              alpha: 0.10,
            ),
          );
        case 'textEntityTypeSpoiler':
          final color = style.color ?? Colors.black;
          style = style.copyWith(
            color: color.withValues(alpha: 0.08),
            backgroundColor: color.withValues(alpha: 0.28),
          );
        case 'textEntityTypeMarked':
          style = style.copyWith(
            backgroundColor: Colors.amber.withValues(alpha: 0.32),
          );
        case 'textEntityTypeTextUrl':
        case 'textEntityTypeUrl':
        case 'textEntityTypeMention':
        case 'textEntityTypeMentionName':
        case 'textEntityTypeHashtag':
        case 'textEntityTypeCashtag':
        case 'textEntityTypeBotCommand':
        case 'textEntityTypeEmailAddress':
        case 'textEntityTypePhoneNumber':
        case 'textEntityTypeBankCardNumber':
        case 'textEntityTypeMediaTimestamp':
        case 'textEntityTypeDateTime':
          style = style.copyWith(color: linkColor);
      }
    }
    if (decorations.isNotEmpty) {
      style = style.copyWith(
        decoration: TextDecoration.combine(decorations),
        decorationColor: style.color,
      );
    }
    return style;
  }

  bool _hasCode(List<MessageTextEntity> active) {
    return active.any(
      (entity) =>
          entity.type == 'textEntityTypeCode' ||
          entity.type == 'textEntityTypePre' ||
          entity.type == 'textEntityTypePreCode',
    );
  }

  int? _mentionUserId(List<MessageTextEntity> active) {
    for (final entity in active.reversed) {
      if (entity.type == 'textEntityTypeMentionName' && entity.userId != null) {
        return entity.userId;
      }
    }
    return null;
  }

  String? _entityTapTarget(String segment, List<MessageTextEntity> active) {
    for (final entity in active.reversed) {
      switch (entity.type) {
        case 'textEntityTypeTextUrl':
          return entity.url;
        case 'textEntityTypeUrl':
          return segment;
        case 'textEntityTypeMention':
          return segment.startsWith('@')
              ? 'https://t.me/${segment.substring(1)}'
              : null;
        case 'textEntityTypeBotCommand':
          return '__bot_command__';
        case 'textEntityTypeEmailAddress':
          return 'mailto:$segment';
        case 'textEntityTypePhoneNumber':
          return 'tel:${segment.replaceAll(RegExp(r'[^0-9+]'), '')}';
      }
    }
    return null;
  }

  List<InlineSpan> _autoLinkSpans(
    BuildContext context,
    String text,
    TextStyle baseStyle,
    Color linkColor,
  ) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final match in _linkRegExp.allMatches(text)) {
      if (match.start > last) {
        spans.add(TextSpan(text: text.substring(last, match.start)));
      }
      final matched = text.substring(match.start, match.end);
      final isMention = match.group(2) != null;
      final target = isMention
          ? 'https://t.me/${matched.substring(1)}'
          : matched;
      final recognizer = TapGestureRecognizer()
        ..onTap = () => openLink(context, target);
      _recognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: matched,
          style: baseStyle.copyWith(
            color: linkColor,
            decoration: isMention
                ? baseStyle.decoration
                : TextDecoration.underline,
            decorationColor: linkColor,
          ),
          recognizer: recognizer,
        ),
      );
      last = match.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }
}
