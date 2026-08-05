import 'package:flutter/foundation.dart';

class ChatDeepLinkRequest {
  const ChatDeepLinkRequest({
    required this.chatId,
    required this.title,
    this.messageId,
    this.accountUserId,
    this.accountSlot,
  });

  final int chatId;
  final String title;
  final int? messageId;
  final int? accountUserId;
  final int? accountSlot;

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
  }) {
    _pending = ChatDeepLinkRequest(
      chatId: chatId,
      title: title,
      messageId: messageId,
      accountUserId: accountUserId,
      accountSlot: accountSlot,
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
