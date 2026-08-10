import 'package:flutter/widgets.dart';

import '../app/chat_deep_link_controller.dart';

typedef InternalChatMessageOpener = Future<void> Function(int messageId);

/// The transcript that owns the context used to open an internal Telegram
/// link. Keeping this context-local matters when more than one chat window is
/// visible: a same-chat link must scroll the window that was actually clicked.
class InternalChatLinkTarget {
  const InternalChatLinkTarget({
    required this.chatId,
    required this.accountSlot,
    required this.openMessage,
  });

  final int chatId;
  final int accountSlot;
  final InternalChatMessageOpener openMessage;
}

class InternalChatLinkScope extends InheritedWidget {
  const InternalChatLinkScope({
    super.key,
    required this.target,
    required super.child,
  });

  final InternalChatLinkTarget target;

  static InternalChatLinkTarget? targetOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<InternalChatLinkScope>()?.target;

  @override
  bool updateShouldNotify(InternalChatLinkScope oldWidget) =>
      target.chatId != oldWidget.target.chatId ||
      target.accountSlot != oldWidget.target.accountSlot ||
      target.openMessage != oldWidget.target.openMessage;
}

enum InternalChatLinkDisposition {
  scrolledWithinCurrentChat,
  keptCurrentChat,
  requestedAdaptiveNavigation,
}

/// Routes a TDLib-resolved chat link using the platform's conversation model.
///
/// Current-chat message links stay inside the owning transcript. Every other
/// chat is handed to the app-level deep-link controller, whose adaptive parent
/// replaces the selected detail pane on wide layouts and preserves the source
/// conversation beneath the destination on phones.
Future<InternalChatLinkDisposition> routeResolvedInternalChatLink({
  required int chatId,
  required String title,
  int? messageId,
  InternalChatLinkTarget? source,
  ChatDeepLinkController? controller,
}) async {
  final targetMessageId = messageId != null && messageId > 0 ? messageId : null;
  if (source?.chatId == chatId) {
    if (targetMessageId == null) {
      return InternalChatLinkDisposition.keptCurrentChat;
    }
    await source!.openMessage(targetMessageId);
    return InternalChatLinkDisposition.scrolledWithinCurrentChat;
  }

  (controller ?? ChatDeepLinkController.shared).openChat(
    chatId: chatId,
    title: title,
    messageId: targetMessageId,
    accountSlot: source?.accountSlot,
    preserveChatStack: source != null,
  );
  return InternalChatLinkDisposition.requestedAdaptiveNavigation;
}
