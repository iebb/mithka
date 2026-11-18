part of 'message_bubble.dart';

extension _MessageBubbleMediaCards on _MessageBubbleState {
  // MARK: - Image

  int _cachePx(double logical) =>
      (logical * MediaQuery.devicePixelRatioOf(context)).ceil();

  bool _groupsMediaCaption(String? caption) =>
      caption != null && _theme.groupImageMessages;

  /// Width of a bubble that groups media with its caption. Like Telegram
  /// (Desktop `Photo::countCurrentSize`, the mobile clients' blurred side
  /// fill), the caption and attribution headers widen the bubble beyond a
  /// narrow or small preview, up to the media box, instead of being squeezed
  /// into the preview's width.
  double _groupedMediaWidth(double mediaWidth, String caption) {
    final maxWidth = _mediaMaxWidth();
    if (mediaWidth >= maxWidth) return mediaWidth;
    final direction = Directionality.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String text, TextStyle style) {
      final painter = TextPainter(
        text: TextSpan(text: text, style: style),
        textDirection: direction,
        textScaler: scaler,
        textWidthBasis: TextWidthBasis.longestLine,
      )..layout(maxWidth: maxWidth);
      final width = painter.width;
      painter.dispose();
      return width;
    }

    final replacesOriginal = _translationReplacesOriginalFor(message);
    final entities = replacesOriginal
        ? message.translationEntities
        : _activeTextEntities;
    final spaced = _displaySpacing(
      replacesOriginal ? message.translationText ?? '' : caption,
      entities,
    );
    final bodyStyle = DefaultTextStyle.of(context).style.merge(
      AppTextStyle.messageBody(_incomingTextColor).copyWith(
        fontSize: _chatFontSize(AppTextSize.messageBody()),
        // Measure bold runs at their wider weight so they never wrap a word.
        fontWeight: spaced.entities.any((e) => e.type == 'textEntityTypeBold')
            ? FontWeight.bold
            : null,
      ),
    );
    // Caption padding is 6 on each side; headers are padded 10.
    var width = math.max(mediaWidth, measure(spaced.text, bodyStyle) + 12);
    const headerStyle = TextStyle(fontSize: 12, fontWeight: FontWeight.w500);
    if (message.hasForwardAttribution) {
      final label = AppStrings.t(AppStringKeys.messageBubbleForwardedFrom, {
        'value1': message.forwardDisplayName,
      });
      // The 11 pt forward glyph and its 4 pt gap lead the label.
      width = math.max(width, measure(label, headerStyle) + 15 + 20);
    }
    if (message.hasViaBotAttribution) {
      final label = AppStrings.t(AppStringKeys.messageBubbleViaBot, {
        'value1': message.viaBotDisplayName,
      });
      width = math.max(width, measure(label, headerStyle) + 20);
    }
    return math.min(maxWidth, width.ceilToDouble());
  }

  /// Pads grouped video or animation [media] of [size] out to the grouped
  /// bubble width; separate media keeps its own width.
  ({Widget media, double width}) _groupedVideoFrame(
    Widget media,
    Size size,
    String? caption,
    BorderRadius borderRadius,
  ) {
    if (!_groupsMediaCaption(caption)) return (media: media, width: size.width);
    final width = _groupedMediaWidth(size.width, caption!);
    if (width <= size.width + 0.5) return (media: media, width: size.width);
    return (
      media: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => widget.bubble.onPlayVideo?.call(message),
        child: SizedBox(
          width: width,
          height: size.height,
          child: _letterboxFrame(
            fillSource: message.image?.thumbnail ?? message.image,
            childSize: size,
            borderRadius: borderRadius,
            child: media,
          ),
        ),
      ),
      width: width,
    );
  }

  String? _caption() {
    final text = _activeMessageText;
    return text.trim().isEmpty ? null : text;
  }

  Size _imageDisplaySize() {
    return _imagePreviewGeometry().frameSize;
  }

  MediaPreviewGeometry _imagePreviewGeometry() {
    return telegramDesktopMediaPreviewGeometry(
      sourceWidth: message.imageWidth,
      sourceHeight: message.imageHeight,
      availableWidth: _mediaMaxWidth(),
      maxHeight: telegramChatMediaPreviewMaxHeight,
    );
  }

  /// The height budget a rich block's media shares with ordinary chat media:
  /// the 320 pixel box, and never taller than a narrow pane is wide.
  double _richMediaMaxHeight(double maxWidth) =>
      math.min(maxWidth, telegramChatMediaPreviewMaxHeight);

  Size _fitSize({
    required int? width,
    required int? height,
    required double maxWidth,
    required double maxHeight,
    required Size fallback,
  }) {
    final w = width, h = height;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return fallback;
    }
    final aspect = w / h;
    var dw = maxWidth;
    var dh = dw / aspect;
    if (dh > maxHeight) {
      dh = maxHeight;
      dw = dh * aspect;
    }
    return Size(dw, dh);
  }

  Size _stickerSize() {
    const maxSide = 120.0;
    final w = message.imageWidth, h = message.imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return const Size(maxSide, maxSide);
    }
    final aspect = w / h;
    return aspect >= 1
        ? Size(maxSide, maxSide / aspect)
        : Size(maxSide * aspect, maxSide);
  }

  void _handleGroupedFileLongPress(ChatMessage source, GlobalKey itemKey) {
    if (_claimDesktopTouchLongPress(source, MessageActionSource.normal)) return;
    final box = itemKey.currentContext?.findRenderObject() as RenderBox?;
    final bounds = box != null && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
    widget.bubble.onLongPress?.call(source, bounds, MessageActionSource.normal);
  }

  void _handleGroupedFileSecondaryTap(
    ChatMessage source,
    Offset globalPosition,
  ) {
    _markDesktopSecondaryHandled();
    widget.bubble.onLongPress?.call(
      source,
      Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 0, 0),
      MessageActionSource.normal,
    );
  }

  bool _isGifDocument(MessageDocument document) =>
      document.ext.toLowerCase() == 'gif' ||
      document.fileName.toLowerCase().endsWith('.gif');

  String _fileCaptionText(ChatMessage source) {
    final text = source.text;
    return text.trim().isEmpty ? '' : text;
  }
}
