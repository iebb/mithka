//
//  gram_transfer_sheet.dart
//
//  The read-only sheet a Gram envelope opens: a curved red header with the
//  seal, who the transfer is from or to, the blessing, the amount and the
//  status; then a details card, and a link to the blockchain explorer once
//  the transaction is known. It only shows; nothing is claimed here.
//

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/gram_amount.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'details_card.dart';
import 'link_handler.dart';
import 'message_gram_envelope.dart';
import 'telegram_rich_text.dart';

/// Opens the detail sheet for [transfer].
///
/// [outgoing] is the transfer's direction; [me] names the current user and
/// [sender] the seal's person when the bubble knows them. [chatPeer] is the
/// other side of a private chat: the recipient of an outgoing transfer until
/// the transaction names one. [onRetry] adds the Retry button to a failed
/// transfer; it is null while sending is not available.
Future<void> showGramTransferSheet(
  BuildContext context, {
  required MessageGramTransfer transfer,
  required GramTransferState state,
  required bool outgoing,
  required int date,
  required GramTransferParty me,
  GramTransferParty? sender,
  GramTransferParty? chatPeer,
  VoidCallback? onRetry,
}) {
  final c = context.colors;
  return showAppModalSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: c.groupedBackground,
    clipBehavior: Clip.antiAlias,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    constraints: BoxConstraints(
      maxHeight:
          MediaQuery.sizeOf(context).height * GramTransferSheet.maxHeightFactor,
    ),
    builder: (_) => GramTransferSheet(
      transfer: transfer,
      state: state,
      outgoing: outgoing,
      date: date,
      me: me,
      sender: sender,
      chatPeer: chatPeer,
      onRetry: onRetry,
    ),
  );
}

class GramTransferSheet extends StatefulWidget {
  const GramTransferSheet({
    super.key,
    required this.transfer,
    required this.state,
    required this.outgoing,
    required this.date,
    required this.me,
    this.sender,
    this.chatPeer,
    this.onRetry,
  });

  final MessageGramTransfer transfer;
  final GramTransferState state;
  final bool outgoing;
  final int date;
  final GramTransferParty me;
  final GramTransferParty? sender;
  final GramTransferParty? chatPeer;
  final VoidCallback? onRetry;

  static const double maxHeightFactor = 0.9;

  @override
  State<GramTransferSheet> createState() => _GramTransferSheetState();
}

class _GramTransferSheetState extends State<GramTransferSheet> {
  static const double _sealTop = 40;
  static const double _seal = 64;
  static const double _titleGap = 12;
  static const double _titleInset = 32;
  static const double _blessingGap = 6;
  static const double _blessingSize = 15;
  static const double _blessingLineHeight = 20;
  static const double _amountGap = 14;
  static const double _amountSize = 36;
  static const double _amountLineHeight = 42;
  static const double _amountPieceGap = 10;
  static const double _amountMaxTextScale = 2;
  static const double _statusGap = 6;
  static const double _statusGlyph = 15;
  static const double _statusGlyphGap = 5;
  static const double _headerBottom = 36;
  static const double _arc = 28;
  static const double _cardGap = 14;
  static const double _retryGap = 16;
  static const double _handleWidth = 36;
  static const double _handleHeight = 5;
  static const double _handleTop = 6;
  static const double _handleAlpha = 0.5;
  static const double _closeSize = 30;
  static const double _closeHitSize = 44;
  static const double _closeTop = 14;
  static const double _closeAlpha = 0.18;
  static const double _copyGlyph = 18;
  static const double _explorerGlyph = 16;
  static const int _addressEnds = 4;
  static const int _transactionStart = 6;
  static const int _transactionEnd = 4;
  static const String _explorerBase = 'https://tonviewer.com/transaction/';

  GramTransferDetails? _details;
  GramTransferParty? _sender;
  bool _senderLooked = false;
  GramTransferParty? _recipient;

  MessageGramTransfer get _transfer => widget.transfer;

  @override
  void initState() {
    super.initState();
    _sender = widget.sender;
    if (_sender == null && _transfer.hasSender) {
      unawaited(
        GramTransferParty.fetch(_transfer.senderUserId).then(
          (party) => _apply(() {
            _sender = party;
            _senderLooked = true;
          }),
        ),
      );
    } else {
      _senderLooked = true;
    }
    if (_transfer.hasTransactionId) unawaited(_loadTransaction());
  }

  void _apply(VoidCallback change) {
    if (mounted) setState(change);
  }

  /// What the transaction adds fills in when it arrives; when it cannot be
  /// read (no wallet access, say) the sheet keeps what the message carries.
  Future<void> _loadTransaction() async {
    GramTransferDetails? details;
    try {
      final result = await TdClient.shared.query({
        '@type': 'getTonWalletTransaction',
        'transaction_id': _transfer.transactionId,
      });
      details = GramTransferDetails.parse(result);
    } catch (_) {
      return;
    }
    if (details == null) return;
    _apply(() => _details = details);
    final peer = details.peerUserId;
    if (widget.outgoing && peer != 0) {
      final party = await GramTransferParty.fetch(peer);
      if (party != null) _apply(() => _recipient = party);
    }
  }

  Future<void> _copy(String value) async {
    unawaited(HapticFeedback.selectionClick());
    var copied = true;
    try {
      await Clipboard.setData(ClipboardData(text: value));
    } catch (_) {
      copied = false;
    }
    if (!mounted) return;
    showToast(
      context,
      AppStrings.t(
        copied
            ? AppStringKeys.profileDetailCopied
            : AppStringKeys.profileDetailCopyFailed,
      ),
    );
  }

  static String _shorten(String value, int start, int end) =>
      value.length <= start + end + 1
      ? value
      : '${value.substring(0, start)}…${value.substring(value.length - end)}';

  String get _shortAddress =>
      _shorten(_transfer.peerAddress, _addressEnds, _addressEnds);

  /// The other side of the transfer, when they are a Telegram user.
  GramTransferParty? get _counterpart =>
      widget.outgoing ? _recipient ?? widget.chatPeer : _sender;

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final showsHandle = !appModalUsesCenteredPresentation(
      MediaQuery.sizeOf(context),
    );
    const closeInset = (_closeHitSize - _closeSize) / 2;
    final rows = _rows(context);
    final hash = _details?.chainHash;
    final retry = widget.state == GramTransferState.failed
        ? widget.onRetry
        : null;

    // White at 18 % over the header, made opaque so the button keeps its
    // look where the details card scrolls under it.
    Widget close(GramEnvelopeColors colors) => Positioned(
      top: _closeTop - closeInset,
      right: AppSpacing.xxl - closeInset,
      child: ScrollPinned(
        child: Semantics(
          container: true,
          sortKey: const OrdinalSortKey(1),
          button: true,
          label: AppStringKeys.musicPlayerClose.l10n(context),
          onTap: () => Navigator.of(context).maybePop(),
          excludeSemantics: true,
          child: GestureDetector(
            key: const ValueKey('gramTransferSheetClose'),
            behavior: HitTestBehavior.opaque,
            onTap: () => Navigator.of(context).maybePop(),
            child: SizedBox.square(
              dimension: _closeHitSize,
              child: Center(
                child: Container(
                  width: _closeSize,
                  height: _closeSize,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Color.alphaBlend(
                      Colors.white.withValues(alpha: _closeAlpha),
                      colors.body,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: const AppIcon(
                    HeroAppIcons.xmark,
                    size: AppIconSize.md,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    return GramEnvelopeColorsBuilder(
      muted: widget.state.isMuted,
      builder: (context, colors) => Stack(
        children: [
          // The close button is laid out with the content so it shares a
          // semantics parent with the title and follows it in focus order;
          // ScrollPinned keeps it in place while the content scrolls under it.
          SingleChildScrollView(
            child: Stack(
              children: [
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _header(context, colors),
                    if (rows.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xxl,
                          _cardGap,
                          AppSpacing.xxl,
                          0,
                        ),
                        child: Semantics(
                          container: true,
                          sortKey: const OrdinalSortKey(2),
                          child: DetailsCard(rows: rows),
                        ),
                      ),
                    if (hash != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xxl,
                          _cardGap,
                          AppSpacing.xxl,
                          0,
                        ),
                        child: Semantics(
                          container: true,
                          sortKey: const OrdinalSortKey(3),
                          child: _explorerCard(context, hash),
                        ),
                      ),
                    if (retry != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(
                          AppSpacing.xxl,
                          _retryGap,
                          AppSpacing.xxl,
                          0,
                        ),
                        child: Semantics(
                          container: true,
                          sortKey: const OrdinalSortKey(4),
                          child: _RetryButton(
                            onPressed: () {
                              Navigator.of(context).maybePop();
                              retry();
                            },
                          ),
                        ),
                      ),
                    SizedBox(height: AppSpacing.xxl + bottomInset),
                  ],
                ),
                close(colors),
              ],
            ),
          ),
          if (showsHandle)
            Positioned(
              top: _handleTop,
              left: 0,
              right: 0,
              child: Center(
                child: Container(
                  width: _handleWidth,
                  height: _handleHeight,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: _handleAlpha),
                    borderRadius: BorderRadius.circular(_handleHeight / 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, GramEnvelopeColors colors) {
    final transfer = _transfer;
    final counterpart = _counterpart;
    final counterpartName =
        counterpart?.name ??
        (transfer.peerAddress.isEmpty ? null : _shortAddress);
    final title = counterpartName == null
        ? AppStringKeys.transferFooterGram.l10n(context)
        : context.l10n.t(
            widget.outgoing
                ? AppStringKeys.transferDetailToValue1
                : AppStringKeys.transferDetailFromValue1,
            {'value1': counterpartName},
          );
    final blessing = gramTransferBlessing(context, transfer);
    const blessingStyle = TextStyle(
      fontSize: _blessingSize,
      height: _blessingLineHeight / _blessingSize,
      fontWeight: AppTextWeight.regular,
      color: AppTheme.envelopeGold,
    );
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
                  size: _blessingSize,
                  color: AppTheme.envelopeGold,
                ),
              ),
            ),
            TextSpan(text: blessing),
          ],
        ),
        style: blessingStyle,
        textAlign: TextAlign.center,
      );
    } else if (transfer.comment.isEmpty) {
      blessingText = Text(
        blessing,
        style: blessingStyle,
        textAlign: TextAlign.center,
      );
    } else {
      blessingText = SelectionArea(
        child: TelegramRichText(
          text: transfer.comment,
          style: blessingStyle,
          linkColor: AppTheme.envelopeGold,
          underlineLinks: true,
          textAlign: TextAlign.center,
        ),
      );
    }

    final (statusGlyph, statusKey) = switch (widget.state) {
      GramTransferState.received => (
        HeroAppIcons.circleCheck,
        AppStringKeys.transferStatusReceived,
      ),
      GramTransferState.sent => (
        HeroAppIcons.circleCheck,
        AppStringKeys.transferStatusSent,
      ),
      GramTransferState.sending => (
        HeroAppIcons.clock,
        AppStringKeys.transferStatusSending,
      ),
      GramTransferState.failed => (
        HeroAppIcons.exclamationCircle,
        AppStringKeys.transferStatusFailed,
      ),
    };

    return CustomPaint(
      painter: _HeaderPainter(color: colors.body, arc: _arc),
      child: Padding(
        padding: const EdgeInsets.only(
          top: _sealTop,
          bottom: _headerBottom + _arc,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ExcludeSemantics(
              child: Center(
                child: GramEnvelopeSeal(
                  size: _seal,
                  colors: colors,
                  hasUser: transfer.hasSender,
                  party: _sender,
                ),
              ),
            ),
            const SizedBox(height: _titleGap),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: _titleInset),
              child: Semantics(
                container: true,
                header: true,
                sortKey: const OrdinalSortKey(0),
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: AppTextStyle.title(
                    Colors.white,
                    weight: AppTextWeight.semibold,
                  ),
                ),
              ),
            ),
            Semantics(
              container: true,
              sortKey: const OrdinalSortKey(0.5),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: _titleInset),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: _blessingGap),
                    blessingText,
                    const SizedBox(height: _amountGap),
                    // The number and the unit stay whole and only wrap between
                    // each other; the scale is capped so "GRAM" fits a phone
                    // width at the largest accessibility size.
                    Wrap(
                      alignment: WrapAlignment.center,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: _amountPieceGap,
                      children: [
                        for (final piece in transfer.formattedAmount().split(
                          ' ',
                        ))
                          Text(
                            piece,
                            textAlign: TextAlign.center,
                            textScaler: MediaQuery.textScalerOf(
                              context,
                            ).clamp(maxScaleFactor: _amountMaxTextScale),
                            style: AppTextStyle.display(AppTheme.envelopeGold)
                                .copyWith(
                                  fontSize: _amountSize,
                                  height: _amountLineHeight / _amountSize,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                          ),
                      ],
                    ),
                    const SizedBox(height: _statusGap),
                    Text.rich(
                      TextSpan(
                        children: [
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsetsDirectional.only(
                                end: _statusGlyphGap,
                              ),
                              child: AppIcon(
                                statusGlyph,
                                size: _statusGlyph,
                                color: Colors.white,
                              ),
                            ),
                          ),
                          TextSpan(text: statusKey.l10n(context)),
                        ],
                      ),
                      textAlign: TextAlign.center,
                      style: AppTextStyle.callout(AppTheme.envelopeInk2),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _rows(BuildContext context) {
    final transfer = _transfer;
    final details = _details;
    final c = context.colors;
    final tabular = AppTextStyle.body(
      c.textPrimary,
    ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    final copyGlyph = AppIcon(
      HeroAppIcons.documentDuplicate,
      size: _copyGlyph,
      color: c.textTertiary,
    );

    /// A Telegram user, or the wallet address when there is none.
    Widget? partyRow(String label, GramTransferParty? party, bool settled) {
      if (party != null) {
        return DetailsRow(
          label: label,
          value: DetailsRow.partyValue(
            party.name,
            party.photo,
            avatarTitle: party.avatarTitle,
          ),
          semanticValue: party.name,
        );
      }
      if (!settled || transfer.peerAddress.isEmpty) return null;
      final address = _shortAddress;
      return DetailsRow(
        label: label,
        value: DetailsRow.textValue(address, style: tabular),
        semanticValue: address,
        trailing: copyGlyph,
        onTap: () => unawaited(_copy(transfer.peerAddress)),
      );
    }

    final from = widget.outgoing
        ? partyRow(
            AppStringKeys.transferSheetFrom.l10n(context),
            widget.me,
            true,
          )
        : partyRow(
            AppStringKeys.transferSheetFrom.l10n(context),
            _sender,
            _senderLooked,
          );
    final to = widget.outgoing
        ? partyRow(
            AppStringKeys.transferSheetTo.l10n(context),
            _counterpart,
            true,
          )
        : partyRow(
            AppStringKeys.transferSheetTo.l10n(context),
            widget.me,
            true,
          );
    final unix = widget.date > 0 ? widget.date : details?.date ?? 0;
    final date = DateText.fullLabel(unix);
    final String? fee = !widget.outgoing || details == null
        ? null
        : details.isGasless
        ? AppStringKeys.transferNetworkFeeFree.l10n(context)
        : details.feeAmount == null
        ? null
        : GramAmount.format(details.feeAmount!);
    final settled =
        widget.state == GramTransferState.received ||
        widget.state == GramTransferState.sent;
    final transactionId = settled && transfer.hasTransactionId
        ? _shorten(transfer.transactionId, _transactionStart, _transactionEnd)
        : null;
    return [
      ?from,
      ?to,
      if (date.isNotEmpty)
        DetailsRow(
          label: AppStringKeys.transferSheetDate.l10n(context),
          value: DetailsRow.textValue(date, style: tabular),
          semanticValue: date,
        ),
      if (fee != null)
        DetailsRow(
          label: AppStringKeys.transferNetworkFee.l10n(context),
          value: DetailsRow.textValue(fee),
          semanticValue: fee,
        ),
      if (transactionId != null)
        DetailsRow(
          label: AppStringKeys.transferSheetTransactionId.l10n(context),
          value: DetailsRow.textValue(transactionId, style: tabular),
          semanticValue: transactionId,
          trailing: copyGlyph,
          onTap: () => unawaited(_copy(transfer.transactionId)),
        ),
    ];
  }

  Widget _explorerCard(BuildContext context, String hash) {
    final c = context.colors;
    final label = AppStringKeys.transferSheetViewInExplorer.l10n(context);
    void open() => unawaited(openLink(context, '$_explorerBase$hash'));
    return Semantics(
      container: true,
      button: true,
      link: true,
      label: label,
      onTap: open,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: open,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.card),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xxl,
              vertical: 13,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(label, style: AppTextStyle.body(c.linkBlue)),
                ),
                const SizedBox(width: AppSpacing.md),
                AppIcon(
                  HeroAppIcons.arrowTopRight,
                  size: _explorerGlyph,
                  color: c.linkBlue,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The header's fill: a rectangle down to [arc] above the bottom, closed by a
/// curve whose lowest point is the bottom edge.
class _HeaderPainter extends CustomPainter {
  const _HeaderPainter({required this.color, required this.arc});

  final Color color;
  final double arc;

  @override
  void paint(Canvas canvas, Size size) {
    final width = size.width;
    final edge = size.height - arc;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(width, 0)
      ..lineTo(width, edge)
      ..quadraticBezierTo(width / 2, size.height + arc, 0, edge)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_HeaderPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.arc != arc;
}

/// The red pill that sends a failed transfer again.
class _RetryButton extends StatefulWidget {
  const _RetryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  State<_RetryButton> createState() => _RetryButtonState();
}

class _RetryButtonState extends State<_RetryButton> {
  static const double _height = 50;
  static const double _pressedAlpha = 0.10;

  bool _pressed = false;

  void _setPressed(bool pressed) {
    if (_pressed != pressed) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final label = AppStringKeys.callsRetry.l10n(context);
    return Semantics(
      container: true,
      button: true,
      label: label,
      onTap: widget.onPressed,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: _height),
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              color: Colors.black.withValues(
                alpha: _pressed ? _pressedAlpha : 0,
              ),
              borderRadius: BorderRadius.circular(_height / 2),
            ),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppTheme.envelopeRed,
                borderRadius: BorderRadius.circular(_height / 2),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.xxl,
                  vertical: AppSpacing.md,
                ),
                child: Center(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: AppTextStyle.title(
                      Colors.white,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
