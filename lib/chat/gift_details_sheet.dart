//
//  gift_details_sheet.dart
//
//  The read-only sheet a gift card opens: the animated gift over a wash in
//  the gift's colour, the card's title, and a details card with whatever the
//  message says about the gift. It has no actions; Close is its only control.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'details_card.dart';
import 'gift_tint.dart';
import 'message_gift_card.dart';
import 'telegram_rich_text.dart';

/// Opens the gift sheet for [gift]. [incomingToMe] picks the same title the
/// card shows.
Future<void> showGiftDetailsSheet(
  BuildContext context, {
  required MessageGift gift,
  required bool incomingToMe,
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
          MediaQuery.sizeOf(context).height * GiftDetailsSheet.maxHeightFactor,
    ),
    builder: (_) => GiftDetailsSheet(gift: gift, incomingToMe: incomingToMe),
  );
}

class GiftDetailsSheet extends StatelessWidget {
  const GiftDetailsSheet({
    super.key,
    required this.gift,
    required this.incomingToMe,
  });

  final MessageGift gift;
  final bool incomingToMe;

  static const double maxHeightFactor = 0.9;
  static const double _washHeight = 230;
  static const double _washMiddleStop = 0.55;
  static const double _stickerTop = 44;
  static const double _sticker = 120;
  static const double _ring = 156;
  static const double _titleGap = 18;
  static const double _titleSize = 21;
  static const double _titleInset = 32;
  static const double _detailsGap = 24;
  static const double _handleWidth = 36;
  static const double _handleHeight = 5;
  static const double _handleTop = 6;
  static const double _handleAlpha = 0.6;
  static const double _closeSize = 30;
  static const double _closeHitSize = 44;
  static const double _closeTop = 14;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final title = gift.titleKey(incomingToMe).l10n(context);
    final bottomInset = MediaQuery.viewPaddingOf(context).bottom;
    final showsHandle = !appModalUsesCenteredPresentation(
      MediaQuery.sizeOf(context),
    );
    const closeInset = (_closeHitSize - _closeSize) / 2;
    final slot = TdClient.shared.activeSlot;
    final close = Positioned(
      top: _closeTop - closeInset,
      right: AppSpacing.xxl - closeInset,
      child: Semantics(
        container: true,
        sortKey: const OrdinalSortKey(1),
        button: true,
        label: AppStringKeys.musicPlayerClose.l10n(context),
        onTap: () => Navigator.of(context).maybePop(),
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey('giftDetailsClose'),
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
                  color: c.card,
                  shape: BoxShape.circle,
                ),
                child: AppIcon(
                  HeroAppIcons.xmark,
                  size: AppIconSize.md,
                  color: c.textSecondary,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    return GiftTintBuilder(
      gift: gift,
      accountSlot: slot,
      builder: (context, palette, probe) => Stack(
        children: [
          // The close button scrolls with the content so it shares a
          // semantics parent with the title and can follow it in focus order.
          SingleChildScrollView(
            child: Stack(
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: _washHeight,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          palette.washTop,
                          palette.washMiddle,
                          c.groupedBackground,
                        ],
                        stops: const [0, _washMiddleStop, 1],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.only(
                    top: _stickerTop,
                    bottom: AppSpacing.xxl + bottomInset,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      ExcludeSemantics(
                        child: Center(
                          child: SizedBox.square(
                            dimension: _sticker,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                OverflowBox(
                                  minWidth: _ring,
                                  maxWidth: _ring,
                                  minHeight: _ring,
                                  maxHeight: _ring,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: palette.ring,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                                GiftStickerView(
                                  sticker: gift.sticker,
                                  size: _sticker,
                                  glyphColor: palette.ink,
                                  accountSlot: slot,
                                  probe: probe,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: _titleGap),
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: _titleInset,
                        ),
                        child: Semantics(
                          container: true,
                          header: true,
                          sortKey: const OrdinalSortKey(0),
                          child: Text(
                            title,
                            textAlign: TextAlign.center,
                            style: AppTextStyle.title(
                              c.textPrimary,
                              weight: AppTextWeight.semibold,
                            ).copyWith(fontSize: _titleSize),
                          ),
                        ),
                      ),
                      Semantics(
                        container: true,
                        sortKey: const OrdinalSortKey(2),
                        child: _GiftDetails(gift: gift),
                      ),
                    ],
                  ),
                ),
                close,
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
                    color: c.textTertiary.withValues(alpha: _handleAlpha),
                    borderRadius: BorderRadius.circular(_handleHeight / 2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Someone named on the sheet: a user or a chat, resolved from TDLib.
class _GiftParty {
  const _GiftParty(this.name, this.photo);

  final String name;
  final TdFileRef? photo;
}

/// The details card. From and To appear once their names arrive; a row whose
/// data is missing is left out, and with no rows at all the card is too.
class _GiftDetails extends StatefulWidget {
  const _GiftDetails({required this.gift});

  final MessageGift gift;

  @override
  State<_GiftDetails> createState() => _GiftDetailsState();
}

class _GiftDetailsState extends State<_GiftDetails> {
  _GiftParty? _from;
  _GiftParty? _to;

  @override
  void initState() {
    super.initState();
    final gift = widget.gift;
    if (!gift.isSenderHidden) {
      unawaited(
        _resolve(
          userId: gift.senderUserId,
          chatId: gift.senderChatId,
        ).then((party) => _apply(() => _from = party)),
      );
    }
    unawaited(
      _resolve(
        userId: gift.receiverUserId,
        chatId: gift.receiverChatId,
        isMe: gift.receiverIsCurrentUser,
      ).then((party) => _apply(() => _to = party)),
    );
  }

  void _apply(VoidCallback change) {
    if (mounted) setState(change);
  }

  static Future<_GiftParty?> _resolve({
    int? userId,
    int? chatId,
    bool isMe = false,
  }) async {
    try {
      final namesUser = userId != null && userId != 0;
      if (namesUser || (isMe && chatId == null)) {
        final user = await TdClient.shared.query(
          namesUser
              ? {'@type': 'getUser', 'user_id': userId}
              : {'@type': 'getMe'},
        );
        if (user.type != 'user') return null;
        final name = TDParse.userName(user);
        if (name.trim().isEmpty) return null;
        return _GiftParty(name, TDParse.smallPhoto(user.obj('profile_photo')));
      }
      if (chatId != null && chatId != 0) {
        final chat = await TdClient.shared.query({
          '@type': 'getChat',
          'chat_id': chatId,
        });
        if (chat.type != 'chat') return null;
        final name = chat.str('title') ?? '';
        if (name.trim().isEmpty) return null;
        return _GiftParty(name, TDParse.smallPhoto(chat.obj('photo')));
      }
    } catch (_) {
      // An unreachable sender or receiver just leaves its row out.
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final gift = widget.gift;
    final from = _from;
    final to = _to;
    final value = gift.valueText();
    final statuses = gift.statusTexts();
    final rows = <Widget>[
      if (gift.isSenderHidden)
        DetailsRow(
          label: AppStringKeys.giftSheetFrom.l10n(context),
          value: _plainValue(AppStringKeys.giftSheetAnonymous.l10n(context)),
          semanticValue: AppStringKeys.giftSheetAnonymous.l10n(context),
        )
      else if (from != null)
        DetailsRow(
          label: AppStringKeys.giftSheetFrom.l10n(context),
          value: _partyValue(from),
          semanticValue: from.name,
        ),
      if (to != null)
        DetailsRow(
          label: AppStringKeys.giftSheetTo.l10n(context),
          value: _partyValue(to),
          semanticValue: to.name,
        ),
      if (gift.hasNote)
        DetailsRow(
          label: AppStringKeys.giftSheetNote.l10n(context),
          value: (align) => SelectionArea(
            child: TelegramRichText(
              text: gift.note,
              entities: gift.noteEntities,
              style: AppTextStyle.body(context.colors.textPrimary),
              textAlign: align,
            ),
          ),
          semanticValue: gift.note,
        ),
      if (value != null)
        DetailsRow(
          label: AppStringKeys.giftSheetValue.l10n(context),
          value: _plainValue(value),
          semanticValue: value,
        ),
      if (statuses.isNotEmpty)
        DetailsRow(
          label: AppStringKeys.linkHandlerDetailStatus.l10n(context),
          value: _plainValue(statuses.join(' · ')),
          semanticValue: statuses.join(' · '),
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xxl,
        GiftDetailsSheet._detailsGap,
        AppSpacing.xxl,
        0,
      ),
      child: DetailsCard(rows: rows),
    );
  }

  static DetailsRowValue _plainValue(String text) => DetailsRow.textValue(text);

  static DetailsRowValue _partyValue(_GiftParty party) =>
      DetailsRow.partyValue(party.name, party.photo);
}
