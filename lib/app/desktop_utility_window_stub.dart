import 'chat_deep_link_controller.dart';
import 'desktop_utility_window_models.dart';

const supportsDesktopUtilityWindows = false;

void attachDesktopUtilityMainProxy({
  Future<void> Function()? onSettingsChanged,
  int? Function(int accountSlot)? accountUserIdForSlot,
}) {}

void detachDesktopUtilityMainProxy() {}

void notifyDesktopUtilityAccountIdentityChanged() {}

void attachDesktopUtilityChildPresentationReload(
  Future<void> Function() callback,
) {}

void detachDesktopUtilityChildPresentationReload() {}

Future<void> notifyDesktopUtilityPresentationChanged() async {}

Future<bool> openDesktopUtilityWindow(
  DesktopUtilityWindowArguments arguments,
) async => false;

Future<bool> openChatInPrimaryWindowFromDesktopUtility(
  ChatDeepLinkRequest request,
) async => false;

Future<void> configureDesktopUtilityChildProxy(
  DesktopUtilityWindowArguments arguments,
) async {}

Future<void> closeCurrentDesktopUtilityWindow() async {}

Future<void> notifyDesktopUtilitySettingsChanged(
  DesktopUtilityWindowArguments arguments,
) async {}
