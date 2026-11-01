//
//  message_gift.dart
//
//  The gift carried by a Telegram gift message (regular, upgraded, refunded,
//  purchase offer, Premium, Stars, Gram), parsed by `TDParse.giftAttachment`,
//  plus the pure copy rules the gift card and gift sheet render with.
//

import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/gram_amount.dart';

import 'td_models.dart';

/// The TDLib message content a [MessageGift] was parsed from.
enum MessageGiftKind {
  /// `messageGift`: a regular gift.
  regular,

  /// `messageUpgradedGift`: an upgraded (collectible) gift.
  upgraded,

  /// `messageRefundedGift`. The pinned TDLib schema has no such type; it is
  /// accepted so a newer TDLib cannot fall through to a plain text bubble.
  refunded,

  /// `messageRefundedUpgradedGift`: a refunded purchase, upgrade or transfer.
  /// TDLib carries the regular `gift` here, not the upgraded one.
  refundedUpgraded,

  /// `messageUpgradedGiftPurchaseOffer`.
  purchaseOffer,

  /// `messageUpgradedGiftPurchaseOfferRejected`: declined or expired.
  purchaseOfferRejected,

  /// `messageGiftedPremium`.
  premium,

  /// `messagePremiumGiftCode`.
  premiumCode,

  /// `messageGiftedStars`.
  stars,

  /// `messageGiveawayPrizeStars`.
  giveawayStars,

  /// `messageGiftedGrams` (TDLib's current name), or the older
  /// `messageGiftedTon`.
  gram,
}

/// TDLib `UpgradedGiftOrigin`: how an upgraded gift reached its owner.
enum MessageGiftOrigin {
  /// No origin (not an upgraded gift) or an origin this client does not know.
  unknown,
  upgrade,
  transfer,
  resale,
  blockchain,
  prepaidUpgrade,
  offer,
  craft,
}

/// The state of an upgraded-gift purchase offer.
enum MessageGiftOfferState {
  pending,
  accepted,

  /// Rejected by the owner (`giftPurchaseOfferStateRejected`, or
  /// `messageUpgradedGiftPurchaseOfferRejected` without `was_expired`).
  declined,

  /// `messageUpgradedGiftPurchaseOfferRejected` with `was_expired`.
  expired,
}

/// TDLib `upgradedGiftBackdropColors`, as opaque ARGB values for `Color(...)`.
class MessageGiftBackdropColors {
  const MessageGiftBackdropColors({
    required this.centerColor,
    required this.edgeColor,
    required this.symbolColor,
    required this.textColor,
  });

  final int centerColor;
  final int edgeColor;
  final int symbolColor;
  final int textColor;
}

/// The whole gift sticker, built like a `messageSticker` so the card can use
/// the same TGS / WebM players.
class MessageGiftSticker {
  const MessageGiftSticker({
    this.image,
    this.thumbnail,
    this.animated,
    this.video,
    this.width,
    this.height,
    this.fileId,
    this.setId,
    this.emoji = '',
    this.uniqueId = '',
    this.hasStaticThumbnail = false,
  });

  /// What a static image view shows: the full file for a static (WebP)
  /// sticker, otherwise the static thumbnail behind the animation.
  final TdFileRef? image;

  /// The sticker's static thumbnail, if TDLib supplied one.
  final TdFileRef? thumbnail;

  /// `.tgs` (Lottie) sticker file.
  final TdFileRef? animated;

  /// `.webm` video sticker file.
  final TdFileRef? video;
  final int? width;
  final int? height;
  final int? fileId;
  final int? setId;
  final String emoji;

  /// The sticker file's `remote.unique_id`: the same for every copy of the
  /// sticker, across chats and accounts. Empty when TDLib omitted it.
  final String uniqueId;

  /// Whether [thumbnail] is a decodable still (WebP, JPEG or PNG) rather than
  /// a TGS / WebM animation.
  final bool hasStaticThumbnail;

  bool get isAnimated => animated != null || video != null;

  /// A low-cost static image to show while the full sticker loads.
  TdFileRef? get placeholder => thumbnail ?? image;
}

/// One line of gift copy. The sender's note keeps its formatting entities
/// (including custom emoji); generated copy has none.
class MessageGiftLine {
  const MessageGiftLine(
    this.text, {
    this.entities = const [],
    this.isNote = false,
  });

  final String text;
  final List<MessageTextEntity> entities;
  final bool isNote;
}

/// A gift message, kept on `ChatMessage.gift`.
///
/// The model holds data only. The helpers below return [AppStringKeys] or
/// strings resolved for the current app locale (or an explicit `localeKey`
/// such as `en` / `zhHans`), so no copy is frozen at parse time.
class MessageGift {
  const MessageGift({
    required this.kind,
    required this.contentType,
    this.origin = MessageGiftOrigin.unknown,
    this.offerState,
    this.senderUserId,
    this.senderChatId,
    this.receiverUserId,
    this.receiverChatId,
    this.receiverIsCurrentUser = false,
    this.isSenderHidden = false,
    this.isPrivate = false,
    this.note = '',
    this.noteEntities = const [],
    this.sticker,
    this.starCount = 0,
    this.gramUnits = 0,
    this.premiumMonthCount = 0,
    this.premiumDayCount = 0,
    this.sellStarCount = 0,
    this.prepaidUpgradeStarCount = 0,
    this.giftId = 0,
    this.upgradedName = '',
    this.upgradedTitle = '',
    this.upgradedNumber = 0,
    this.backdropColors,
    this.isSaved = false,
    this.canBeUpgraded = false,
    this.wasConverted = false,
    this.wasUpgraded = false,
    this.wasRefunded = false,
    this.wasTransferred = false,
    this.isFromGiveaway = false,
    this.isUnclaimed = false,
    this.offerExpirationDate = 0,
  });

  final MessageGiftKind kind;

  /// The raw TDLib content `@type`.
  final String contentType;

  /// Upgraded gifts only (`messageUpgradedGift`, `messageRefundedUpgradedGift`).
  final MessageGiftOrigin origin;

  /// Purchase offers only.
  final MessageGiftOfferState? offerState;

  /// Who sent the gift: a user, or a chat (a channel gift, the chat that
  /// created a Premium code, the giveaway's boosted chat). Both null when
  /// TDLib does not name the sender.
  final int? senderUserId;
  final int? senderChatId;

  /// Who received it. [receiverChatId] is set for channel gifts.
  final int? receiverUserId;
  final int? receiverChatId;

  /// TDLib says the current user is the receiver without naming them:
  /// Premium / Stars / Gram gifts report `receiver_user_id` 0 when incoming,
  /// and Premium codes and giveaway prizes are always for the current user.
  final bool receiverIsCurrentUser;

  /// Telegram hides the sender (an anonymous or private gift, or an unknown
  /// sender): the sheet shows `giftSheetAnonymous` for From.
  final bool isSenderHidden;

  /// TDLib `is_private`: sender and note are shown only to the receiver.
  final bool isPrivate;

  /// The sender's note (TDLib `text`), exactly as written, with its entities.
  final String note;
  final List<MessageTextEntity> noteEntities;

  /// `gift.sticker` (regular / refunded), `gift.model.sticker` (upgraded and
  /// purchase offers) or the content's `sticker` (Premium, Stars, Gram).
  final MessageGiftSticker? sticker;

  /// Stars: the regular gift's price, the gifted or won Stars, or a resale /
  /// offer price in Stars.
  final int starCount;

  /// Gram in smallest units (10^-9 Gram, see [GramAmount]): gifted Gram, or
  /// a resale / offer price in Gram (TDLib's `gram_cent_count` is converted).
  final int gramUnits;

  /// Premium duration; `premiumMonthCount` is 0 when it isn't whole months.
  final int premiumMonthCount;
  final int premiumDayCount;

  /// Regular gifts: Stars the receiver can convert the gift to.
  final int sellStarCount;

  /// Regular gifts: Stars the sender prepaid for an upgrade.
  final int prepaidUpgradeStarCount;

  /// TDLib `gift.id` / `upgradedGift.id`; 0 when absent.
  final int giftId;

  /// Upgraded gift slug, the argument of `getUpgradedGift` and the existing
  /// upgraded-gift page. Empty for anything that is not an upgraded gift.
  final String upgradedName;
  final String upgradedTitle;
  final int upgradedNumber;
  final MessageGiftBackdropColors? backdropColors;

  final bool isSaved;
  final bool canBeUpgraded;
  final bool wasConverted;
  final bool wasUpgraded;
  final bool wasRefunded;
  final bool wasTransferred;
  final bool isFromGiveaway;
  final bool isUnclaimed;

  /// Purchase offers: Unix time the offer expires or expired; 0 if unknown.
  final int offerExpirationDate;

  bool get hasNote => note.trim().isNotEmpty;

  /// Whether TDLib supplied upgraded-gift details (title, number, backdrop).
  bool get isUpgradedGift => upgradedName.isNotEmpty;

  /// Tap opens the existing upgraded-gift page for [upgradedName] instead of
  /// the gift sheet.
  bool get opensUpgradedGiftPage => upgradedName.isNotEmpty;

  /// Whether the gift was sent to the current account, which picks the
  /// `...Received` title.
  ///
  /// Pass the same [outgoing] the transcript uses for the bubble side
  /// (`isOutgoingTranscriptMessage(message, meId)`) and the account's user id
  /// ([meId], `ChatViewModel.meId` / `MessageBubble.meId`). An outgoing gift,
  /// a channel gift and a gift to someone else are not incoming to me.
  bool isIncomingToMe({required bool outgoing, int? meId}) {
    if (outgoing) return false;
    if (receiverIsCurrentUser) return true;
    if (receiverChatId != null) return false;
    final receiver = receiverUserId;
    if (receiver == null) return false;
    // Before `getMe` resolves, an incoming gift to a user is a gift in a
    // private chat with this account, i.e. to me.
    return meId == null || receiver == meId;
  }

  /// The card and sheet title for this gift.
  String titleKey(bool isIncomingToMe) {
    switch (kind) {
      case MessageGiftKind.regular:
        return _sentOrReceived(isIncomingToMe);
      case MessageGiftKind.upgraded:
        return switch (origin) {
          MessageGiftOrigin.upgrade || MessageGiftOrigin.prepaidUpgrade =>
            AppStringKeys.giftCardTitleUpgraded,
          MessageGiftOrigin.resale ||
          MessageGiftOrigin.offer => AppStringKeys.giftCardTitleBought,
          MessageGiftOrigin.craft => AppStringKeys.giftCardTitleCrafted,
          MessageGiftOrigin.transfer ||
          MessageGiftOrigin.blockchain ||
          MessageGiftOrigin.unknown => _sentOrReceived(isIncomingToMe),
        };
      case MessageGiftKind.refunded:
      case MessageGiftKind.refundedUpgraded:
        return AppStringKeys.giftCardTitleRefunded;
      case MessageGiftKind.purchaseOffer:
        return AppStringKeys.giftCardTitleOffer;
      case MessageGiftKind.purchaseOfferRejected:
        return offerState == MessageGiftOfferState.expired
            ? AppStringKeys.giftCardTitleOfferExpired
            : AppStringKeys.giftCardTitleOfferDeclined;
      case MessageGiftKind.premium:
        return isIncomingToMe
            ? AppStringKeys.giftCardTitlePremiumReceived
            : AppStringKeys.giftCardTitlePremiumSent;
      case MessageGiftKind.premiumCode:
        return AppStringKeys.giftCardTitlePremiumCode;
      case MessageGiftKind.stars:
        return isIncomingToMe
            ? AppStringKeys.giftCardTitleStarsReceived
            : AppStringKeys.giftCardTitleStarsSent;
      case MessageGiftKind.giveawayStars:
        return AppStringKeys.giftCardTitleGiveawayStars;
      case MessageGiftKind.gram:
        return isIncomingToMe
            ? AppStringKeys.giftCardTitleGramReceived
            : AppStringKeys.giftCardTitleGramSent;
    }
  }

  static String _sentOrReceived(bool isIncomingToMe) => isIncomingToMe
      ? AppStringKeys.giftCardTitleReceived
      : AppStringKeys.giftCardTitleSent;

  /// The card's optional second line, first rule that applies: the note;
  /// an upgraded gift's name and number; the Premium duration; the Stars or
  /// Gram amount; a purchase offer's state. Null when none applies (a plain
  /// gift without a note). Never a price for gifts and offers.
  MessageGiftLine? secondLine({String? localeKey}) {
    if (hasNote) {
      return MessageGiftLine(note, entities: noteEntities, isNote: true);
    }
    final String? text;
    switch (kind) {
      case MessageGiftKind.regular:
      case MessageGiftKind.purchaseOfferRejected:
        text = null;
      case MessageGiftKind.upgraded:
      case MessageGiftKind.refunded:
      case MessageGiftKind.refundedUpgraded:
        text = upgradedNameNumber(localeKey: localeKey);
      case MessageGiftKind.premium:
      case MessageGiftKind.premiumCode:
        text = premiumDurationText(localeKey: localeKey);
      case MessageGiftKind.stars:
      case MessageGiftKind.giveawayStars:
        text = starCount > 0
            ? starsText(starCount, localeKey: localeKey)
            : null;
      case MessageGiftKind.gram:
        text = gramUnits > 0
            ? GramAmount.format(gramUnits, localeKey: localeKey)
            : null;
      case MessageGiftKind.purchaseOffer:
        text = switch (offerState) {
          MessageGiftOfferState.pending => _t(
            AppStringKeys.giftOfferPending,
            localeKey,
          ),
          MessageGiftOfferState.accepted => _t(
            AppStringKeys.giftOfferAccepted,
            localeKey,
          ),
          _ => null,
        };
    }
    return text == null || text.isEmpty ? null : MessageGiftLine(text);
  }

  /// "Gift Name #123" for an upgraded gift (number without grouping); the
  /// gift's own title, or the generic Gift label when it has none. Null when
  /// TDLib supplied no upgraded-gift details.
  String? upgradedNameNumber({String? localeKey}) {
    final title = upgradedTitle.trim();
    if (title.isEmpty && upgradedNumber <= 0) return null;
    final name = title.isEmpty
        ? _t(AppStringKeys.linkHandlerDetailGift, localeKey)
        : title;
    if (upgradedNumber <= 0) return name;
    return _t(AppStringKeys.giftUpgradedNameNumber, localeKey, {
      'value1': name,
      'value2': '$upgradedNumber',
    });
  }

  /// The bare Premium duration for the card ("3 months"), days when the
  /// duration isn't whole months. Null when unknown.
  String? premiumDurationText({String? localeKey}) {
    if (premiumMonthCount > 0) {
      return _plural(
        AppStringKeys.giftDurationMonths,
        premiumMonthCount,
        localeKey,
      );
    }
    if (premiumDayCount > 0) {
      return _plural(
        AppStringKeys.giftDurationDays,
        premiumDayCount,
        localeKey,
      );
    }
    return null;
  }

  /// The sheet's Value row: Stars, the Premium duration with the product
  /// name, the Gram amount, or an offer / resale price. Null when unknown.
  String? valueText({String? localeKey}) {
    if (kind == MessageGiftKind.premium ||
        kind == MessageGiftKind.premiumCode) {
      if (premiumMonthCount > 0) {
        return _plural(
          AppStringKeys.giftPremiumMonths,
          premiumMonthCount,
          localeKey,
        );
      }
      if (premiumDayCount > 0) {
        return _plural(
          AppStringKeys.giftPremiumDays,
          premiumDayCount,
          localeKey,
        );
      }
      return null;
    }
    if (starCount > 0) return starsText(starCount, localeKey: localeKey);
    if (gramUnits > 0) {
      return GramAmount.format(gramUnits, localeKey: localeKey);
    }
    return null;
  }

  /// The sheet's Status values, in display order; join them with " · ".
  List<String> get statusKeys => [
    if (kind == MessageGiftKind.refunded ||
        kind == MessageGiftKind.refundedUpgraded ||
        wasRefunded)
      AppStringKeys.giftStatusRefunded,
    if (wasConverted) AppStringKeys.giftStatusConverted,
    if (wasUpgraded) AppStringKeys.giftStatusUpgraded,
    if (isFromGiveaway) AppStringKeys.giftStatusFromGiveaway,
    if (isUnclaimed) AppStringKeys.giftStatusUnclaimed,
  ];

  /// [statusKeys] resolved; empty when no status is known.
  List<String> statusTexts({String? localeKey}) => [
    for (final key in statusKeys) _t(key, localeKey),
  ];

  /// "50 Stars" in the given or current app locale.
  static String starsText(int count, {String? localeKey}) =>
      _plural(AppStringKeys.giftStarsCount, count, localeKey);

  static String _t(
    String key,
    String? localeKey, [
    Map<String, Object?> placeholders = const {},
  ]) => AppStrings.tForLocale(
    localeKey ?? AppStrings.currentLocaleKey,
    key,
    placeholders,
  );

  static String _plural(String key, int count, String? localeKey) =>
      AppStrings.pluralForLocale(
        localeKey ?? AppStrings.currentLocaleKey,
        key,
        count,
      );
}
