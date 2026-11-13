import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/deep_link_service.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/chat/telegram_link.dart';
import 'package:mithka/platform/external_links.dart';

ExternalLink _classify(String url) => classifyExternalLink(Uri.parse(url));

void main() {
  group('external link classification', () {
    test('accepts tg:// links unchanged', () {
      expect(
        _classify('tg://resolve?domain=telegram'),
        const ExternalLink.telegram('tg://resolve?domain=telegram'),
      );
      expect(
        _classify('tg://join?invite=AbCdEf123'),
        const ExternalLink.telegram('tg://join?invite=AbCdEf123'),
      );
      expect(
        _classify('TG://resolve?domain=durov&post=1'),
        const ExternalLink.telegram('tg://resolve?domain=durov&post=1'),
      );
    });

    test('accepts t.me and telegram.me web links on registered hosts', () {
      for (final url in const [
        'https://t.me/telegram',
        'https://t.me/+AbCdEf123',
        'https://t.me/joinchat/AbCdEf123',
        'https://t.me/c/1234567890/42',
        'https://t.me/durov/1',
        'https://telegram.me/telegram',
        'https://www.t.me/telegram',
        'https://www.telegram.me/telegram',
        'https://telegram.dog/telegram',
        'https://www.telegram.dog/telegram',
        'http://t.me/telegram',
      ]) {
        final link = _classify(url);
        expect(link.kind, ExternalLinkKind.telegram, reason: url);
        expect(link.link, url, reason: url);
        expect(normalizeTelegramLink(link.link!), isNotNull, reason: url);
      }
    });

    test('keeps mk:// and mithka:// links on the existing path', () {
      expect(
        _classify('mk://resolve?domain=telegram'),
        const ExternalLink.telegram('mk://resolve?domain=telegram'),
      );
      expect(
        _classify('mithka://user?id=42'),
        const ExternalLink.telegram('mithka://user?id=42'),
      );
      expect(
        normalizeTelegramLink('mk://resolve?domain=telegram'),
        'tg://resolve?domain=telegram',
      );
    });

    test('ignores links the OS should never hand to Mithka', () {
      for (final url in const [
        'https://example.com/telegram',
        'https://t.me.example.com/telegram',
        'https://telegram.org/blog',
        'file:///etc/hosts',
        'mailto:someone@example.com',
      ]) {
        expect(_classify(url), ExternalLink.ignored, reason: url);
      }
    });

    test('sends only the bare t.me home page straight to the browser', () {
      for (final url in const [
        'https://t.me',
        'https://t.me/',
        'https://www.t.me/',
        'http://telegram.me/',
      ]) {
        expect(isTelegramWebHomePage(Uri.parse(url)), isTrue, reason: url);
      }
      for (final url in const [
        'https://t.me/telegram',
        'https://t.me/blog',
        'https://t.me/?start=1',
        'tg://resolve?domain=telegram',
        'https://example.com/',
      ]) {
        expect(isTelegramWebHomePage(Uri.parse(url)), isFalse, reason: url);
      }
    });
  });

  group('mk://open wrapper', () {
    test('round-trips Telegram links', () {
      for (final inner in const [
        'https://t.me/telegram',
        'https://t.me/+AbCdEf123',
        'https://telegram.me/c/1234567890/42?thread=7&single',
        'tg://resolve?domain=telegram&post=5',
      ]) {
        final wrapper = mithkaOpenLinkFor(inner);
        expect(wrapper, startsWith('mk://open?url='));
        expect(_classify(wrapper), ExternalLink.telegram(inner));
        expect(normalizeTelegramLink(wrapper), inner);
      }
    });

    test('adds https to a scheme-less t.me link', () {
      expect(
        _classify('mithka://open?url=t.me%2Ftelegram'),
        const ExternalLink.telegram('https://t.me/telegram'),
      );
    });

    test('rejects payloads that are not Telegram links', () {
      for (final url in const [
        'mk://open?url=https%3A%2F%2Fexample.com%2F',
        'mk://open?url=',
        'mk://open',
        'mk://open?url=mk%3A%2F%2Fresolve%3Fdomain%3Dtelegram',
        'mk://open?url=mk%3A%2F%2Fopen%3Furl%3Dhttps%253A%252F%252Ft.me%252Fx',
      ]) {
        expect(_classify(url), ExternalLink.notTelegram, reason: url);
      }
    });
  });

  group('loop guard', () {
    test('Android launches Telegram links outside Mithka explicitly', () {
      for (final url in const [
        'https://t.me/',
        'https://t.me/blog',
        'https://telegram.me/some/web/page',
        'http://www.t.me/x',
        'tg://unknown_feature?x=1',
      ]) {
        expect(
          externalLaunchMustBypassMithka(
            Uri.parse(url),
            platform: TargetPlatform.android,
            isWeb: false,
            onOhos: false,
          ),
          isTrue,
          reason: url,
        );
      }
    });

    test('macOS hands tg:// to the bridge but keeps t.me generic', () {
      expect(
        externalLaunchRouteFor(
          Uri.parse('tg://unknown_feature?x=1'),
          platform: TargetPlatform.macOS,
          isWeb: false,
          onOhos: false,
        ),
        ExternalLaunchRoute.bridge,
      );
      expect(
        externalLaunchRouteFor(
          Uri.parse('https://t.me/blog'),
          platform: TargetPlatform.macOS,
          isWeb: false,
          onOhos: false,
        ),
        ExternalLaunchRoute.generic,
      );
    });

    test('iOS and HarmonyOS never relaunch tg://', () {
      expect(
        externalLaunchRouteFor(
          Uri.parse('tg://unknown_feature?x=1'),
          platform: TargetPlatform.iOS,
          isWeb: false,
          onOhos: false,
        ),
        ExternalLaunchRoute.notice,
      );
      expect(
        externalLaunchRouteFor(
          Uri.parse('tg://unknown_feature?x=1'),
          platform: TargetPlatform.android,
          isWeb: false,
          onOhos: true,
        ),
        ExternalLaunchRoute.notice,
      );
    });

    test('other links and other platforms keep the generic launch', () {
      expect(
        externalLaunchMustBypassMithka(
          Uri.parse('https://example.com/'),
          platform: TargetPlatform.android,
          isWeb: false,
          onOhos: false,
        ),
        isFalse,
      );
      for (final platform in const [
        TargetPlatform.iOS,
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          externalLaunchRouteFor(
            Uri.parse('https://t.me/blog'),
            platform: platform,
            isWeb: false,
            onOhos: false,
          ),
          ExternalLaunchRoute.generic,
          reason: '$platform',
        );
      }
      // Mithka registers no tg:// handler on Linux and Windows.
      for (final platform in const [
        TargetPlatform.windows,
        TargetPlatform.linux,
      ]) {
        expect(
          externalLaunchRouteFor(
            Uri.parse('tg://unknown_feature?x=1'),
            platform: platform,
            isWeb: false,
            onOhos: false,
          ),
          ExternalLaunchRoute.generic,
          reason: '$platform',
        );
      }
      expect(
        externalLaunchRouteFor(
          Uri.parse('tg://unknown_feature?x=1'),
          platform: TargetPlatform.android,
          isWeb: true,
        ),
        ExternalLaunchRoute.generic,
      );
    });
  });

  group('signed-out queue', () {
    test('opens immediately only once an account is ready', () {
      expect(
        deepLinkGateFor(const AuthReady(), locked: false, needsAccount: true),
        DeepLinkGate.open,
      );
      expect(
        deepLinkGateFor(
          const AuthWaitPhoneNumber(),
          locked: false,
          needsAccount: true,
        ),
        DeepLinkGate.logIn,
      );
      expect(
        deepLinkGateFor(
          const AuthWaitQrCode('tg://login?token=x'),
          locked: false,
          needsAccount: true,
        ),
        DeepLinkGate.logIn,
      );
    });

    test('waits through startup, account reloads and the app lock', () {
      for (final step in const <AuthStep>[
        AuthInitializing(),
        AuthReloading(),
        AuthLoggingOut(),
        AuthClosed(),
      ]) {
        expect(
          deepLinkGateFor(step, locked: false, needsAccount: true),
          DeepLinkGate.wait,
          reason: '$step',
        );
      }
      expect(
        deepLinkGateFor(const AuthReady(), locked: true, needsAccount: true),
        DeepLinkGate.wait,
      );
    });

    test('waits until the app is in front, then opens', () {
      for (final state in const [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.detached,
      ]) {
        expect(deepLinkAppInForeground(state), isFalse, reason: '$state');
        // Notices (needsAccount: false) wait for the foreground too, so they
        // are not spent while the app is still coming to the front.
        expect(
          deepLinkGateFor(
            const AuthReady(),
            locked: false,
            needsAccount: false,
            foreground: deepLinkAppInForeground(state),
          ),
          DeepLinkGate.wait,
          reason: '$state',
        );
        expect(
          deepLinkGateFor(
            const AuthWaitPhoneNumber(),
            locked: false,
            needsAccount: true,
            foreground: deepLinkAppInForeground(state),
          ),
          DeepLinkGate.wait,
          reason: '$state',
        );
      }
      expect(deepLinkAppInForeground(AppLifecycleState.resumed), isTrue);
      expect(deepLinkAppInForeground(null), isTrue);
      expect(
        deepLinkGateFor(
          const AuthReady(),
          locked: false,
          needsAccount: true,
          foreground: deepLinkAppInForeground(AppLifecycleState.resumed),
        ),
        DeepLinkGate.open,
      );
    });

    test('proxy links open on the login screen', () {
      expect(
        deepLinkGateFor(
          const AuthWaitPhoneNumber(),
          locked: false,
          needsAccount: false,
        ),
        DeepLinkGate.open,
      );
    });
  });
}
