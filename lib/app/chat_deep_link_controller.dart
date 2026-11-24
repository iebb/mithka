import 'package:flutter/foundation.dart';

import '../chat/forward_handoff.dart';

/// A reply carried from another chat into the newly opened transcript.
///
/// The destination composer holds this as a cross-chat reply: its sends
/// address the source message via `inputMessageReplyToExternalMessage`, so
/// the destination chat shows a quote-reply header pointing at the original
/// message in [sourceChatId].
class ExternalReplyHandoff {
  const ExternalReplyHandoff({
    required this.sourceChatId,
    required this.message,
    this.quote,
    this.draftText = '',
  });

  final int sourceChatId;
  final ChatMessagePayload message;

  /// Pre-selected quote range, when the reply started as a quote.
  final Object? quote;

  /// The composer text typed before the move, restored into the destination.
  final String draftText;
}

/// Minimal message identity the handoff carries. Kept as a thin carrier so
/// this file stays free of the chat-model import; the chat side reconstructs
/// a [ChatMessage] from it via [ChatMessagePayload.toChatMessage].
class ChatMessagePayload {
  const ChatMessagePayload({
    required this.id,
    required this.isOutgoing,
    required this.date,
    this.senderName,
    this.text = '',
  });

  final int id;
  final bool isOutgoing;
  final int date;
  final String? senderName;
  final String text;
}

class ChatDeepLinkRequest {
  const ChatDeepLinkRequest({
    required this.chatId,
    required this.title,
    this.messageId,
    this.accountUserId,
    this.accountSlot,
    this.preserveChatStack = false,
    this.fromNotification = false,
    this.externalReply,
    this.forwardHandoff,
  });

  final int chatId;
  final String title;
  final int? messageId;
  final int? accountUserId;
  final int? accountSlot;
  final bool preserveChatStack;

  /// A notification is about a message an account received, so when its
  /// account cannot be named the shell switches to the account that has the
  /// chat instead of asking.
  final bool fromNotification;

  /// A reply carried over from another chat (reply-in-another-chat). The
  /// destination transcript's composer starts with this reply pending.
  final ExternalReplyHandoff? externalReply;

  /// A forward carried over from the picking chat (forward-to-chat): the
  /// destination transcript's composer starts with this forward pending.
  final ForwardMessagesHandoff? forwardHandoff;

  ChatDeepLinkRequest scopedToAccountSlot(int slot) => ChatDeepLinkRequest(
    chatId: chatId,
    title: title,
    messageId: messageId,
    accountUserId: accountUserId,
    accountSlot: slot,
    preserveChatStack: preserveChatStack,
    fromNotification: fromNotification,
    externalReply: externalReply,
    forwardHandoff: forwardHandoff,
  );

  /// Presentation-only payload used when a registered desktop child asks the
  /// primary window to select a conversation. Account identity is never read
  /// from this map; the primary bridge supplies it from the authenticated
  /// child-window registration.
  Map<String, Object?> toDesktopIpcJson() => {
    'chatId': chatId,
    'title': _normalizeDesktopChatTitle(title),
    if (messageId != null) 'messageId': messageId,
  };

  static ChatDeepLinkRequest? tryParseDesktopIpc(Object? source) {
    if (source is! Map) return null;
    final chatId = source['chatId'];
    final messageId = source['messageId'];
    if (chatId is! int || chatId == 0) return null;
    if (messageId != null && (messageId is! int || messageId == 0)) {
      return null;
    }
    final title = source['title'];
    if (title != null && title is! String) return null;
    final handoff = source['externalReply'];
    if (handoff != null && handoff is! ExternalReplyHandoff) return null;
    final forwardHandoff = source['forwardHandoff'];
    if (forwardHandoff != null && forwardHandoff is! ForwardMessagesHandoff) {
      return null;
    }
    return ChatDeepLinkRequest(
      chatId: chatId,
      title: _normalizeDesktopChatTitle(title as String?),
      messageId: messageId as int?,
      externalReply: handoff as ExternalReplyHandoff?,
      forwardHandoff: forwardHandoff as ForwardMessagesHandoff?,
    );
  }
}

String _normalizeDesktopChatTitle(String? source) {
  final value = source?.replaceAll(RegExp(r'[\r\n]+'), ' ').trim() ?? '';
  if (value.isEmpty) return 'Mithka';
  return value.length <= 256 ? value : value.substring(0, 256);
}

/// The slot a deep link must open in, or null when it must not be opened at
/// all.
///
/// A chat id only means something inside the account that produced it. Opening
/// one against whichever account happens to be active does not fail loudly —
/// it lands on a different conversation that happens to share the id, which
/// reads as the app having opened the wrong chat. So a link naming an account
/// that is not signed in is dropped, and so is one naming no account while
/// several are signed in, because there is nothing to disambiguate it with.
int? resolveDeepLinkAccountSlot({
  required int? requestedSlot,
  required int? requestedUserId,
  required int activeSlot,
  required List<({int slot, int? userId})> accounts,
}) {
  if (requestedSlot != null) return requestedSlot;
  if (requestedUserId != null) {
    return accounts
        .where((account) => account.userId == requestedUserId)
        .map((account) => account.slot)
        .firstOrNull;
  }
  // Naming no account is only safe when there is a single account it could
  // have meant. A lone account is the common case, and the one that predates
  // notifications carrying an identity at all.
  return accounts.length <= 1 ? activeSlot : null;
}

class ChatDeepLinkController extends ChangeNotifier {
  ChatDeepLinkController._();

  static final ChatDeepLinkController shared = ChatDeepLinkController._();

  ChatDeepLinkRequest? _pending;

  void openChat({
    required int chatId,
    required String title,
    int? messageId,
    int? accountUserId,
    int? accountSlot,
    bool preserveChatStack = false,
    bool fromNotification = false,
    ExternalReplyHandoff? externalReply,
    ForwardMessagesHandoff? forwardHandoff,
  }) {
    _pending = ChatDeepLinkRequest(
      chatId: chatId,
      title: title,
      messageId: messageId,
      accountUserId: accountUserId,
      accountSlot: accountSlot,
      preserveChatStack: preserveChatStack,
      fromNotification: fromNotification,
      externalReply: externalReply,
      forwardHandoff: forwardHandoff,
    );
    notifyListeners();
  }

  ChatDeepLinkRequest? consumePending() {
    final request = _pending;
    _pending = null;
    return request;
  }

  /// Whether a host (MainTabView) is listening and can act on a request.
  ///
  /// Callers route through this controller so a conversation lands in the
  /// desktop split pane; without a host they must open the chat themselves
  /// rather than drop the request on the floor.
  bool get hasHost => hasListeners;
}
