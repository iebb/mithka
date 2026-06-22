//
//  message_bubble.dart
//
//  One conversation message, reference-styled. Plain rounded bubbles (no tail).
//  Renders text (with highlighted links), inline images (tap → full-screen
//  viewer), stickers (.tgs Lottie), voice notes, location cards, and document
//  cards. Shows a "+1" quick-repeat badge for a duplicate tail. Swipe a bubble
//  left to reply. Port of the Swift `MessageBubble`.
//

import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../components/photo_avatar.dart';
import '../components/sf_symbols.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'animated_sticker_view.dart';
import 'custom_emoji.dart';
import 'video_sticker_view.dart';
import 'file_opener.dart';
import 'link_handler.dart';
import 'voice_audio.dart';

class MessageBubble extends StatefulWidget {
  const MessageBubble({
    super.key,
    required this.message,
    required this.peerTitle,
    this.peerPhoto,
    required this.isGroup,
    this.meName = '我',
    this.mePhoto,
    this.showRepeat = false,
    this.onRepeat,
    this.onLongPress,
    this.onReply,
    this.onAvatarTap,
    this.onAvatarLongPress,
    this.onOpenImage,
    this.onToggleReaction,
    this.isRead = false,
  });

  final ChatMessage message;
  final String peerTitle;
  final TdFileRef? peerPhoto;
  final bool isGroup;
  final String meName;
  final TdFileRef? mePhoto;
  final bool showRepeat;
  final VoidCallback? onRepeat;
  final void Function(ChatMessage message, Rect? bounds)? onLongPress;
  final ValueChanged<ChatMessage>? onReply;
  final ValueChanged<ChatMessage>? onAvatarTap;
  final ValueChanged<ChatMessage>? onAvatarLongPress;
  final ValueChanged<ChatMessage>? onOpenImage;
  final ValueChanged<MessageReaction>? onToggleReaction;
  final bool isRead; // outgoing message read by the peer (✓✓)

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  final VoicePlayer _voice = VoicePlayer();
  final GlobalKey _bubbleKey = GlobalKey();
  final List<TapGestureRecognizer> _linkRecognizers = [];
  bool _stickerReady = false;
  bool _videoStickerReady = false;
  double _swipeX = 0;

  void _handleLongPress() {
    final box = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    Rect? bounds;
    if (box != null && box.hasSize) {
      bounds = box.localToGlobal(Offset.zero) & box.size;
    }
    widget.onLongPress?.call(message, bounds);
  }

  ChatMessage get message => widget.message;

  @override
  void dispose() {
    _voice.dispose();
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (message.isService) return const SizedBox.shrink();
    return Stack(
      alignment: Alignment.centerRight,
      children: [
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: Opacity(
            opacity: (math.min(1, math.max(0, -_swipeX) / 50)).toDouble(),
            child: Icon(
              sfIcon('arrowshape.turn.up.left.fill'),
              size: 18,
              color: AppTheme.brand,
            ),
          ),
        ),
        Transform.translate(
          offset: Offset(_swipeX, 0),
          child: _row(message.isOutgoing),
        ),
      ],
    );
  }

  void _onDragUpdate(DragUpdateDetails d) {
    setState(() => _swipeX = math.max(math.min(_swipeX + d.delta.dx, 0), -72));
  }

  void _onDragEnd(DragEndDetails d) {
    if (_swipeX < -52) widget.onReply?.call(message);
    setState(() => _swipeX = 0);
  }

  Widget _row(bool outgoing) {
    final c = context.colors;
    final body = GestureDetector(
      key: _bubbleKey,
      onLongPress: _handleLongPress,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: _contentBody(outgoing),
    );
    final content = message.reactions.isEmpty
        ? body
        : Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: outgoing
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            children: [
              body,
              const SizedBox(height: 4),
              _reactionChips(outgoing),
            ],
          );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: outgoing
            ? [
                const SizedBox(width: 48),
                Expanded(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      if (widget.showRepeat) _repeatBadge(),
                      if (widget.showRepeat) const SizedBox(width: 6),
                      Flexible(child: content),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                PhotoAvatar(
                  title: widget.meName,
                  photo: widget.mePhoto,
                  size: 38,
                ),
              ]
            : [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onAvatarTap?.call(message),
                  onLongPress: () => widget.onAvatarLongPress?.call(message),
                  child: PhotoAvatar(
                    title: widget.isGroup
                        ? (message.senderName ?? widget.peerTitle)
                        : widget.peerTitle,
                    photo: widget.isGroup
                        ? message.senderPhoto
                        : widget.peerPhoto,
                    size: 38,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (widget.isGroup && message.senderName != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 3),
                          child: Row(
                            children: [
                              if (message.senderRole != null) ...[
                                RoleTag(
                                  role: message.senderRole!,
                                  title: message.senderTitle,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  message.senderName!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: c.textSecondary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Flexible(child: content),
                          if (widget.showRepeat) const SizedBox(width: 6),
                          if (widget.showRepeat) _repeatBadge(),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 48),
              ],
      ),
    );
  }

  Widget _reactionChips(bool outgoing) {
    final c = context.colors;
    return Wrap(
      spacing: 5,
      runSpacing: 5,
      alignment: outgoing ? WrapAlignment.end : WrapAlignment.start,
      children: [
        for (final r in message.reactions)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onToggleReaction?.call(r),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: r.chosen
                    ? AppTheme.brand.withValues(alpha: 0.18)
                    : c.searchFill,
                borderRadius: BorderRadius.circular(12),
                border: r.chosen
                    ? Border.all(color: AppTheme.brand, width: 1)
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  r.customEmojiId != 0
                      ? CustomEmojiView(
                          id: r.customEmojiId,
                          size: 16,
                          color: r.chosen ? AppTheme.brand : c.textSecondary,
                        )
                      : Text(
                          r.emoji ?? '',
                          style: const TextStyle(fontSize: 14),
                        ),
                  if (r.count > 1) ...[
                    const SizedBox(width: 4),
                    Text(
                      '${r.count}',
                      style: TextStyle(
                        fontSize: 12,
                        color: r.chosen ? AppTheme.brand : c.textSecondary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _repeatBadge() => GestureDetector(
    onTap: widget.onRepeat,
    child: Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: AppTheme.brand, width: 1.2),
      ),
      child: Text(
        '+1',
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: AppTheme.brand,
        ),
      ),
    ),
  );

  // MARK: - Content router

  Widget _contentBody(bool outgoing) {
    if (message.animatedSticker != null) {
      final s = _stickerSize();
      return SizedBox(
        width: s.width,
        height: s.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (message.image != null && !_stickerReady)
              TDImage(photo: message.image, cornerRadius: 8),
            AnimatedStickerView(
              file: message.animatedSticker!,
              onReady: () => setState(() => _stickerReady = true),
            ),
          ],
        ),
      );
    }
    if (message.videoSticker != null) {
      final s = _stickerSize();
      return SizedBox(
        width: s.width,
        height: s.height,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (message.image != null && !_videoStickerReady)
              TDImage(photo: message.image, cornerRadius: 8),
            VideoStickerView(
              file: message.videoSticker!,
              onReady: () => setState(() => _videoStickerReady = true),
            ),
          ],
        ),
      );
    }
    if (message.image != null) return _imageContent(message.image!, outgoing);
    if (message.location != null) return _locationBubble(message.location!);
    if (message.voice != null) return _voiceBubble(message.voice!, outgoing);
    if (message.document != null) return _fileCard(message.document!);
    return _textBubble(message.text, outgoing);
  }

  // MARK: - Text bubble

  Widget _textBubble(String text, bool outgoing) {
    final c = context.colors;
    final baseColor = outgoing
        ? AppTheme.bubbleOutgoingText
        : c.bubbleIncomingText;
    final linkColor = outgoing ? Colors.white : c.linkBlue;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: outgoing ? AppTheme.bubbleOutgoing : c.bubbleIncoming,
        borderRadius: BorderRadius.circular(6),
        border: outgoing ? null : Border.all(color: c.divider, width: 0.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if ((message.forwardOrigin ?? '').isNotEmpty) ...[
            _forwardHeader(outgoing),
            const SizedBox(height: 3),
          ],
          if (message.replyToPreview != null) ...[
            _replyQuote(outgoing),
            const SizedBox(height: 5),
          ],
          RichText(
            text: TextSpan(
              style: TextStyle(fontSize: 16, color: baseColor),
              children: [
                ..._emojiSpans(text, baseColor, linkColor),
                if (widget.message.isEdited || outgoing) _metaSpan(outgoing),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 转发 attribution shown above forwarded content: `转发自 …`.
  Widget _forwardHeader(bool outgoing) {
    final c = context.colors;
    final accent = outgoing ? Colors.white : AppTheme.brand;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          sfIcon('arrowshape.turn.up.right.fill'),
          size: 11,
          color: accent.withValues(alpha: 0.9),
        ),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '转发自 ${message.forwardOrigin}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: outgoing ? Colors.white : c.textSecondary,
            ),
          ),
        ),
      ],
    );
  }

  /// 引用 quote block shown above a reply's text: accent bar + sender + preview.
  Widget _replyQuote(bool outgoing) {
    final c = context.colors;
    final accent = outgoing ? Colors.white : AppTheme.brand;
    final faded = outgoing ? Colors.white70 : c.textSecondary;
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
      decoration: BoxDecoration(
        color: (outgoing ? Colors.white : AppTheme.brand).withValues(
          alpha: 0.12,
        ),
        borderRadius: BorderRadius.circular(4),
        border: Border(left: BorderSide(color: accent, width: 2.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message.replyToSender ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: accent,
            ),
          ),
          Text(
            message.replyToPreview ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: faded),
          ),
        ],
      ),
    );
  }

  static final _urlRegExp = RegExp(
    r'((https?:\/\/|www\.|t\.me\/|tg:\/\/)[^\s]+)',
    caseSensitive: false,
  );

  /// Trailing inline meta after the text: 已编辑 tag + read tick (✓ / ✓✓).
  InlineSpan _metaSpan(bool outgoing) {
    final faint = outgoing
        ? Colors.white.withValues(alpha: 0.65)
        : context.colors.textTertiary;
    return WidgetSpan(
      alignment: PlaceholderAlignment.bottom,
      child: Padding(
        padding: const EdgeInsets.only(left: 6, top: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.message.isEdited)
              Text('已编辑', style: TextStyle(fontSize: 10, color: faint)),
            if (widget.message.isEdited && outgoing) const SizedBox(width: 4),
            if (outgoing)
              Icon(
                widget.isRead ? Icons.done_all : Icons.done,
                size: 13,
                color: widget.isRead ? Colors.white : faint,
              ),
          ],
        ),
      ),
    );
  }

  /// Interleaves inline custom-emoji widgets (at their UTF-16 entity ranges)
  /// with link-highlighted plain text segments.
  List<InlineSpan> _emojiSpans(String text, Color base, Color link) {
    // Recycle tap recognizers from the previous build before making new ones.
    for (final r in _linkRecognizers) {
      r.dispose();
    }
    _linkRecognizers.clear();
    final emojis = message.customEmoji;
    if (emojis.isEmpty) return _linkSpans(text, base, link);
    final sorted = [...emojis]..sort((a, b) => a.offset.compareTo(b.offset));
    final spans = <InlineSpan>[];
    var cursor = 0;
    for (final e in sorted) {
      final start = e.offset.clamp(0, text.length);
      final end = (e.offset + e.length).clamp(0, text.length);
      if (start < cursor || end <= start) continue;
      if (start > cursor) {
        spans.addAll(_linkSpans(text.substring(cursor, start), base, link));
      }
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 0.5),
            child: CustomEmojiView(id: e.id, size: 20, color: base),
          ),
        ),
      );
      cursor = end;
    }
    if (cursor < text.length) {
      spans.addAll(_linkSpans(text.substring(cursor), base, link));
    }
    return spans;
  }

  List<InlineSpan> _linkSpans(String text, Color base, Color link) {
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _urlRegExp.allMatches(text)) {
      if (m.start > last) {
        spans.add(TextSpan(text: text.substring(last, m.start)));
      }
      final url = text.substring(m.start, m.end);
      final recognizer = TapGestureRecognizer()
        ..onTap = () => openLink(context, url);
      _linkRecognizers.add(recognizer);
      spans.add(
        TextSpan(
          text: url,
          style: TextStyle(color: link, decoration: TextDecoration.underline),
          recognizer: recognizer,
        ),
      );
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));
    return spans;
  }

  // MARK: - Image

  Widget _imageContent(TdFileRef image, bool outgoing) {
    final size = _imageDisplaySize();
    final caption = _caption();
    return Column(
      crossAxisAlignment: outgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        GestureDetector(
          onTap: () => widget.onOpenImage?.call(message),
          child: SizedBox(
            width: size.width,
            height: size.height,
            child: TDImage(photo: image, cornerRadius: 10),
          ),
        ),
        if (caption != null) ...[
          const SizedBox(height: 4),
          _textBubble(caption, outgoing),
        ],
      ],
    );
  }

  String? _caption() {
    final t = message.text;
    if (t.isEmpty) return null;
    if (t.startsWith('[') && t.endsWith(']')) return null;
    return t;
  }

  Size _imageDisplaySize() {
    const maxW = 240.0, maxH = 280.0;
    final w = message.imageWidth, h = message.imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) {
      return const Size(200, 200);
    }
    final aspect = w / h;
    var dw = maxW;
    var dh = dw / aspect;
    if (dh > maxH) {
      dh = maxH;
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

  // MARK: - Voice

  Widget _voiceBubble(MessageVoice voice, bool outgoing) {
    final c = context.colors;
    final fg = outgoing ? Colors.white : AppTheme.brand;
    final track = outgoing
        ? Colors.white.withValues(alpha: 0.35)
        : AppTheme.brand.withValues(alpha: 0.25);
    return AnimatedBuilder(
      animation: _voice,
      builder: (context, _) {
        final total = _voice.total.inMilliseconds > 0
            ? _voice.total
            : Duration(seconds: voice.duration);
        final frac = total.inMilliseconds > 0
            ? (_voice.position.inMilliseconds / total.inMilliseconds).clamp(
                0.0,
                1.0,
              )
            : 0.0;
        final played = _voice.isPlaying || _voice.position > Duration.zero;
        final timeText = played
            ? _durationString(_voice.position.inSeconds)
            : _durationString(voice.duration);
        return Container(
          width: 210,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: outgoing ? AppTheme.bubbleOutgoing : c.bubbleIncoming,
            borderRadius: BorderRadius.circular(6),
            border: outgoing ? null : Border.all(color: c.divider, width: 0.5),
          ),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => _voice.toggle(voice.file),
                child: Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: outgoing
                        ? Colors.white.withValues(alpha: 0.25)
                        : AppTheme.brand.withValues(alpha: 0.12),
                  ),
                  child: _voice.isLoading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation(fg),
                          ),
                        )
                      : Icon(
                          sfIcon(_voice.isPlaying ? 'pause.fill' : 'play.fill'),
                          size: 14,
                          color: fg,
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: LayoutBuilder(
                  builder: (ctx, box) {
                    final w = box.maxWidth;
                    void seekAt(double dx) =>
                        _voice.seekFraction(dx / w, voice.duration);
                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapDown: (d) => seekAt(d.localPosition.dx),
                      onHorizontalDragStart: (d) => seekAt(d.localPosition.dx),
                      onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
                      child: SizedBox(
                        height: 22,
                        child: Stack(
                          alignment: Alignment.centerLeft,
                          children: [
                            Container(
                              height: 3,
                              decoration: BoxDecoration(
                                color: track,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            FractionallySizedBox(
                              widthFactor: frac,
                              child: Container(
                                height: 3,
                                decoration: BoxDecoration(
                                  color: fg,
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                            Align(
                              alignment: Alignment(frac * 2 - 1, 0),
                              child: Container(
                                width: 11,
                                height: 11,
                                decoration: BoxDecoration(
                                  color: fg,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                timeText,
                style: TextStyle(
                  fontSize: 12,
                  color: outgoing
                      ? Colors.white.withValues(alpha: 0.9)
                      : c.textSecondary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _durationString(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  // MARK: - Location

  Widget _locationBubble(MessageLocation location) {
    final c = context.colors;
    return Container(
      width: 220,
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: c.divider, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (location.title?.isNotEmpty ?? false)
                      ? location.title!
                      : '位置',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: c.bubbleIncomingText,
                  ),
                ),
                if (location.address?.isNotEmpty ?? false) ...[
                  const SizedBox(height: 3),
                  Text(
                    location.address!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          _MapThumbnail(
            latitude: location.latitude,
            longitude: location.longitude,
          ),
        ],
      ),
    );
  }

  // MARK: - File card

  Widget _fileCard(MessageDocument doc) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => openDocument(context, doc),
      child: Container(
        width: 244,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    doc.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.bubbleIncomingText),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _byteString(doc.size),
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            _fileGlyph(doc.ext),
          ],
        ),
      ),
    );
  }

  Widget _fileGlyph(String ext) {
    return SizedBox(
      width: 44,
      height: 48,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          Icon(sfIcon('doc.fill'), size: 40, color: _fileColor(ext)),
          Positioned(
            bottom: 8,
            child: Text(
              _fileBadge(ext),
              style: const TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
          ),
          Positioned(
            right: -2,
            bottom: 2,
            child: Container(
              width: 20,
              height: 20,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand,
                shape: BoxShape.circle,
                border: Border.all(color: c.card, width: 1.5),
              ),
              child: const Icon(
                Icons.arrow_downward,
                size: 11,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  AppColors get c => context.colors;

  static String _byteString(int bytes) {
    if (bytes < 1024) return '$bytes B';
    const units = ['KB', 'MB', 'GB', 'TB'];
    var size = bytes / 1024;
    var i = 0;
    while (size >= 1024 && i < units.length - 1) {
      size /= 1024;
      i++;
    }
    return '${size.toStringAsFixed(size >= 100 ? 0 : 1)} ${units[i]}';
  }

  static Color _fileColor(String ext) {
    switch (ext) {
      case 'DOC':
      case 'DOCX':
        return const Color(0xFF2B7CD3);
      case 'XLS':
      case 'XLSX':
      case 'CSV':
        return const Color(0xFF21A366);
      case 'PPT':
      case 'PPTX':
        return const Color(0xFFD24726);
      case 'PDF':
        return const Color(0xFFE2453C);
      case 'ZIP':
      case 'RAR':
      case '7Z':
        return const Color(0xFFF4A100);
      default:
        return AppColors.light.textTertiary;
    }
  }

  static String _fileBadge(String ext) {
    switch (ext) {
      case 'DOC':
      case 'DOCX':
        return 'W';
      case 'XLS':
      case 'XLSX':
        return 'X';
      case 'PPT':
      case 'PPTX':
        return 'P';
      case '':
        return 'FILE';
      default:
        return ext.length > 4 ? ext.substring(0, 4) : ext;
    }
  }
}

/// Static map preview for a location message. Telegram renders the map tile via
/// getMapThumbnailFile (no marker); we overlay a centre pin.
class _MapThumbnail extends StatefulWidget {
  const _MapThumbnail({required this.latitude, required this.longitude});
  final double latitude;
  final double longitude;

  @override
  State<_MapThumbnail> createState() => _MapThumbnailState();
}

class _MapThumbnailState extends State<_MapThumbnail> {
  TdFileRef? _ref;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final res = await TdClient.shared.query({
        '@type': 'getMapThumbnailFile',
        'location': {
          '@type': 'location',
          'latitude': widget.latitude,
          'longitude': widget.longitude,
        },
        'zoom': 16,
        'width': 220,
        'height': 120,
        'scale': 2,
        'chat_id': 0,
      });
      final id = res.integer('id');
      if (mounted && id != null) setState(() => _ref = TdFileRef(id: id));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SizedBox(
      height: 120,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_ref != null)
            TDImage(photo: _ref, cornerRadius: 0)
          else
            Container(color: c.groupedBackground),
          Center(
            child: Icon(
              sfIcon('mappin.and.ellipse'),
              size: 32,
              color: AppTheme.brand,
            ),
          ),
        ],
      ),
    );
  }
}
