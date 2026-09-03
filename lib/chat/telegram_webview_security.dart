import 'dart:convert';
import 'dart:math';

enum TelegramWebViewNavigationAction {
  navigateTrusted,
  navigateUntrusted,
  openExternally,
  block,
}

String newTelegramWebViewBridgeNonce() {
  final random = Random.secure();
  final bytes = List<int>.generate(24, (_) => random.nextInt(256));
  return base64UrlEncode(bytes);
}

/// The exact HTTPS origin that is allowed to use a privileged Telegram bridge.
class TelegramWebViewOrigin {
  const TelegramWebViewOrigin._({required this.host, required this.port});

  final String host;
  final int port;

  static TelegramWebViewOrigin? fromUrl(String value) {
    return fromUri(Uri.tryParse(value));
  }

  static TelegramWebViewOrigin? fromUri(Uri? uri) {
    if (!_isSafeHttpsUri(uri)) return null;
    return TelegramWebViewOrigin._(
      host: uri!.host.toLowerCase(),
      port: uri.port,
    );
  }

  bool matches(Uri? uri) {
    return _isSafeHttpsUri(uri) &&
        uri!.host.toLowerCase() == host &&
        uri.port == port;
  }
}

TelegramWebViewNavigationAction telegramMiniAppNavigationAction({
  required TelegramWebViewOrigin? expectedOrigin,
  required String url,
  required bool isMainFrame,
}) {
  final uri = Uri.tryParse(url);
  if (!isMainFrame) {
    return _isSafeHttpsUri(uri)
        ? TelegramWebViewNavigationAction.navigateUntrusted
        : TelegramWebViewNavigationAction.block;
  }
  if (expectedOrigin?.matches(uri) ?? false) {
    return TelegramWebViewNavigationAction.navigateTrusted;
  }
  if (_isSafeHttpsUri(uri)) {
    return TelegramWebViewNavigationAction.openExternally;
  }
  return TelegramWebViewNavigationAction.block;
}

TelegramWebViewNavigationAction telegramPaymentNavigationAction({
  required TelegramWebViewOrigin? expectedOrigin,
  required String url,
  required bool isMainFrame,
}) {
  final uri = Uri.tryParse(url);
  if (!isMainFrame) {
    return _isSafeHttpsUri(uri)
        ? TelegramWebViewNavigationAction.navigateUntrusted
        : TelegramWebViewNavigationAction.block;
  }
  if (expectedOrigin?.matches(uri) ?? false) {
    return TelegramWebViewNavigationAction.navigateTrusted;
  }
  // Payment providers commonly cross an HTTPS origin boundary for 3-D Secure
  // or bank verification. Keep that navigation in-process, but never grant it
  // the credential-submission bridge.
  if (_isSafeHttpsUri(uri)) {
    return TelegramWebViewNavigationAction.navigateUntrusted;
  }
  return TelegramWebViewNavigationAction.block;
}

bool _isSafeHttpsUri(Uri? uri) {
  if (uri == null) return false;
  try {
    final port = uri.port;
    return uri.scheme.toLowerCase() == 'https' &&
        uri.hasAuthority &&
        uri.host.isNotEmpty &&
        uri.userInfo.isEmpty &&
        port > 0 &&
        port <= 65535;
  } catch (_) {
    return false;
  }
}
