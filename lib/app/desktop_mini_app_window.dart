import 'chat_deep_link_controller.dart';
import 'desktop_mini_app_window_models.dart';
import 'desktop_mini_app_window_stub.dart'
    if (dart.library.io) 'desktop_mini_app_window_io.dart'
    as implementation;

export 'desktop_mini_app_window_models.dart';

/// Owns independent native windows used by Telegram Mini Apps on macOS.
class DesktopMiniAppWindowService {
  DesktopMiniAppWindowService._();

  static final DesktopMiniAppWindowService instance =
      DesktopMiniAppWindowService._();

  bool get isSupported => implementation.supportsDesktopMiniAppWindows;

  void attachMainProxy() => implementation.attachDesktopMiniAppMainProxy();

  void detachMainProxy() => implementation.detachDesktopMiniAppMainProxy();

  void notifyAccountIdentityChanged() =>
      implementation.notifyDesktopMiniAppAccountIdentityChanged();

  Future<bool> open(DesktopMiniAppWindowLaunch launch) =>
      implementation.openDesktopMiniAppWindow(launch);

  Future<bool> openChatInPrimaryWindow(ChatDeepLinkRequest request) =>
      implementation.openChatInPrimaryWindowFromDesktopMiniApp(request);

  Future<DesktopMiniAppWindowLaunch> configureChildProxy(
    DesktopMiniAppWindowArguments arguments,
  ) => implementation.configureDesktopMiniAppChildProxy(arguments);

  Future<void> closeCurrentWindow() =>
      implementation.closeCurrentDesktopMiniAppWindow();

  Future<bool?> setCurrentWindowFullscreen(bool fullscreen) =>
      implementation.setCurrentDesktopMiniAppWindowFullscreen(fullscreen);
}
