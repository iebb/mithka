//
//  message_gift_card.dart
//
//  A gift message in the transcript: one compact card in the sender's spot.
//  A tinted body carries the title, an optional second line and the whole
//  animated gift sticker over a decorative circle; a footer strip below it
//  names the card a gift and holds the message's delivery mark.
//

import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'animated_sticker_view.dart';
import 'gift_tint.dart';
import 'telegram_rich_text.dart';
import 'video_sticker_view.dart';

/// The in-chat gift card. It draws its own surface instead of the bubble's
/// and stays the same in Standard and Simple mode.
///
/// The whole card is one button: [onTap] opens the gift, while a long press
/// falls through to the message's own menu.
class MessageGiftCard extends StatefulWidget {
  const MessageGiftCard({
    super.key,
    required this.gift,
    required this.incomingToMe,
    required this.maxWidth,
    this.borderRadius,
    this.meta,
    this.onTap,
  });

  final MessageGift gift;

  /// Picks the "…Received" title over the "…Sent" one; see
  /// [MessageGift.isIncomingToMe].
  final bool incomingToMe;

  /// The bubble's maximum width. The card is narrower than its usual 240 only
  /// when this is.
  final double maxWidth;
  final BorderRadius? borderRadius;

  /// The message's delivery tick or edited mark, at the footer's trailing
  /// end; null when the message shows none.
  final Widget? meta;
  final VoidCallback? onTap;

  @override
  State<MessageGiftCard> createState() => _MessageGiftCardState();
}

class _MessageGiftCardState extends State<MessageGiftCard> {
  static const double _width = 240;
  static const double _maxScaledWidth = 300;
  static const double _sticker = 64;
  static const double _maxStickerScale = 1.25;
  static const double _ringToSticker = 1.625;
  static const double _footerHeight = 24;
  static const double _titleLineHeight = 22;
  static const double _secondLineHeight = 19;
  static const int _secondLineMaxLines = 3;
  static const double _pressedOverlayAlpha = 0.06;

  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final gift = widget.gift;
    final scaler = MediaQuery.textScalerOf(context);
    final scale = math.max(
      1.0,
      scaler.scale(AppTextSize.title) / AppTextSize.title,
    );
    final width = math.min(
      math.min(_width * scale, _maxScaledWidth),
      widget.maxWidth,
    );
    final stickerSize = _sticker * math.min(scale, _maxStickerScale);
    final ringSize = stickerSize * _ringToSticker;
    final title = gift.titleKey(widget.incomingToMe).l10n(context);
    final secondLine = gift.secondLine();
    final footerWord = AppStringKeys.linkHandlerDetailGift.l10n(context);
    // The sticker players and avatars read the active account too.
    final slot = TdClient.shared.activeSlot;
    final radius =
        widget.borderRadius ?? BorderRadius.circular(AppRadius.control);

    Widget card(GiftPalette palette, GiftFrameProbe? probe) {
      final secondStyle = AppTextStyle.callout(
        palette.ink2,
      ).copyWith(height: _secondLineHeight / AppTextSize.callout);
      final body = DecoratedBox(
        decoration: BoxDecoration(
          // Left to right: the default begin and end.
          gradient: LinearGradient(
            colors: [palette.bodyStart, palette.bodyEnd],
          ),
        ),
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              right: AppSpacing.md + (stickerSize - ringSize) / 2,
              width: ringSize,
              child: OverflowBox(
                minWidth: ringSize,
                maxWidth: ringSize,
                minHeight: ringSize,
                maxHeight: ringSize,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.ring,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ),
            ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: stickerSize + AppSpacing.lg * 2,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.lg,
                  AppSpacing.md + stickerSize + AppSpacing.md,
                  AppSpacing.lg,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: AppTextStyle.title(
                        palette.ink,
                        weight: AppTextWeight.regular,
                      ).copyWith(height: _titleLineHeight / AppTextSize.title),
                    ),
                    if (secondLine != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      if (secondLine.isNote)
                        TelegramRichText(
                          text: secondLine.text,
                          entities: secondLine.entities,
                          style: secondStyle,
                          linkColor: palette.ink,
                          underlineLinks: true,
                          maxLines: _secondLineMaxLines,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        Text(
                          secondLine.text,
                          style: secondStyle,
                          maxLines: _secondLineMaxLines,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ],
                ),
              ),
            ),
            Positioned(
              top: 0,
              bottom: 0,
              right: AppSpacing.md,
              width: stickerSize,
              child: Center(
                child: GiftStickerView(
                  sticker: gift.sticker,
                  size: stickerSize,
                  glyphColor: palette.ink,
                  accountSlot: slot,
                  probe: probe,
                ),
              ),
            ),
          ],
        ),
      );
      final footer = ColoredBox(
        color: c.card,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: _footerHeight * scale),
          child: Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.lg,
              right: AppSpacing.md,
            ),
            child: Row(
              children: [
                AppIcon(
                  HeroAppIcons.gift,
                  size: scaler.scale(AppIconSize.sm),
                  color: c.textSecondary,
                ),
                const SizedBox(width: AppSpacing.xs),
                Expanded(
                  child: Text(
                    footerWord,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption(c.textSecondary),
                  ),
                ),
                ?widget.meta,
              ],
            ),
          ),
        ),
      );
      return SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: radius,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              color: _pressed
                  ? c.textPrimary.withValues(alpha: _pressedOverlayAlpha)
                  : c.textPrimary.withValues(alpha: 0),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [body, footer],
            ),
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      button: true,
      label: [title, ?secondLine?.text, footerWord].join(', '),
      hint: AppStringKeys.giftCardHint.l10n(context),
      onTap: widget.onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('messageGiftCard'),
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: widget.onTap == null ? null : (_) => _setPressed(true),
        onTapUp: widget.onTap == null ? null : (_) => _setPressed(false),
        onTapCancel: widget.onTap == null ? null : () => _setPressed(false),
        child: GiftTintBuilder(
          gift: gift,
          accountSlot: slot,
          builder: (context, palette, probe) => card(palette, probe),
        ),
      ),
    );
  }
}

/// A gift's whole sticker, contained in a [size] square and never cropped.
///
/// TGS and WebM stickers play through the regular sticker players and loop;
/// under Reduce Motion a TGS holds its first frame and a WebM shows its still.
/// Until the player has a frame the static thumbnail stands in, and without
/// one the gift glyph in [glyphColor] does, so the slot is never empty.
///
/// With a [probe], one rendered frame is handed to it once the player is
/// ready: the colour source for a gift with no static thumbnail.
class GiftStickerView extends StatefulWidget {
  const GiftStickerView({
    super.key,
    required this.sticker,
    required this.size,
    required this.glyphColor,
    required this.accountSlot,
    this.probe,
  });

  final MessageGiftSticker? sticker;
  final double size;
  final Color glyphColor;
  final int accountSlot;
  final GiftFrameProbe? probe;

  @override
  State<GiftStickerView> createState() => _GiftStickerViewState();
}

class _GiftStickerViewState extends State<GiftStickerView> {
  /// The glyph is 40pt in a 64pt slot.
  static const double _glyphRatio = 40 / 64;

  /// The probe reads a frame about this many pixels across; the colour
  /// extractor averages it down to 32 × 32 anyway.
  static const double _probeSide = 64;

  /// Lottie can need a few frames after it reports ready before anything is
  /// painted; a frame with no opaque pixel is retried this many times.
  static const int _maxProbeAttempts = 10;

  final GlobalKey _frameKey = GlobalKey();
  bool _playerReady = false;
  bool _probing = false;
  int _probeAttempts = 0;

  int? get _playerFileId =>
      widget.sticker?.animated?.id ?? widget.sticker?.video?.id;

  @override
  void didUpdateWidget(GiftStickerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldId =
        oldWidget.sticker?.animated?.id ?? oldWidget.sticker?.video?.id;
    if (oldId != _playerFileId) {
      _playerReady = false;
      _probing = false;
    } else if (oldWidget.probe == null && widget.probe != null) {
      _startProbe();
    }
  }

  void _handlePlayerReady() {
    if (!mounted) return;
    if (!_playerReady) setState(() => _playerReady = true);
    _startProbe();
  }

  void _startProbe() {
    if (widget.probe == null || _probing || !_playerReady) return;
    _probing = true;
    _probeAttempts = 0;
    _probeAfterNextFrame();
  }

  void _probeAfterNextFrame() {
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => unawaited(_captureFrame()),
    );
    WidgetsBinding.instance.scheduleFrame();
  }

  Future<void> _captureFrame() async {
    final boundary = _frameKey.currentContext?.findRenderObject();
    if (!mounted ||
        widget.probe == null ||
        boundary is! RenderRepaintBoundary ||
        !boundary.hasSize ||
        boundary.size.isEmpty) {
      _probing = false;
      return;
    }
    ui.Image? frame;
    try {
      frame = await boundary.toImage(
        pixelRatio: _probeSide / boundary.size.longestSide,
      );
      final data = await frame.toByteData(
        format: ui.ImageByteFormat.rawStraightRgba,
      );
      if (data != null && _hasOpaquePixel(data)) {
        final probe = widget.probe;
        if (mounted && probe != null) {
          probe(
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            frame.width,
            frame.height,
          );
        }
        _probing = false;
        return;
      }
    } catch (_) {
      // Not painted yet, or a platform texture the engine cannot read back;
      // the next frame is tried, and after that the theme colour stays.
    } finally {
      frame?.dispose();
    }
    if (mounted && ++_probeAttempts < _maxProbeAttempts) {
      _probeAfterNextFrame();
    } else {
      _probing = false;
    }
  }

  static bool _hasOpaquePixel(ByteData data) {
    for (var offset = 3; offset < data.lengthInBytes; offset += 4) {
      if (data.getUint8(offset) >= 128) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;
    final glyph = Center(
      child: AppIcon(
        HeroAppIcons.gift,
        size: size * _glyphRatio,
        color: widget.glyphColor,
      ),
    );
    final sticker = widget.sticker;
    if (sticker == null) return SizedBox.square(dimension: size, child: glyph);
    final animate = !AppMotion.isReduced(context);
    final animated = sticker.animated;
    final video = sticker.video;
    final Widget? player = animated != null
        ? AnimatedStickerView(
            file: animated,
            animate: animate,
            onReady: _handlePlayerReady,
          )
        : video != null && animate
        ? VideoStickerView(
            file: video,
            fallback: sticker.hasStaticThumbnail ? sticker.thumbnail : null,
            onReady: _handlePlayerReady,
          )
        : null;
    final still = sticker.hasStaticThumbnail
        ? sticker.thumbnail
        : sticker.isAnimated
        ? null
        : sticker.image;
    return SizedBox.square(
      dimension: size,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (player == null || !_playerReady)
            still == null
                ? glyph
                : _GiftStill(
                    file: still,
                    accountSlot: widget.accountSlot,
                    size: size,
                    placeholder: glyph,
                  ),
          // Hidden until it has a frame: before that the video player paints
          // its own loading surface over the still.
          if (player != null)
            Opacity(
              opacity: _playerReady ? 1 : 0,
              child: RepaintBoundary(key: _frameKey, child: player),
            ),
        ],
      ),
    );
  }
}

/// A static sticker image, contained; [placeholder] until it has decoded or
/// when it cannot be read.
class _GiftStill extends StatefulWidget {
  const _GiftStill({
    required this.file,
    required this.accountSlot,
    required this.size,
    required this.placeholder,
  });

  final TdFileRef file;
  final int accountSlot;
  final double size;
  final Widget placeholder;

  @override
  State<_GiftStill> createState() => _GiftStillState();
}

class _GiftStillState extends State<_GiftStill> {
  File? _file;
  int? _loadedId;
  int? _loadedSlot;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_GiftStill oldWidget) {
    super.didUpdateWidget(oldWidget);
    _load();
  }

  void _load() {
    final ref = widget.file;
    final slot = widget.accountSlot;
    if (_loadedId == ref.id && _loadedSlot == slot) return;
    _loadedId = ref.id;
    _loadedSlot = slot;
    _file = null;
    unawaited(
      TdFileCenter.shared.pathFor(ref, accountSlot: slot).then((path) {
        if (!mounted || path == null) return;
        if (_loadedId != ref.id || _loadedSlot != slot) return;
        setState(() => _file = File(path));
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    if (file == null) return widget.placeholder;
    return Image.file(
      file,
      fit: BoxFit.contain,
      cacheWidth: (widget.size * MediaQuery.devicePixelRatioOf(context))
          .round(),
      gaplessPlayback: true,
      frameBuilder: (context, child, frame, synchronous) =>
          frame == null && !synchronous ? widget.placeholder : child,
      errorBuilder: (context, _, _) => widget.placeholder,
    );
  }
}
