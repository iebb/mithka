//
//  message_gram_envelope.dart
//
//  A Gram transfer in the transcript: a portrait red envelope in the sender's
//  spot. A lighter flap with a curved edge carries a gold seal holding the
//  sender's avatar; the comment sits in gold as the blessing, one status line
//  closes the body, and the shared footer strip names it a Gram transfer.
//  The amount is never on the envelope: the detail sheet shows it.
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../tdlib/td_user_index.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'message_card_footer.dart';
import 'telegram_rich_text.dart';

/// Someone on either side of a transfer, as the seal and the sheet name them.
class GramTransferParty {
  const GramTransferParty({required this.name, this.photo, String? avatarTitle})
    : avatarTitle = avatarTitle ?? name;

  /// The name the sheet shows.
  final String name;
  final TdFileRef? photo;

  /// Picks the avatar's initials and colour.
  final String avatarTitle;

  /// [userId] from the active account's user cache, when it is there.
  static GramTransferParty? cached(int userId) {
    if (userId == 0) return null;
    final user = TdUserIndex.shared.userFor(TdClient.shared.activeSlot, userId);
    return user == null ? null : _fromUser(user);
  }

  /// [userId] from the cache, or from TDLib; null when it cannot be read.
  static Future<GramTransferParty?> fetch(int userId) async {
    if (userId == 0) return null;
    final known = cached(userId);
    if (known != null) return known;
    try {
      final user = await TdClient.shared.query({
        '@type': 'getUser',
        'user_id': userId,
      });
      return _fromUser(user);
    } catch (_) {
      // An unreachable user keeps the seal's empty ring.
      return null;
    }
  }

  static GramTransferParty? _fromUser(Map<String, dynamic> user) {
    if (user.type != 'user') return null;
    final name = TDParse.userName(user);
    if (name.trim().isEmpty) return null;
    return GramTransferParty(
      name: name,
      photo: TDParse.smallPhoto(user.obj('profile_photo')),
    );
  }
}

/// The blessing's text: the comment as written, the default blessing when
/// there is none, or the encrypted-message label.
String gramTransferBlessing(BuildContext context, MessageGramTransfer t) =>
    t.isCommentEncrypted
    ? AppStringKeys.transferEncryptedComment.l10n(context)
    : t.comment.isEmpty
    ? AppStringKeys.transferDefaultBlessing.l10n(context)
    : t.comment;

/// The envelope's colours between red (0) and muted (1), so a sending
/// envelope can cross-fade to sent.
class GramEnvelopeColors {
  const GramEnvelopeColors(this.muted);

  /// 0 for red, 1 for muted.
  final double muted;

  static const double _mutedSaturation = 0.35;

  Color get body =>
      Color.lerp(AppTheme.envelopeRed, AppTheme.envelopeMuted, muted)!;
  Color get flap =>
      Color.lerp(AppTheme.envelopeFlap, AppTheme.envelopeMutedFlap, muted)!;
  Gradient get seal => LinearGradient.lerp(
    AppTheme.envelopeSeal,
    AppTheme.envelopeMutedSeal,
    muted,
  )!;

  /// The avatar's saturation: full on red, 35 % on muted.
  double get avatarSaturation => 1 - (1 - _mutedSaturation) * muted;
}

/// Runs [builder] with the colours for [muted], cross-fading over the motion
/// token's duration when it changes (instantly under Reduce Motion).
class GramEnvelopeColorsBuilder extends StatelessWidget {
  const GramEnvelopeColorsBuilder({
    super.key,
    required this.muted,
    required this.builder,
  });

  final bool muted;
  final Widget Function(BuildContext context, GramEnvelopeColors colors)
  builder;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: muted ? 1 : 0),
      duration: AppMotion.duration(context, AppMotion.responsive),
      curve: AppMotion.standard,
      builder: (context, value, _) =>
          builder(context, GramEnvelopeColors(value)),
    );
  }
}

/// The gold seal: [party]'s avatar inside a 3pt gold ring. Without a
/// Telegram sender ([hasUser] false) the inner circle is red with the
/// transfer glyph; while the sender is still being looked up it is empty.
class GramEnvelopeSeal extends StatelessWidget {
  const GramEnvelopeSeal({
    super.key,
    required this.size,
    required this.colors,
    required this.hasUser,
    this.party,
  });

  final double size;
  final GramEnvelopeColors colors;
  final bool hasUser;
  final GramTransferParty? party;

  static const double _ring = 3;
  static const double _glyphRatio = 0.5;
  static const double _shadowAlpha = 0.25;
  static const double _shadowBlur = 2;
  static const double _shadowOffset = 1;

  /// A saturation matrix over Rec. 709 luminance.
  static List<double> _saturation(double s) {
    const r = 0.2126, g = 0.7152, b = 0.0722;
    final i = 1 - s;
    return [
      r * i + s, g * i, b * i, 0, 0, //
      r * i, g * i + s, b * i, 0, 0, //
      r * i, g * i, b * i + s, 0, 0, //
      0, 0, 0, 1, 0, //
    ];
  }

  @override
  Widget build(BuildContext context) {
    final inner = size - _ring * 2;
    final party = this.party;
    Widget content;
    if (hasUser && party != null) {
      content = PhotoAvatar(
        title: party.avatarTitle,
        photo: party.photo,
        size: inner,
      );
      final saturation = colors.avatarSaturation;
      if (saturation < 1) {
        content = ColorFiltered(
          colorFilter: ColorFilter.matrix(_saturation(saturation)),
          child: content,
        );
      }
    } else {
      content = DecoratedBox(
        decoration: BoxDecoration(color: colors.body, shape: BoxShape.circle),
        child: hasUser
            ? const SizedBox.expand()
            : Center(
                child: AppIcon(
                  HeroAppIcons.arrowsRightLeft,
                  size: size * _glyphRatio,
                  color: AppTheme.envelopeGold,
                ),
              ),
      );
    }
    return Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(_ring),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: colors.seal,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: _shadowAlpha),
            blurRadius: _shadowBlur,
            offset: const Offset(0, _shadowOffset),
          ),
        ],
      ),
      child: SizedBox.square(dimension: inner, child: content),
    );
  }
}

/// The in-chat envelope. It draws its own surface instead of the bubble's
/// and is the same in Standard and Simple mode.
///
/// The whole card is one button: [onTap] opens the detail sheet, except for
/// a failed transfer with an [onRetry], where the tap retries. A long press
/// falls through to the message's own menu.
class MessageGramEnvelope extends StatefulWidget {
  const MessageGramEnvelope({
    super.key,
    required this.transfer,
    required this.state,
    required this.maxWidth,
    this.sender,
    this.borderRadius,
    this.meta,
    this.onTap,
    this.onRetry,
  });

  final MessageGramTransfer transfer;
  final GramTransferState state;

  /// The bubble's maximum width; the envelope is narrower than its usual
  /// width only when this is.
  final double maxWidth;

  /// The seal's person when the bubble already knows them; otherwise it is
  /// looked up from [MessageGramTransfer.senderUserId].
  final GramTransferParty? sender;
  final BorderRadius? borderRadius;

  /// The message's delivery mark at the footer's end; null for none.
  final Widget? meta;
  final VoidCallback? onTap;

  /// Sends a failed transfer again. Null while sending is not available.
  final VoidCallback? onRetry;

  @override
  State<MessageGramEnvelope> createState() => _MessageGramEnvelopeState();
}

class _MessageGramEnvelopeState extends State<MessageGramEnvelope> {
  static const double _width = 180;
  static const double _maxScaledWidth = 240;
  static const double _bodyMinHeight = 184;
  static const double _flapDepth = 30;
  static const double _flapCurve = 16;
  static const double _seal = 40;
  static const double _maxSealScale = 1.25;
  static const double _sealGap = 12;
  static const double _sideInset = 14;
  static const double _bottomInset = 12;
  static const double _statusGap = 12;
  static const double _blessingLineHeight = 21;
  static const double _statusLineHeight = 17;
  static const int _blessingMaxLines = 3;
  static const double _lockGlyph = 15;
  static const double _failedGlyph = 14;
  static const double _pressedAlpha = 0.10;

  bool _pressed = false;
  GramTransferParty? _fetched;
  int? _fetchedFor;

  @override
  void initState() {
    super.initState();
    _resolveSender();
  }

  @override
  void didUpdateWidget(MessageGramEnvelope oldWidget) {
    super.didUpdateWidget(oldWidget);
    _resolveSender();
  }

  /// Looks the sender up when the bubble could not name them.
  void _resolveSender() {
    final userId = widget.transfer.senderUserId;
    if (widget.sender != null || userId == 0 || _fetchedFor == userId) return;
    _fetchedFor = userId;
    _fetched = GramTransferParty.cached(userId);
    if (_fetched != null) return;
    unawaited(
      GramTransferParty.fetch(userId).then((party) {
        if (!mounted || _fetchedFor != userId || party == null) return;
        setState(() => _fetched = party);
      }),
    );
  }

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final transfer = widget.transfer;
    final state = widget.state;
    final scaler = MediaQuery.textScalerOf(context);
    final scale = math.max(
      1.0,
      scaler.scale(AppTextSize.bodyLarge) / AppTextSize.bodyLarge,
    );
    final width = math.min(
      math.min(_width * scale, _maxScaledWidth),
      widget.maxWidth,
    );
    final sealScale = math.min(scale, _maxSealScale);
    final flapDepth = _flapDepth * sealScale;
    final flapCurve = _flapCurve * sealScale;
    final sealSize = _seal * sealScale;
    final sealCentre = flapDepth + flapCurve;
    final radius =
        widget.borderRadius ?? BorderRadius.circular(AppRadius.control);
    final retries = state == GramTransferState.failed && widget.onRetry != null;
    final onTap = retries ? widget.onRetry : widget.onTap;

    final footerWord = AppStringKeys.transferFooterGram.l10n(context);
    final blessing = gramTransferBlessing(context, transfer);
    final status = switch (state) {
      GramTransferState.received => AppStringKeys.transferStatusReceived,
      GramTransferState.sent => AppStringKeys.transferStatusSent,
      GramTransferState.sending => AppStringKeys.transferStatusSending,
      GramTransferState.failed =>
        retries
            ? AppStringKeys.transferStatusFailedRetry
            : AppStringKeys.transferStatusFailed,
    }.l10n(context);

    final blessingStyle = AppTextStyle.bodyLarge(
      AppTheme.envelopeGold,
      weight: AppTextWeight.medium,
    ).copyWith(height: _blessingLineHeight / AppTextSize.bodyLarge);
    final Widget blessingText;
    if (transfer.isCommentEncrypted) {
      blessingText = Text.rich(
        TextSpan(
          children: [
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: AppSpacing.xs),
                child: AppIcon(
                  HeroAppIcons.lock,
                  size: _lockGlyph,
                  color: AppTheme.envelopeGold,
                ),
              ),
            ),
            TextSpan(text: blessing),
          ],
        ),
        style: blessingStyle,
        textAlign: TextAlign.center,
        maxLines: _blessingMaxLines,
        overflow: TextOverflow.ellipsis,
      );
    } else if (transfer.comment.isEmpty) {
      blessingText = Text(
        blessing,
        style: blessingStyle,
        textAlign: TextAlign.center,
        maxLines: _blessingMaxLines,
        overflow: TextOverflow.ellipsis,
      );
    } else {
      // The card is one button, so a link in the comment opens nothing here;
      // the sheet's blessing is the one to tap or select.
      blessingText = IgnorePointer(
        child: TelegramRichText(
          text: transfer.comment,
          style: blessingStyle,
          linkColor: AppTheme.envelopeGold,
          underlineLinks: true,
          textAlign: TextAlign.center,
          maxLines: _blessingMaxLines,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    final failed = state == GramTransferState.failed;
    final statusStyle = AppTextStyle.footnote(
      failed ? Colors.white : AppTheme.envelopeInk2,
    ).copyWith(height: _statusLineHeight / AppTextSize.footnote);
    final statusText = Text.rich(
      TextSpan(
        children: [
          if (failed)
            const WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: Padding(
                padding: EdgeInsetsDirectional.only(end: AppSpacing.xs),
                child: AppIcon(
                  HeroAppIcons.exclamationCircle,
                  size: _failedGlyph,
                  color: Colors.white,
                ),
              ),
            ),
          TextSpan(text: status),
        ],
      ),
      style: statusStyle,
      textAlign: TextAlign.center,
    );

    final party = widget.sender ?? _fetched;
    Widget card(GramEnvelopeColors colors) {
      final body = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: _pressed ? _pressedAlpha : 0),
        ),
        child: ColoredBox(
          color: colors.body,
          child: CustomPaint(
            painter: _EnvelopeFlapPainter(
              color: colors.flap,
              depth: flapDepth,
              curve: flapCurve,
            ),
            child: Stack(
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight:
                        _bodyMinHeight *
                        math.min(scale, _maxScaledWidth / _width),
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      _sideInset,
                      sealCentre + sealSize / 2 + _sealGap,
                      _sideInset,
                      _bottomInset,
                    ),
                    // With min size under the body's minimum height, the
                    // spare height goes evenly above and below the blessing:
                    // it sits centred between the seal and the status line.
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox.shrink(),
                        blessingText,
                        Padding(
                          padding: const EdgeInsets.only(top: _statusGap),
                          child: statusText,
                        ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  top: sealCentre - sealSize / 2,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: GramEnvelopeSeal(
                      size: sealSize,
                      colors: colors,
                      hasUser: transfer.hasSender,
                      party: party,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return SizedBox(
        width: width,
        child: ClipRRect(
          borderRadius: radius,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              body,
              MessageCardFooter(
                label: footerWord,
                scale: scale,
                meta: widget.meta,
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      button: true,
      label: [footerWord, blessing, status].join(', '),
      hint: retries
          ? AppStringKeys.transferStatusFailedRetry.l10n(context)
          : AppStringKeys.transferCardHint.l10n(context),
      onTap: onTap,
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('messageGramEnvelope'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onTapDown: onTap == null ? null : (_) => _setPressed(true),
        onTapUp: onTap == null ? null : (_) => _setPressed(false),
        onTapCancel: onTap == null ? null : () => _setPressed(false),
        child: GramEnvelopeColorsBuilder(
          muted: state.isMuted,
          builder: (context, colors) => card(colors),
        ),
      ),
    );
  }
}

/// The flap across the envelope's top: straight down [depth] at both sides,
/// then a curve whose lowest point, [depth] + [curve], is where the seal
/// sits.
class _EnvelopeFlapPainter extends CustomPainter {
  const _EnvelopeFlapPainter({
    required this.color,
    required this.depth,
    required this.curve,
  });

  final Color color;
  final double depth;
  final double curve;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(width, 0)
      ..lineTo(width, depth)
      ..quadraticBezierTo(width / 2, depth + curve * 2, 0, depth)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_EnvelopeFlapPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.depth != depth ||
      oldDelegate.curve != curve;
}
