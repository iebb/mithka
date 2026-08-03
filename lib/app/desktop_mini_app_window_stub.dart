import 'chat_deep_link_controller.dart';
import 'desktop_mini_app_window_models.dart';

const supportsDesktopMiniAppWindows = false;

void attachDesktopMiniAppMainProxy() {}

void detachDesktopMiniAppMainProxy() {}

void notifyDesktopMiniAppAccountIdentityChanged() {}

Future<bool> openDesktopMiniAppWindow(
  DesktopMiniAppWindowLaunch launch,
) async => false;

Future<bool> openChatInPrimaryWindowFromDesktopMiniApp(
  ChatDeepLinkRequest request,
) async => false;

Future<DesktopMiniAppWindowLaunch> configureDesktopMiniAppChildProxy(
  DesktopMiniAppWindowArguments arguments,
) async => throw UnsupportedError('Desktop Mini App windows are unavailable');

Future<void> closeCurrentDesktopMiniAppWindow() async {}

Future<bool?> setCurrentDesktopMiniAppWindowFullscreen(bool fullscreen) async =>
    null;
