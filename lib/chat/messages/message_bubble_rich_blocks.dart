part of 'message_bubble.dart';

extension _MessageBubbleRichBlocks on _MessageBubbleState {
  List<Widget> _richBlockWidgets(
    List<RichMessageBlock> blocks,
    bool outgoing, {
    Color? textLinkColor,
    String blockPath = '',
  }) {
    final widgets = <Widget>[];
    for (var index = 0; index < blocks.length; index++) {
      final block = blocks[index];
      if (widgets.isNotEmpty) widgets.add(const SizedBox(height: 8));
      final widget = _richBlockWidget(
        block,
        outgoing,
        textLinkColor: textLinkColor,
        // Nested quotes fold independently, so every block carries the index
        // path that reaches it inside this message's rich tree.
        blockPath: blockPath.isEmpty ? '$index' : '$blockPath.$index',
      );
      if (widget != null) {
        widgets.add(
          KeyedSubtree(
            key: ValueKey('rich-message-block-$index-${block.kind.name}'),
            child: widget,
          ),
        );
      }
    }
    return widgets;
  }

  Widget? _richBlockWidget(
    RichMessageBlock block,
    bool outgoing, {
    Color? textLinkColor,
    String blockPath = '',
  }) {
    return switch (block.kind) {
      RichMessageBlockKind.paragraph ||
      RichMessageBlockKind.heading ||
      RichMessageBlockKind.preformatted ||
      RichMessageBlockKind.footer ||
      RichMessageBlockKind.thinking => _richTextBlock(
        block,
        outgoing,
        linkColor: textLinkColor,
      ),
      RichMessageBlockKind.divider => Divider(
        height: 12,
        color: _colors.divider,
      ),
      RichMessageBlockKind.math => _richMathBlock(
        block.mathExpression ?? '',
        outgoing,
      ),
      RichMessageBlockKind.anchor => const SizedBox.shrink(),
      RichMessageBlockKind.buttonRow => SelectionContainer.disabled(
        child: _richButtonRowBlock(block, outgoing),
      ),
      RichMessageBlockKind.list => _richListBlock(
        block,
        outgoing,
        blockPath: blockPath,
      ),
      RichMessageBlockKind.blockQuote || RichMessageBlockKind.pullQuote =>
        _richQuoteContainer(block, outgoing, blockKey: blockPath),
      RichMessageBlockKind.animation ||
      RichMessageBlockKind.audio ||
      RichMessageBlockKind.photo ||
      RichMessageBlockKind.video ||
      RichMessageBlockKind.voiceNote => _richMediaBlock(block, outgoing),
      RichMessageBlockKind.collage => _richCollageBlock(block, outgoing),
      RichMessageBlockKind.slideshow => _richSlideshowBlock(block, outgoing),
      RichMessageBlockKind.table => _richTableBlock(block, outgoing),
      RichMessageBlockKind.details => _richDetailsBlock(
        block,
        outgoing,
        blockPath: blockPath,
      ),
      RichMessageBlockKind.map => _richMapBlock(block, outgoing),
    };
  }

  String _richListLabel(RichMessageListItem item, int index) {
    if (item.label.isNotEmpty) return item.label;
    if (item.value > 0 || item.numberingType.isNotEmpty) {
      return '${item.value > 0 ? item.value : index + 1}.';
    }
    return '•';
  }

  /// One line of rich-block body text, including the body leading used by
  /// quote paragraphs. Keep the folding cap in sync with their actual layout.
  double _richQuoteLineHeight() {
    final painter = TextPainter(
      text: TextSpan(
        text: 'M',
        style: DefaultTextStyle.of(context).style.merge(
          AppTextStyle.messageBody(
            _incomingTextColor,
          ).copyWith(fontSize: _chatFontSize(AppTextSize.messageBody())),
        ),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  /// A rich quote reports its measured height after layout, so a short quote
  /// never builds the affordance and a long one gains it on the next frame.
  void _handleRichQuoteOverflow(String key, bool overflows) {
    if (!mounted) return;
    final changed = overflows
        ? _foldableRichQuotes.add(key)
        : _foldableRichQuotes.remove(key);
    if (changed) _updateState(() {});
  }

  void _toggleRichQuoteExpanded(String key) {
    _updateState(() {
      if (!_expandedQuotes.remove(key)) _expandedQuotes.add(key);
    });
  }

  bool _isRichMediaKind(RichMessageBlockKind kind) =>
      kind == RichMessageBlockKind.photo ||
      kind == RichMessageBlockKind.video ||
      kind == RichMessageBlockKind.animation ||
      kind == RichMessageBlockKind.audio ||
      kind == RichMessageBlockKind.voiceNote;

  ({List<TdFileRef> items, List<int?> indexes}) _richPhotoGallery(
    List<RichMessageBlock> media,
  ) {
    final items = <TdFileRef>[];
    final indexes = <int?>[];
    for (final child in media) {
      final image =
          child.kind == RichMessageBlockKind.photo && !child.hasSpoiler
          ? child.image
          : null;
      if (image == null) {
        indexes.add(null);
        continue;
      }
      indexes.add(items.length);
      items.add(image);
    }
    return (items: List.unmodifiable(items), indexes: indexes);
  }

  ChatMessage _richMediaMessage(RichMessageBlock block) {
    final contentType = switch (block.kind) {
      RichMessageBlockKind.photo => 'messagePhoto',
      RichMessageBlockKind.video => 'messageVideo',
      RichMessageBlockKind.animation => 'messageAnimation',
      RichMessageBlockKind.audio => 'messageAudio',
      RichMessageBlockKind.voiceNote => 'messageVoiceNote',
      _ => 'messageRichMessage',
    };
    return ChatMessage(
      id: message.id,
      chatId: message.chatId,
      isOutgoing: message.isOutgoing,
      text: block.caption.trim().isEmpty ? '' : block.caption,
      date: message.date,
      contentType: contentType,
      image: block.image,
      imageWidth: block.imageWidth,
      imageHeight: block.imageHeight,
      video: block.video,
      videoDuration: block.videoDuration,
      music: block.music,
      voice: block.voice,
    );
  }
}
