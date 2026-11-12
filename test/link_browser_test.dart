import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/link_browser.dart';
import 'package:mithka/theme/theme_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

  test('internal browser controller has no privileged bridge', () {
    final source = File(
      'lib/chat/internal_browser_view.dart',
    ).readAsStringSync();
    // Web pages must never reach a native bridge or local files.
    expect(source, isNot(contains('addJavaScriptChannel')));
    expect(source, contains('setAllowFileAccess(false)'));
  });
}
