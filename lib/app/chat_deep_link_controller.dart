import 'package:flutter/foundation.dart';

class ChatDeepLinkRequest {
  const ChatDeepLinkRequest({
    required this.chatId,
    required this.title,
    this.messageId,
    this.accountUserId,
    this.accountSlot,
    this.preserveChatStack = false,
  });

  final int chatId;
  final String title;
  final int? messageId;
  final int? accountUserId;
  final int? accountSlot;
  final bool preserveChatStack;

  ChatDeepLinkRequest scopedToAccountSlot(int slot) => ChatDeepLinkRequest(
    chatId: chatId,
    title: title,
    messageId: messageId,
    accountUserId: accountUserId,
    accountSlot: slot,
    preserveChatStack: preserveChatStack,
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
    return ChatDeepLinkRequest(
      chatId: chatId,
      title: _normalizeDesktopChatTitle(title as String?),
      messageId: messageId as int?,
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
  }) {
    _pending = ChatDeepLinkRequest(
      chatId: chatId,
      title: title,
      messageId: messageId,
      accountUserId: accountUserId,
      accountSlot: accountSlot,
      preserveChatStack: preserveChatStack,
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
