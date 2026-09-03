import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/link_browser.dart';
import 'package:mithka/chat/link_handler.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('link parsing', () {
    test('adds HTTPS only when a scheme is genuinely absent', () {
      expect(
        parseLinkUri('example.com/path')?.toString(),
        'https://example.com/path',
      );
      expect(
        parseLinkUri('example.com:8443/path')?.toString(),
        'https://example.com:8443/path',
      );
      expect(
        parseLinkUri('//example.com/path')?.toString(),
        'https://example.com/path',
      );
    });

    test('preserves non-browser schemes used by message entities', () {
      expect(parseLinkUri('mailto:hello@example.com')?.scheme, 'mailto');
      expect(parseLinkUri('tel:+810000000000')?.scheme, 'tel');
      expect(parseLinkUri('tg://resolve?domain=mithka')?.scheme, 'tg');
    });
  });

  group('internal browser eligibility', () {
    test('accepts only authenticated HTTPS origins', () {
      expect(
        internalBrowserCanOpen(Uri.parse('https://safe.example/path?q=1')),
        isTrue,
      );
      expect(
        internalBrowserCanOpen(Uri.parse('https://safe.example:8443/path')),
        isTrue,
      );
      expect(
        internalBrowserCanOpen(Uri.parse('http://safe.example/path')),
        isFalse,
      );
      expect(
        internalBrowserCanOpen(Uri.parse('https://user@safe.example/path')),
        isFalse,
      );
      expect(
        internalBrowserCanOpen(Uri.parse('https://safe.example:99999/path')),
        isFalse,
      );
      expect(
        internalBrowserCanOpen(Uri.parse('data:text/html,hello')),
        isFalse,
      );
    });

    test('matches the installed platform implementations', () {
      for (final platform in const [
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      ]) {
        expect(
          internalBrowserSupported(platform: platform, isWeb: false),
          isTrue,
        );
      }
      for (final platform in const [
        TargetPlatform.fuchsia,
        TargetPlatform.linux,
        TargetPlatform.windows,
      ]) {
        expect(
          internalBrowserSupported(platform: platform, isWeb: false),
          isFalse,
        );
      }
      expect(
        internalBrowserSupported(platform: TargetPlatform.android, isWeb: true),
        isFalse,
      );
    });

    test('resolves saved choices without unsafe silent WebView fallback', () {
      final uri = Uri.parse('https://safe.example/path');
      expect(
        linkOpenTargetFor(
          mode: LinkOpenMode.defaultBrowser,
          uri: uri,
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        LinkOpenTarget.defaultBrowser,
      );
      expect(
        linkOpenTargetFor(
          mode: LinkOpenMode.internalBrowser,
          uri: uri,
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        LinkOpenTarget.internalBrowser,
      );
      expect(
        linkOpenTargetFor(
          mode: LinkOpenMode.askEveryTime,
          uri: uri,
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        isNull,
      );
      expect(
        linkOpenTargetFor(
          mode: LinkOpenMode.internalBrowser,
          uri: uri,
          platform: TargetPlatform.windows,
          isWeb: false,
        ),
        LinkOpenTarget.defaultBrowser,
      );
      expect(
        linkOpenTargetFor(
          mode: LinkOpenMode.internalBrowser,
          uri: Uri.parse('http://safe.example'),
          platform: TargetPlatform.iOS,
          isWeb: false,
        ),
        LinkOpenTarget.defaultBrowser,
      );
    });
  });

  test('internal navigation keeps unsafe schemes outside the WebView', () {
    expect(
      internalBrowserNavigationAction(
        url: 'https://other.example/path',
        isMainFrame: true,
      ),
      InternalBrowserNavigationAction.navigate,
    );
    for (final url in const [
      'http://other.example/path',
      'mailto:hello@example.com',
      'tel:+810000000000',
    ]) {
      expect(
        internalBrowserNavigationAction(url: url, isMainFrame: true),
        InternalBrowserNavigationAction.openExternally,
      );
    }
    expect(
      internalBrowserNavigationAction(
        url: 'tg://resolve?domain=mithka',
        isMainFrame: true,
      ),
      InternalBrowserNavigationAction.openInApp,
    );
    for (final url in const [
      'data:text/html,hello',
      'javascript:alert(1)',
      'file:///tmp/private',
      'about:blank',
    ]) {
      expect(
        internalBrowserNavigationAction(url: url, isMainFrame: true),
        InternalBrowserNavigationAction.block,
      );
    }
    expect(
      internalBrowserNavigationAction(
        url: 'mailto:hello@example.com',
        isMainFrame: false,
      ),
      InternalBrowserNavigationAction.block,
    );

    expect(
      linkCanOpenExternally(Uri.parse('mailto:hello@example.com')),
      isTrue,
    );
    expect(linkCanOpenExternally(Uri.parse('custom-app://open/1')), isTrue);
    expect(linkCanOpenExternally(Uri.parse('javascript:alert(1)')), isFalse);
    expect(linkCanOpenExternally(Uri.parse('file:///tmp/private')), isFalse);
  });

  test(
    'browser preference defaults safely and persists valid choices',
    () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final controller = ThemeController(preferences);
      addTearDown(controller.dispose);

      expect(controller.linkOpenMode, LinkOpenMode.defaultBrowser);
      controller.linkOpenMode = LinkOpenMode.askEveryTime;
      expect(preferences.getString('linkOpenMode.v1'), 'askEveryTime');

      final restored = ThemeController(preferences);
      addTearDown(restored.dispose);
      expect(restored.linkOpenMode, LinkOpenMode.askEveryTime);

      SharedPreferences.setMockInitialValues({'linkOpenMode.v1': 'retired'});
      final invalidPreferences = await SharedPreferences.getInstance();
      final invalid = ThemeController(invalidPreferences);
      addTearDown(invalid.dispose);
      expect(invalid.linkOpenMode, LinkOpenMode.defaultBrowser);
    },
  );

  testWidgets('ask mode presents both browser choices for an HTTPS link', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'linkOpenMode.v1': LinkOpenMode.askEveryTime.name,
    });
    final preferences = await SharedPreferences.getInstance();
    final controller = ThemeController(preferences);
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: controller,
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate],
          theme: ThemeData(
            platform: TargetPlatform.iOS,
            extensions: [AppColors.light],
          ),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () =>
                    unawaited(openLink(context, 'https://example.com/safe')),
                child: const Text('Open link'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open link'));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('link-browser-chooser')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('link-browser-open-internal')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('link-browser-open-default')),
      findsOneWidget,
    );

    // The default-browser launcher is allowed to be unavailable in a widget
    // test; the chooser must still return and dismiss cleanly.
    await tester.tap(find.byKey(const ValueKey('link-browser-open-default')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('link-browser-chooser')), findsNothing);
  });

  test('internal browser controller has no privileged bridge', () {
    final source = File(
      'lib/chat/internal_browser_view.dart',
    ).readAsStringSync();
    expect(source, contains('onPermissionRequest:'));
    expect(source, contains('request.deny()'));
    expect(source, contains('setAllowFileAccess(false)'));
    expect(source, contains('setAllowContentAccess(false)'));
    expect(source, contains('MixedContentMode.neverAllow'));
    expect(source, contains('error.cancel()'));
    expect(source, isNot(contains('addJavaScriptChannel')));
  });
}
