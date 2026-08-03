import 'package:flutter/widgets.dart';

import 'chat_deep_link_controller.dart';
import 'desktop_chat_window_models.dart';
import 'desktop_utility_window_models.dart';

bool get supportsDesktopChatWindows => false;

void attachDesktopChatMainProxy({
  int? Function(int accountSlot)? accountUserIdForSlot,
}) {}

void detachDesktopChatMainProxy() {}

void notifyDesktopChatAccountIdentityChanged() {}

Future<void> notifyDesktopChatPresentationChanged() async {}

void attachDesktopChatChildPresentationReload(
  Future<void> Function() callback,
) {}

void detachDesktopChatChildPresentationReload() {}

Future<bool> openDesktopChatWindow(
  DesktopChatWindowArguments arguments,
) async => false;

Future<bool> openChatInPrimaryWindowFromDesktopChat(
  ChatDeepLinkRequest request,
) async => false;

Future<bool> requestDesktopUtilityWindowFromChat({
  required DesktopChatWindowArguments requestingChat,
  required DesktopUtilityWindowArguments utility,
}) async => false;

Future<void> configureDesktopChatChildProxy(
  DesktopChatWindowArguments arguments,
) async {}

Future<void> closeCurrentDesktopChatWindow() async {}

Widget buildDesktopChatWindowHost({
  required DesktopChatWindowArguments initialArguments,
  required Widget Function(
    BuildContext context,
    DesktopChatWindowArguments arguments,
  )
  builder,
}) => Builder(builder: (context) => builder(context, initialArguments));
