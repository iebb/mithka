//
//  message_gram_envelope.dart
//
//  A compact Gram transfer card in the transcript. The amount leads, with the
//  actual comment and status beside a transfer symbol. The detail sheet keeps
//  its shared envelope colours and avatar seal below.
//

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../l10n/gram_amount.dart';
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

/// The blessing's text: the comment as written, or the encrypted-message
/// label; null when there is no comment.
String? gramTransferBlessing(BuildContext context, MessageGramTransfer t) =>
    t.isCommentEncrypted
    ? AppStringKeys.transferEncryptedComment.l10n(context)
    : t.comment.isEmpty
    ? null
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

/// The chat card's theme palette. The envelope detail sheet keeps its own
/// colours; these tokens also let the bubble colour the footer delivery mark.
class GramTransferCardColors {
  GramTransferCardColors.of(BuildContext context) {
    final c = context.colors;
    body = _whiteContrastSurface(AppTheme.brand);
    final hsl = HSLColor.fromColor(body);
    mutedBody = _whiteContrastSurface(
      hsl.withSaturation(hsl.saturation * 0.35).toColor(),
    );
    footer = Color.alphaBlend(AppTheme.brand.withValues(alpha: 0.12), c.card);
    footerInk = contrastRatio(c.textSecondary, footer) >= 4.5
        ? c.textSecondary
        : c.textPrimary;
    final read = Theme.of(context).brightness == Brightness.dark
        ? AppTheme.readMark
        : AppTheme.readMarkOnLightCard;
    var adjustedRead = read;
    for (
      var step = 1;
      contrastRatio(adjustedRead, footer) < 3 && step <= 10;
      step++
    ) {
      adjustedRead = Color.lerp(read, c.textPrimary, step / 10)!;
    }
    readInk = adjustedRead;
  }

  late final Color body;
  late final Color mutedBody;
  late final Color footer;
  late final Color footerInk;
  late final Color readInk;

  /// Preserve the chosen hue/saturation and the exact brand where white is
  /// already readable. Otherwise find the lightest accessible shade.
  static Color _whiteContrastSurface(Color color) {
    final opaque = color.withValues(alpha: 1);
    if (contrastRatio(Colors.white, opaque) >= 4.5) return opaque;
    final hsl = HSLColor.fromColor(opaque);
    var lower = 0.0;
    var upper = hsl.lightness;
    for (var step = 0; step < 14; step++) {
      final middle = (lower + upper) / 2;
      // A little luminance headroom keeps rounded channels above 4.5:1.
      if (hsl.withLightness(middle).toColor().computeLuminance() <= 0.18) {
        lower = middle;
      } else {
        upper = middle;
      }
    }
    return hsl.withLightness(lower).toColor();
  }
}

/// The in-chat transfer card. It draws its own surface instead of the bubble's
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

  /// The sender passed through by existing callers for detail-sheet routing.
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
  static const double _width = 240;
  static const double _maxScaledWidth = 300;
  static const double _bodyMinHeight = 78;
  static const double _amountSize = 22;
  static const double _amountLineHeight = 27;
  static const double _amountMaxScale = 2;
  static const double _symbolSize = 40;
  static const double _symbolMaxScale = 1.25;
  static const double _symbolGap = 10;
  static const double _sideInset = 12;
  static const double _verticalInset = 14;
  static const double _commentGap = 4;
  static const double _commentLineHeight = 19;
  static const int _commentMaxLines = 3;
  static const double _statusGap = 6;
  static const double _statusLineHeight = 17;
  static const double _lockGlyph = 13;
  static const double _pressedAlpha = 0.10;

  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final palette = GramTransferCardColors.of(context);
    final transfer = widget.transfer;
    final state = widget.state;
    final scaler = MediaQuery.textScalerOf(context);
    final scale = math.max(1.0, scaler.scale(_amountSize) / _amountSize);
    final amountScaler = scaler.clamp(maxScaleFactor: _amountMaxScale);
    final width = math.min(
      math.min(_width * scale, _maxScaledWidth),
      widget.maxWidth,
    );
    final symbolScale = math.min(scale, _symbolMaxScale);
    final symbolSize = _symbolSize * symbolScale;
    final radius = widget.borderRadius ?? BorderRadius.circular(9);
    final retries = state == GramTransferState.failed && widget.onRetry != null;
    final onTap = retries ? widget.onRetry : widget.onTap;
    final footerWord = AppStringKeys.transferFooterGram.l10n(context);
    final amount = transfer.formattedAmount();
    final number = GramAmount.formatNumber(transfer.amount.abs());
    final comment = transfer.isCommentEncrypted
        ? AppStringKeys.transferEncryptedComment.l10n(context)
        : transfer.comment;
    final status = switch (state) {
      GramTransferState.received => AppStringKeys.transferStatusReceived,
      GramTransferState.sent => AppStringKeys.transferStatusSent,
      GramTransferState.sending => AppStringKeys.transferStatusSending,
      GramTransferState.failed =>
        retries
            ? AppStringKeys.transferStatusFailedRetry
            : AppStringKeys.transferStatusFailed,
    }.l10n(context);

    Widget card(Color bodyColor, Color ink) {
      final amountStyle = AppTextStyle.display(ink).copyWith(
        fontSize: _amountSize,
        height: _amountLineHeight / _amountSize,
        fontFeatures: const [FontFeature.tabularFigures()],
      );
      final commentStyle = AppTextStyle.callout(
        ink,
      ).copyWith(height: _commentLineHeight / AppTextSize.callout);
      final Widget commentText;
      if (transfer.isCommentEncrypted) {
        commentText = Text.rich(
          TextSpan(
            children: [
              WidgetSpan(
                alignment: PlaceholderAlignment.middle,
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: AppIcon(
                    HeroAppIcons.lock,
                    // Text.rich scales inline widgets with the comment.
                    size: _lockGlyph,
                    color: ink,
                  ),
                ),
              ),
              TextSpan(text: comment),
            ],
          ),
          style: commentStyle,
          maxLines: _commentMaxLines,
          overflow: TextOverflow.ellipsis,
        );
      } else {
        // The whole card opens the detail sheet, including links in a comment.
        commentText = IgnorePointer(
          child: TelegramRichText(
            text: comment,
            style: commentStyle,
            linkColor: ink,
            underlineLinks: true,
            maxLines: _commentMaxLines,
            overflow: TextOverflow.ellipsis,
          ),
        );
      }

      final symbol = ExcludeSemantics(
        child: Container(
          width: symbolSize,
          height: symbolSize,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ink, width: 1.5),
          ),
          child: Center(
            child: AppIcon(
              state == GramTransferState.failed
                  ? HeroAppIcons.exclamationCircle
                  : HeroAppIcons.arrowsRightLeft,
              size: 22 * symbolScale,
              color: ink,
            ),
          ),
        ),
      );
      final body = DecoratedBox(
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: _pressed ? _pressedAlpha : 0),
        ),
        child: ColoredBox(
          color: bodyColor,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: _bodyMinHeight),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: _sideInset,
                vertical: _verticalInset,
              ),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Keep the number whole beside the symbol whenever it fits.
                  // A long amount gets the full width before digit groups wrap.
                  final measurementStyle =
                      AppTextStyle.forSystemBoldTextMeasurement(
                        DefaultTextStyle.of(context).style.merge(amountStyle),
                        boldText: MediaQuery.boldTextOf(context),
                      );
                  final painter = TextPainter(
                    text: TextSpan(text: number, style: measurementStyle),
                    textScaler: amountScaler,
                    textDirection: Directionality.of(context),
                  )..layout();
                  final stacked =
                      painter.width >
                      constraints.maxWidth - symbolSize - _symbolGap;
                  painter.dispose();
                  final content = Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _GramCardAmount(
                        amount: amount,
                        number: number,
                        style: amountStyle,
                        scaler: amountScaler,
                      ),
                      if (comment.isNotEmpty) ...[
                        const SizedBox(height: _commentGap),
                        commentText,
                      ],
                      const SizedBox(height: _statusGap),
                      Text(
                        status,
                        style: AppTextStyle.footnote(ink).copyWith(
                          height: _statusLineHeight / AppTextSize.footnote,
                        ),
                      ),
                    ],
                  );
                  if (stacked) {
                    return Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        symbol,
                        const SizedBox(height: _symbolGap),
                        content,
                      ],
                    );
                  }
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      symbol,
                      const SizedBox(width: _symbolGap),
                      Expanded(child: content),
                    ],
                  );
                },
              ),
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
                backgroundColor: palette.footer,
                labelColor: palette.footerInk,
              ),
            ],
          ),
        ),
      );
    }

    return Semantics(
      container: true,
      button: true,
      label: [
        footerWord,
        amount,
        if (comment.isNotEmpty) comment,
        status,
      ].join(', '),
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
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: state.isMuted ? 1 : 0),
          duration: AppMotion.duration(context, AppMotion.responsive),
          curve: AppMotion.standard,
          builder: (context, muted, _) {
            return card(
              Color.lerp(palette.body, palette.mutedBody, muted)!,
              Colors.white,
            );
          },
        ),
      ),
    );
  }
}

/// The formatter is shared with the sheet. Number and unit are separate runs,
/// so GRAM always stays whole even at the largest supported amount scale.
class _GramCardAmount extends StatelessWidget {
  const _GramCardAmount({
    required this.amount,
    required this.number,
    required this.style,
    required this.scaler,
  });

  final String amount;
  final String number;
  final TextStyle style;
  final TextScaler scaler;

  @override
  Widget build(BuildContext context) {
    final numberStart = amount.indexOf(number);
    final prefix = amount.substring(0, numberStart).trim();
    final suffix = amount.substring(numberStart + number.length).trim();
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(
            text: number,
            style: AppTextStyle.forSystemBoldTextMeasurement(
              DefaultTextStyle.of(context).style.merge(style),
              boldText: MediaQuery.boldTextOf(context),
            ),
          ),
          textScaler: scaler,
          textDirection: Directionality.of(context),
        )..layout();
        final wrapGroups = painter.width > constraints.maxWidth;
        painter.dispose();
        // Only expose breaks between locale-formatted digit groups after the
        // number has been given the body's full width. Never split GRAM.
        final displayedNumber = wrapGroups
            ? number.replaceAllMapped(
                RegExp(r'([^0-9]+)(?=[0-9])'),
                (match) => '${match[0]}\u200b',
              )
            : number;
        return Wrap(
          spacing: scaler.scale(5),
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (prefix.isNotEmpty)
              Text(prefix, style: style, textScaler: scaler),
            Text(displayedNumber, style: style, textScaler: scaler),
            if (suffix.isNotEmpty)
              Text(suffix, style: style, textScaler: scaler),
          ],
        );
      },
    );
  }
}
