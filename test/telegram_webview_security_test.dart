import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/telegram_webview_security.dart';

void main() {
  group('Telegram WebView origins', () {
    test('requires an exact HTTPS origin', () {
      final origin = TelegramWebViewOrigin.fromUrl(
        'https://Mini.Example:8443/app?tgWebAppData=signed',
      );

      expect(origin, isNotNull);
      expect(
        origin!.matches(Uri.parse('https://mini.example:8443/next')),
        isTrue,
      );
      expect(origin.matches(Uri.parse('https://mini.example/next')), isFalse);
      expect(
        origin.matches(Uri.parse('https://sub.mini.example:8443/')),
        isFalse,
      );
      expect(origin.matches(Uri.parse('http://mini.example:8443/')), isFalse);
      expect(TelegramWebViewOrigin.fromUrl('data:text/html,hello'), isNull);
      expect(
        TelegramWebViewOrigin.fromUrl('https://user@mini.example/'),
        isNull,
      );
      expect(
        TelegramWebViewOrigin.fromUrl('https://mini.example:99999/'),
        isNull,
      );
    });

    test('bridge nonces are high-entropy and unique per view', () {
      final first = newTelegramWebViewBridgeNonce();
      final second = newTelegramWebViewBridgeNonce();

      expect(first, isNot(second));
      expect(first.length, greaterThanOrEqualTo(32));
      expect(second.length, greaterThanOrEqualTo(32));
    });

    test('Mini Apps externalize unrelated top-level HTTPS pages', () {
      final origin = TelegramWebViewOrigin.fromUrl('https://mini.example/app');

      expect(
        telegramMiniAppNavigationAction(
          expectedOrigin: origin,
          url: 'https://mini.example/page',
          isMainFrame: true,
        ),
        TelegramWebViewNavigationAction.navigateTrusted,
      );
      expect(
        telegramMiniAppNavigationAction(
          expectedOrigin: origin,
          url: 'https://example.org/',
          isMainFrame: true,
        ),
        TelegramWebViewNavigationAction.openExternally,
      );
      for (final unsafe in [
        'http://mini.example/',
        'data:text/html,hello',
        'about:blank',
        'javascript:alert(1)',
      ]) {
        expect(
          telegramMiniAppNavigationAction(
            expectedOrigin: origin,
            url: unsafe,
            isMainFrame: true,
          ),
          TelegramWebViewNavigationAction.block,
          reason: unsafe,
        );
      }
      expect(
        telegramMiniAppNavigationAction(
          expectedOrigin: origin,
          url: 'data:text/html,frame',
          isMainFrame: false,
        ),
        TelegramWebViewNavigationAction.block,
      );
    });

    test('payment redirects remain isolated from the trusted bridge', () {
      final origin = TelegramWebViewOrigin.fromUrl(
        'https://payments.example/form',
      );

      expect(
        telegramPaymentNavigationAction(
          expectedOrigin: origin,
          url: 'https://bank.example/3ds',
          isMainFrame: true,
        ),
        TelegramWebViewNavigationAction.navigateUntrusted,
      );
      expect(
        telegramPaymentNavigationAction(
          expectedOrigin: origin,
          url: 'about:blank',
          isMainFrame: true,
        ),
        TelegramWebViewNavigationAction.block,
      );
      expect(
        telegramPaymentNavigationAction(
          expectedOrigin: origin,
          url: 'data:text/html,frame',
          isMainFrame: false,
        ),
        TelegramWebViewNavigationAction.block,
      );
      expect(
        telegramPaymentNavigationAction(
          expectedOrigin: origin,
          url: 'javascript:alert(1)',
          isMainFrame: false,
        ),
        TelegramWebViewNavigationAction.block,
      );
    });
  });
}
