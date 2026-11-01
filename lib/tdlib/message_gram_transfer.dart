//
//  message_gram_transfer.dart
//
//  A Gram transfer between two wallets, carried by a TDLib
//  `messageTonWalletTransfer` message, plus the rule that turns it and its
//  message's sending state into what the envelope shows.
//

import 'dart:convert';

import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/l10n/gram_amount.dart';

import 'json_helpers.dart';

/// Where a transfer stands, as the envelope and the detail sheet show it.
enum GramTransferState {
  /// Money that came in: it is already in the wallet.
  received,

  /// An outgoing transfer the server has.
  sent,

  /// An outgoing transfer still on its way: the message is pending, or TDLib
  /// has not given it a transaction yet.
  sending,

  /// An outgoing transfer TDLib could not send.
  failed;

  /// Sending and failed transfers draw in the muted colours.
  bool get isMuted => this == sending || this == failed;
}

/// The transfer a `messageTonWalletTransfer` message carries.
class MessageGramTransfer {
  const MessageGramTransfer({
    required this.senderUserId,
    required this.transactionId,
    required this.peerAddress,
    required this.amount,
    required this.comment,
    required this.isCommentEncrypted,
    this.isSendFailed = false,
  });

  /// The TDLib message content type this model is parsed from.
  static const contentType = 'messageTonWalletTransfer';

  /// The user who sent the money; 0 when unknown or not a Telegram user.
  final int senderUserId;

  /// TDLib's identifier for `getTonWalletTransaction`; empty until the
  /// transfer has been sent.
  final String transactionId;

  /// The other side's wallet address.
  final String peerAddress;

  /// In 10^-9 Gram; negative for an outgoing transfer.
  final int amount;

  /// The sender's comment as written; empty when there is none.
  final String comment;

  /// The comment is encrypted and [comment] cannot be shown.
  final bool isCommentEncrypted;

  /// The message's sending state is `messageSendingStateFailed`.
  final bool isSendFailed;

  bool get hasSender => senderUserId != 0;
  bool get hasTransactionId => transactionId.isNotEmpty;

  /// The money left the current user's wallet. A zero amount, which TDLib
  /// does not send, follows the message's direction.
  bool isOutgoing({required bool messageOutgoing}) =>
      amount < 0 || (amount == 0 && messageOutgoing);

  /// See [GramTransferState]. [isSending] is the message's pending state.
  GramTransferState state({
    required bool messageOutgoing,
    required bool isSending,
  }) {
    if (isSendFailed) return GramTransferState.failed;
    if (!isOutgoing(messageOutgoing: messageOutgoing)) {
      return GramTransferState.received;
    }
    if (isSending || !hasTransactionId) return GramTransferState.sending;
    return GramTransferState.sent;
  }

  /// "1.5 GRAM": the amount without its sign.
  String formattedAmount({String? localeKey}) =>
      GramAmount.format(amount.abs(), localeKey: localeKey);

  /// "[Transfer] 1.5 GRAM" for the chat list, notifications and replies.
  static String previewText(Map<String, dynamic> content) => AppStrings.t(
    AppStringKeys.tdMessageTransferValue1,
    {'value1': GramAmount.format((content.int64('amount') ?? 0).abs())},
  );

  /// Parses [content] when it is a transfer; [message] supplies the sending
  /// state.
  static MessageGramTransfer? parse(
    Map<String, dynamic> message,
    Map<String, dynamic>? content,
  ) {
    if (content == null || content.type != contentType) return null;
    return MessageGramTransfer(
      senderUserId: content.int64('sender_user_id') ?? 0,
      transactionId: content.str('transaction_id') ?? '',
      peerAddress: content.str('peer_address') ?? '',
      amount: content.int64('amount') ?? 0,
      comment: content.str('comment') ?? '',
      isCommentEncrypted: content.boolean('is_comment_encrypted') ?? false,
      isSendFailed:
          message.obj('sending_state')?.type == 'messageSendingStateFailed',
    );
  }
}

/// What `getTonWalletTransaction` adds to a transfer on the detail sheet.
class GramTransferDetails {
  const GramTransferDetails({
    this.peerUserId = 0,
    this.date = 0,
    this.feeAmount,
    this.isGasless = false,
    this.chainHash,
  });

  /// The other side's Telegram user; 0 when it has none.
  final int peerUserId;
  final int date;

  /// In 10^-9 Gram; null when TDLib did not say.
  final int? feeAmount;
  final bool isGasless;

  /// The succeeded transaction's hash as 64 lowercase hex digits; null until
  /// it has one, or when it cannot be read.
  final String? chainHash;

  /// Parses a TDLib `tonWalletTransaction`; null for anything else.
  static GramTransferDetails? parse(Map<String, dynamic> transaction) {
    if (transaction.type != 'tonWalletTransaction') return null;
    final state = transaction.obj('state');
    final kind = transaction.obj('type');
    return GramTransferDetails(
      peerUserId: transaction.int64('peer_user_id') ?? 0,
      date: transaction.integer('date') ?? 0,
      feeAmount: transaction.int64('fee_amount'),
      isGasless:
          kind?.type == 'tonWalletTransactionTypeTransfer' &&
          (kind?.boolean('is_gasless') ?? false),
      chainHash: state?.type == 'tonWalletTransactionStateSucceeded'
          ? hexHash(state?.str('tx_hash'))
          : null,
    );
  }

  static final _hex64 = RegExp(r'^[0-9a-fA-F]{64}$');

  /// A 32-byte hash as 64 lowercase hex digits, from hex, base64 or base64url;
  /// null when [raw] is none of these.
  static String? hexHash(String? raw) {
    final value = raw?.trim() ?? '';
    if (value.isEmpty) return null;
    if (_hex64.hasMatch(value)) return value.toLowerCase();
    final bytes = _base64Bytes(value);
    if (bytes == null || bytes.length != 32) return null;
    return [
      for (final byte in bytes) byte.toRadixString(16).padLeft(2, '0'),
    ].join();
  }

  static List<int>? _base64Bytes(String value) {
    var normalized = value.replaceAll('-', '+').replaceAll('_', '/');
    final remainder = normalized.length % 4;
    if (remainder == 1) return null;
    if (remainder > 0) normalized += '=' * (4 - remainder);
    try {
      return base64.decode(normalized);
    } on FormatException {
      return null;
    }
  }
}
