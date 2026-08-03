import 'package:flutter/widgets.dart';

import '../chat/chat_view.dart';
import 'app_navigator.dart';
import 'chat_deep_link_controller.dart';
import 'desktop_chat_window.dart';
import 'desktop_mini_app_window.dart';
import 'desktop_utility_window.dart';

/// Opens a conversation in the primary app window when invoked from a
/// registered desktop child. Mobile and primary-window callers keep the
/// normal app-level route behavior.
Future<void> openChatFromCurrentWindow(
  BuildContext context, {
  required int chatId,
  required String title,
  int? initialMessageId,
  bool replaceCurrent = false,
  Future<void> Function()? openFallback,
}) async {
  if (await handoffChatToPrimaryWindow(
    chatId: chatId,
    title: title,
    initialMessageId: initialMessageId,
  )) {
    return;
  }
  if (!context.mounted) return;
  if (openFallback != null) {
    await openFallback();
    return;
  }
  final route = AppChatPageRoute<void>(
    builder: (_) => ChatView(
      chatId: chatId,
      title: title,
      initialMessageId: initialMessageId,
    ),
  );
  if (replaceCurrent) {
    await replaceWithAppChatRoute<void, void>(context, route);
  } else {
    await pushAppChatRoute<void>(context, route);
  }
}

/// Returns whether a registered desktop child handed this conversation to the
/// primary window. Primary-window and mobile callers return false.
Future<bool> handoffChatToPrimaryWindow({
  required int chatId,
  required String title,
  int? initialMessageId,
}) async {
  final request = ChatDeepLinkRequest(
    chatId: chatId,
    title: title,
    messageId: initialMessageId,
  );
  return await DesktopUtilityWindowService.instance.openChatInPrimaryWindow(
        request,
      ) ||
      await DesktopChatWindowService.instance.openChatInPrimaryWindow(
        request,
      ) ||
      await DesktopMiniAppWindowService.instance.openChatInPrimaryWindow(
        request,
      );
}
