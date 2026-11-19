part of 'message_bubble.dart';

extension _MessageBubbleTextEntities on _MessageBubbleState {
  /// The answer is nearly always "no" and never changes for a given message, so
  /// it is memoised; the scan itself walks the source lazily and quits on the
  /// first ordinary character instead of building a stripped copy first.
  bool _isEmojiOnlyText(String text) {
    if (_emojiOnlyKey == text) return _emojiOnlyValue;
    _emojiOnlyKey = text;
    _emojiOnlyValue = _computeIsEmojiOnlyText(text);
    return _emojiOnlyValue;
  }

  bool _computeIsEmojiOnlyText(String text) {
    var count = 0;
    for (final cluster in text.characters) {
      if (_isWhitespaceCluster(cluster)) continue;
      if (!_isEmojiCluster(cluster)) return false;
      count++;
    }
    return count > 1;
  }

  bool _isWhitespaceCluster(String cluster) {
    for (final rune in cluster.runes) {
      if (!_isWhitespaceRune(rune)) return false;
    }
    return true;
  }

  /// The set `RegExp(r'\s')` matches, which is what this check used to strip.
  bool _isWhitespaceRune(int rune) =>
      rune == 0x20 ||
      (rune >= 0x09 && rune <= 0x0D) ||
      rune == 0xA0 ||
      rune == 0x1680 ||
      (rune >= 0x2000 && rune <= 0x200A) ||
      rune == 0x2028 ||
      rune == 0x2029 ||
      rune == 0x202F ||
      rune == 0x205F ||
      rune == 0x3000 ||
      rune == 0xFEFF;

  bool _isEmojiCluster(String cluster) {
    final runes = cluster.runes.toList();
    final keycap = runes.contains(0x20E3);
    for (final rune in runes) {
      if (_isEmojiModifier(rune)) continue;
      if (keycap && _isKeycapBase(rune)) continue;
      if (!_isEmojiCodepoint(rune)) return false;
    }
    return true;
  }

  bool _isEmojiModifier(int rune) =>
      rune == 0x200D ||
      rune == 0xFE0E ||
      rune == 0xFE0F ||
      rune == 0x20E3 ||
      (rune >= 0x1F3FB && rune <= 0x1F3FF);

  bool _isKeycapBase(int rune) =>
      (rune >= 0x30 && rune <= 0x39) || rune == 0x23 || rune == 0x2A;

  bool _isEmojiCodepoint(int rune) =>
      rune == 0x00A9 ||
      rune == 0x00AE ||
      rune == 0x203C ||
      rune == 0x2049 ||
      rune == 0x2122 ||
      rune == 0x2139 ||
      rune == 0x3030 ||
      rune == 0x303D ||
      rune == 0x3297 ||
      rune == 0x3299 ||
      (rune >= 0x2194 && rune <= 0x21AA) ||
      (rune >= 0x2300 && rune <= 0x23FF) ||
      (rune >= 0x2600 && rune <= 0x27BF) ||
      (rune >= 0x2934 && rune <= 0x2935) ||
      (rune >= 0x1F000 && rune <= 0x1FAFF);

  bool _showsTranslationFor(ChatMessage source) =>
      source.isTranslating ||
      (source.translationText?.trim().isNotEmpty ?? false);

  bool _showsTranslationBlockFor(ChatMessage source) {
    if (source.isTranslating) return true;
    if (!(source.translationText?.trim().isNotEmpty ?? false)) return false;
    return widget.bubble.translationDisplayStyle !=
        TranslationDisplayStyle.translatedOnly;
  }

  bool _translationReplacesOriginalFor(ChatMessage source) =>
      widget.bubble.translationDisplayStyle ==
          TranslationDisplayStyle.translatedOnly &&
      !widget.bubble.showOriginalTranslationMessageIds.contains(source.id) &&
      !source.isTranslating &&
      (source.translationText?.trim().isNotEmpty ?? false);

  Color _translatedOnlyTextColor(bool outgoing) {
    final base = outgoing ? _outgoingTextColor : _incomingTextColor;
    return Color.lerp(base, AppTheme.brand, outgoing ? 0.36 : 0.52)!;
  }

  Widget? _linkPreviewMedia(MessageLinkPreview preview, double maxWidth) {
    final media = preview.image;
    if (media == null) return null;
    final large =
        preview.showLargeMedia || preview.type == 'linkPreviewTypePhoto';
    final width = large ? maxWidth : math.min(maxWidth, 210.0);
    final size = _fitSize(
      width: preview.imageWidth,
      height: preview.imageHeight,
      maxWidth: width,
      maxHeight: large ? 180 : 120,
      fallback: Size(width, large ? 140 : 96),
    );
    return SizedBox(
      key: ValueKey('messageLinkPreviewMedia-${message.id}'),
      width: size.width,
      height: size.height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          TDImage(
            photo: media,
            cornerRadius: 0,
            cacheWidth: _cachePx(size.width),
            cacheHeight: _cachePx(size.height),
          ),
          if (preview.video != null)
            Center(
              child: Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.45),
                  shape: BoxShape.circle,
                ),
                child: const AppIcon(
                  HeroAppIcons.play,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Color _replyQuoteBackground(bool outgoing) {
    if (_messageColors != null) {
      return _messageAccentFill(_messageReplyLineColor(outgoing));
    }
    final base = outgoing ? _outgoingBubbleColor : _incomingBubbleColor;
    final dark = _brightness == Brightness.dark;
    return Color.lerp(base, dark ? Colors.white : Colors.black, 0.10)!;
  }

  /// Trailing inline meta: delivery progress, replaced by edit status.
  InlineSpan _metaSpan(bool outgoing) {
    final faint = _messageTimeColor(outgoing);
    // At most one glyph, so it needs no flex row to hold it.
    final Widget glyph;
    if (widget.bubble.message.isEdited) {
      glyph = AppIcon(
        HeroAppIcons.penToSquare,
        key: const ValueKey('messageDeliveryEdited'),
        size: 10,
        color: faint,
      );
    } else if (outgoing) {
      glyph = _deliveryTick(
        sentColor: _showsMessageBubbleSurface
            ? Colors.white
            : _outgoingTextColor,
      );
    } else {
      glyph = const SizedBox.shrink();
    }
    return WidgetSpan(
      child: Padding(
        padding: const EdgeInsets.only(left: 6, top: 2),
        child: glyph,
      ),
    );
  }

  /// Spaces one rendered text for display, when 盘古之白 is on.
  ///
  /// The stored message is never rewritten: copy, quote, edit, forward and
  /// search all keep reading [ChatMessage.text]. Only what the bubble paints
  /// changes, together with the entity ranges that style it.
  PanguDisplay _displaySpacing(String text, List<MessageTextEntity> entities) {
    if (!_theme.panguOnReceive) return PanguDisplay(text, entities, const []);
    return _panguSpacing.resolve(text, entities);
  }

  List<Widget> _richTextWidgets(
    String text,
    Color base,
    Color link,
    bool outgoing,
    bool appendMeta, [
    List<MessageTextEntity>? entities,
    double fontSize = 15,
    bool bodyLeading = true,
  ]) {
    final resolvedFontSize = fontSize == AppTextSize.body
        ? AppTextSize.messageBody()
        : fontSize;
    // 盘古之白 is a display pass: the spaced text and its shifted entities are
    // resolved once here so every slice below — inline run, quote block, code
    // block — works on the same pair. The stored message keeps its own text.
    final spaced = _displaySpacing(text, entities ?? message.textEntities);
    final sourceText = spaced.text;
    final sourceEntities = spaced.entities;
    final blocks =
        sourceEntities.where((e) => e.isBlockQuote || e.isPreBlock).toList()
          ..sort((a, b) => a.offset.compareTo(b.offset));
    if (blocks.isEmpty) {
      return [
        _richText(
          sourceText,
          base,
          link,
          0,
          sourceText.length,
          outgoing,
          appendMeta,
          entities: sourceEntities,
          fontSize: resolvedFontSize,
          bodyLeading: bodyLeading,
        ),
      ];
    }

    final widgets = <Widget>[];
    var cursor = 0;
    var metaAdded = false;
    for (final block in blocks) {
      final start = block.offset.clamp(0, sourceText.length).toInt();
      final end = block.end.clamp(start, sourceText.length).toInt();
      if (end <= cursor) continue;
      if (start > cursor) {
        widgets.add(
          _richText(
            sourceText,
            base,
            link,
            cursor,
            start,
            outgoing,
            false,
            entities: sourceEntities,
            fontSize: resolvedFontSize,
            bodyLeading: bodyLeading,
          ),
        );
        widgets.add(const SizedBox(height: 5));
      }
      widgets.add(
        block.isPreBlock
            ? _preBlock(
                block,
                sourceText,
                start,
                end,
                base,
                link,
                sourceEntities,
                resolvedFontSize,
              )
            : _quoteBlock(
                block,
                sourceText,
                start,
                end,
                base,
                link,
                outgoing,
                sourceEntities,
                resolvedFontSize,
                bodyLeading,
              ),
      );
      cursor = end;
    }
    if (cursor < sourceText.length) {
      widgets.add(const SizedBox(height: 5));
      widgets.add(
        _richText(
          sourceText,
          base,
          link,
          cursor,
          sourceText.length,
          outgoing,
          appendMeta,
          entities: sourceEntities,
          fontSize: resolvedFontSize,
          bodyLeading: bodyLeading,
        ),
      );
      metaAdded = appendMeta;
    }
    if (appendMeta && !metaAdded) {
      widgets.add(
        Align(
          alignment: Alignment.centerRight,
          child: RichText(
            textScaler: MediaQuery.textScalerOf(context),
            text: TextSpan(children: [_metaSpan(outgoing)]),
          ),
        ),
      );
    }
    return widgets;
  }

  void _copyMonospaceText(String text) {
    if (text.isEmpty) return;
    Clipboard.setData(ClipboardData(text: text)).then((_) {
      if (mounted) {
        showToast(context, AppStringKeys.topicPostContentCopied);
      }
    });
  }

  List<InlineSpan> _entitySpans(
    String text,
    int start,
    int end,
    Color base,
    Color link,
    List<MessageTextEntity> sourceEntities,
    double fontSize,
    bool outgoing,
  ) {
    final entities =
        sourceEntities
            .where((e) => !e.isBlockQuote && e.offset < end && e.end > start)
            .toList()
          ..sort((a, b) => a.offset.compareTo(b.offset));
    final spans = <InlineSpan>[];
    var cursor = start;
    while (cursor < end) {
      var next = end;
      for (final e in entities) {
        final eStart = e.offset.clamp(start, end).toInt();
        final eEnd = e.end.clamp(start, end).toInt();
        if (eStart > cursor) next = math.min(next, eStart);
        if (eStart <= cursor && eEnd > cursor) next = math.min(next, eEnd);
      }
      if (next <= cursor) next = cursor + 1;
      final active = entities
          .where((e) => e.offset <= cursor && e.end >= next)
          .toList();
      final segment = text.substring(cursor, next);
      if (segment == '\n') {
        spans.add(const TextSpan(text: '\n'));
        cursor = next;
        continue;
      }
      spans.addAll(
        _textSegmentSpans(segment, active, base, link, fontSize, outgoing),
      );
      cursor = next;
    }
    return spans;
  }

  List<InlineSpan> _textSegmentSpans(
    String segment,
    List<MessageTextEntity> active,
    Color base,
    Color link,
    double fontSize,
    bool outgoing,
  ) {
    final spoilerKey = active.spoilerKey;
    final spoilerHidden =
        spoilerKey != null && !_revealedSpoilers.contains(spoilerKey);
    if (spoilerHidden) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (!mounted) return;
          _updateState(() => _revealedSpoilers.add(spoilerKey));
        };
      _linkRecognizers.add(recognizer);
      return [
        TextSpan(
          text: segment,
          style: _entityStyle(active, base, link),
          recognizer: recognizer,
        ),
      ];
    }

    final effectiveActive = spoilerKey == null
        ? active
        : active
              .where((e) => e.type != 'textEntityTypeSpoiler')
              .toList(growable: false);
    final style = _entityStyle(effectiveActive, base, link);
    final inlineButton = _inlineButton(effectiveActive);
    if (inlineButton != null) {
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 88, maxWidth: 220),
            child: _buttonCell(inlineButton, outgoing),
          ),
        ),
      ];
    }
    final customEmojiId = effectiveActive.customEmojiId;
    if (customEmojiId != null) {
      return [
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: SelectableCustomEmojiView(
            id: customEmojiId,
            fallbackText: segment,
            size: math.max(20, (fontSize * 1.15).roundToDouble()),
            color: style.color ?? base,
          ),
        ),
      ];
    }
    if (effectiveActive.hasMathematicalExpression) {
      return [_inlineMathSpan(segment, style, fontSize)];
    }
    if (_hasInlineCode(effectiveActive)) {
      return [_inlineCodeSpan(segment, style, fontSize)];
    }
    final userId = effectiveActive.mentionUserId;
    if (userId != null) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ProfileDetailView(userId: userId, name: segment),
            ),
          );
        };
      _linkRecognizers.add(recognizer);
      return [TextSpan(text: segment, style: style, recognizer: recognizer)];
    }
    final target = _entityTapTarget(segment, effectiveActive);
    if (target == '__bot_command__') {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => widget.bubble.onBotCommandTap?.call(segment.trim());
      _linkRecognizers.add(recognizer);
      return [TextSpan(text: segment, style: style, recognizer: recognizer)];
    }
    if (target == '__hashtag__') {
      if (widget.bubble.onHashtagTap == null) {
        return [TextSpan(text: segment, style: style)];
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () =>
            widget.bubble.onHashtagTap?.call(normalizedHashtag(segment));
      _linkRecognizers.add(recognizer);
      return [TextSpan(text: segment, style: style, recognizer: recognizer)];
    }
    if (target != null) {
      final recognizer = TapGestureRecognizer()
        ..onTap = () => openLink(context, target);
      _linkRecognizers.add(recognizer);
      return [TextSpan(text: segment, style: style, recognizer: recognizer)];
    }
    if (_hasPreCode(active)) return [TextSpan(text: segment, style: style)];
    return _linkSpansStyled(segment, style, link);
  }

  InlineSpan _inlineCodeSpan(String segment, TextStyle style, double fontSize) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: GestureDetector(
        key: const ValueKey('message-inline-code'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _copyMonospaceText(segment),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(
            color: _codeBackgroundColor,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(segment, style: style.copyWith(fontSize: fontSize)),
        ),
      ),
    );
  }

  InlineSpan _inlineMathSpan(String segment, TextStyle style, double fontSize) {
    return WidgetSpan(
      alignment: PlaceholderAlignment.baseline,
      baseline: TextBaseline.alphabetic,
      child: _LatexView(
        expression: segment,
        style: style.copyWith(fontSize: fontSize),
      ),
    );
  }

  bool _hasInlineCode(List<MessageTextEntity> active) {
    return active.any((e) => e.type == 'textEntityTypeCode');
  }

  MessageButton? _inlineButton(List<MessageTextEntity> active) {
    for (final entity in active.reversed) {
      if (entity.type == 'textEntityTypeButton' && entity.button != null) {
        return entity.button;
      }
    }
    return null;
  }

  bool _hasPreCode(List<MessageTextEntity> active) {
    return active.any(
      (e) => e.type == 'textEntityTypePre' || e.type == 'textEntityTypePreCode',
    );
  }

  TextStyle _entityStyle(
    List<MessageTextEntity> active,
    Color base,
    Color link,
  ) {
    var color = base;
    var weight = FontWeight.w400;
    FontStyle? fontStyle;
    Color? backgroundColor;
    var useCodeFont = false;
    var fontFeatures = const <FontFeature>[];
    final decorations = <TextDecoration>[];
    var isLink = false;
    for (final e in active) {
      switch (e.type) {
        case 'textEntityTypeBold':
          weight = FontWeight.w600;
        case 'textEntityTypeItalic':
          fontStyle = FontStyle.italic;
        case 'textEntityTypeUnderline':
          decorations.add(TextDecoration.underline);
        case 'textEntityTypeStrikethrough':
          decorations.add(TextDecoration.lineThrough);
        case 'textEntityTypeCode':
          useCodeFont = true;
        case 'textEntityTypePre':
        case 'textEntityTypePreCode':
          useCodeFont = true;
        case 'textEntityTypeSpoiler':
          color = base.withValues(alpha: 0.06);
          backgroundColor = base.withValues(alpha: 0.34);
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
          color = link;
          isLink = true;
        case 'textEntityTypeMediaTimestamp':
          color = link;
          weight = FontWeight.w600;
          isLink = true;
        case 'textEntityTypeMarked':
          backgroundColor = Colors.amber.withValues(alpha: 0.32);
        case 'textEntityTypeSubscript':
          fontFeatures = const [FontFeature.subscripts()];
        case 'textEntityTypeSuperscript':
          fontFeatures = const [FontFeature.superscripts()];
        case 'textEntityTypeDateTime':
          color = link;
          isLink = true;
      }
    }
    final fallbackUnderline =
        isLink &&
        !active.any((entity) => entity.type == 'textEntityTypeSpoiler') &&
        _underlinesLinks(base, link);
    if (fallbackUnderline && !decorations.contains(TextDecoration.underline)) {
      decorations.add(TextDecoration.underline);
    }
    final style = TextStyle(
      color: color,
      fontWeight: weight,
      fontStyle: fontStyle,
      backgroundColor: backgroundColor,
      decoration: decorations.isEmpty
          ? null
          : TextDecoration.combine(decorations),
      decorationColor: color,
      decorationStyle: fallbackUnderline ? TextDecorationStyle.solid : null,
      decorationThickness: fallbackUnderline ? 1.0 : null,
      fontFeatures: fontFeatures.isEmpty ? null : fontFeatures,
    );
    return useCodeFont ? _theme.codeTextStyle(style) : style;
  }

  String? _entityTapTarget(String segment, List<MessageTextEntity> active) {
    for (final e in active.reversed) {
      switch (e.type) {
        case 'textEntityTypeTextUrl':
          return e.url;
        case 'textEntityTypeUrl':
          return segment;
        case 'textEntityTypeMention':
          return segment.startsWith('@')
              ? 'https://t.me/${segment.substring(1)}'
              : null;
        case 'textEntityTypeHashtag':
          return '__hashtag__';
        case 'textEntityTypeCashtag':
        case 'textEntityTypeBotCommand':
          return e.type == 'textEntityTypeBotCommand'
              ? '__bot_command__'
              : null;
        case 'textEntityTypeEmailAddress':
          return 'mailto:$segment';
        case 'textEntityTypePhoneNumber':
          return telephoneUri(segment);
        case 'textEntityTypeBankCardNumber':
          return null;
        case 'textEntityTypeMentionName':
          return null;
      }
    }
    return null;
  }

  List<InlineSpan> _linkSpansStyled(
    String text,
    TextStyle baseStyle,
    Color link,
  ) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _MessageBubbleState._linkRegExp.allMatches(text)) {
      if (m.start > last) {
        spans.add(
          TextSpan(text: text.substring(last, m.start), style: baseStyle),
        );
      }
      final matched = text.substring(m.start, m.end);
      final isMention = m.group(2) != null;
      final isHashtag = m.group(3) != null;
      final target = isMention
          ? 'https://t.me/${matched.substring(1)}'
          : matched;
      if (isHashtag && widget.bubble.onHashtagTap == null) {
        spans.add(
          TextSpan(text: matched, style: _autoLinkStyle(baseStyle, link)),
        );
        last = m.end;
        continue;
      }
      final recognizer = TapGestureRecognizer()
        ..onTap = () {
          if (isHashtag) {
            widget.bubble.onHashtagTap?.call(normalizedHashtag(matched));
          } else {
            openLink(context, target);
          }
        };
      _linkRecognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: matched,
          style: _autoLinkStyle(baseStyle, link),
          recognizer: recognizer,
        ),
      );
      last = m.end;
    }
    if (last < text.length) {
      spans.add(TextSpan(text: text.substring(last), style: baseStyle));
    }
    return spans;
  }

  TextStyle _autoLinkStyle(TextStyle baseStyle, Color link) {
    if (!_underlinesLinks(baseStyle.color ?? _colors.textPrimary, link)) {
      return baseStyle.copyWith(color: link);
    }
    final existing = baseStyle.decoration;
    final decoration = existing == null || existing == TextDecoration.none
        ? TextDecoration.underline
        : existing == TextDecoration.underline
        ? existing
        : TextDecoration.combine([existing, TextDecoration.underline]);
    return baseStyle.copyWith(
      color: link,
      decoration: decoration,
      decorationColor: link,
      decorationStyle: TextDecorationStyle.solid,
      decorationThickness: 1.0,
    );
  }
}
