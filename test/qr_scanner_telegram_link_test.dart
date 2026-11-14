import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/link_handler.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _urlLauncherChannel = MethodChannel('plugins.flutter.io/url_launcher');
const _externalLinksChannel = MethodChannel('mithka/external_links');

const _unroutedLink = 'tg://mithka-unrouted?value=1';

/// What the native side of `mithka/external_links` does in a test.
enum _Bridge {
  /// Another app took the link.
  opened,

  /// No app other than Mithka handles the link.
  noOtherApp,

  /// No plugin answers the channel (MissingPluginException).
  missing,
}

class _LinkOutcome {
  final launched = <String>[];
  final bridged = <String>[];
  var noticeShown = false;
}

/// Opens [url] the way a tap (or, with [keepTelegramInApp], a QR scan) does,
/// on the platform set by the test variant. Every channel a launch can use is
/// mocked: an unmocked channel never answers inside the test's fake clock.
Future<_LinkOutcome> _openLink(
  WidgetTester tester,
  String url, {
  required bool keepTelegramInApp,
  _Bridge bridge = _Bridge.opened,
}) async {
  final outcome = _LinkOutcome();
  final messenger = tester.binding.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(_urlLauncherChannel, (call) async {
    final arguments = call.arguments;
    if (arguments is Map && arguments['url'] is String) {
      outcome.launched.add(arguments['url'] as String);
    }
    return true;
  });
  messenger.setMockMethodCallHandler(_externalLinksChannel, (call) async {
    if (call.method != 'openExternally') return null;
    final arguments = call.arguments;
    if (arguments is Map && arguments['url'] is String) {
      outcome.bridged.add(arguments['url'] as String);
    }
    return switch (bridge) {
      _Bridge.opened => true,
      _Bridge.noOtherApp => false,
      _Bridge.missing => throw MissingPluginException(),
    };
  });
  addTearDown(() {
    messenger.setMockMethodCallHandler(_urlLauncherChannel, null);
    messenger.setMockMethodCallHandler(_externalLinksChannel, null);
  });

  SharedPreferences.setMockInitialValues({});
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
        theme: ThemeData(extensions: [AppColors.light]),
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => unawaited(
                openLink(context, url, keepTelegramInApp: keepTelegramInApp),
              ),
              child: const Text('Open link'),
            ),
          ),
        ),
      ),
    ),
  );

  await tester.tap(find.text('Open link'));
  // Let the TDLib lookup fail over to the fallback, then let any toast
  // appear and finish, watching for the notice on the way.
  final notice = AppStrings.t(AppStringKeys.linkHandlerUnsupportedTelegramLink);
  for (var i = 0; i < 30; i++) {
    await tester.pump(const Duration(milliseconds: 200));
    if (find.text(notice).evaluate().isNotEmpty) outcome.noticeShown = true;
  }
  return outcome;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'a scanned tg:// link Mithka cannot route stays in the app',
    (tester) async {
      final outcome = await _openLink(
        tester,
        _unroutedLink,
        keepTelegramInApp: true,
      );
      expect(outcome.launched, isEmpty);
      expect(outcome.bridged, isEmpty);
      expect(outcome.noticeShown, isTrue);
    },
    variant: const TargetPlatformVariant({
      TargetPlatform.android,
      TargetPlatform.iOS,
      TargetPlatform.macOS,
    }),
  );

  // Mithka claims tg:// itself, so a tapped tg:// link it cannot route is
  // offered to other apps through the native bridge, which excludes Mithka.
  // url_launcher is never used there: the system could pick Mithka again.
  testWidgets(
    'tapped tg:// links go to another app through the bridge',
    (tester) async {
      final outcome = await _openLink(
        tester,
        _unroutedLink,
        keepTelegramInApp: false,
      );
      expect(outcome.bridged, [_unroutedLink]);
      expect(outcome.launched, isEmpty);
      expect(outcome.noticeShown, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  testWidgets(
    'macOS hands tapped tg:// links to the bridge too',
    (tester) async {
      final outcome = await _openLink(
        tester,
        _unroutedLink,
        keepTelegramInApp: false,
      );
      expect(outcome.bridged, [_unroutedLink]);
      expect(outcome.launched, isEmpty);
      expect(outcome.noticeShown, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.macOS),
  );

  testWidgets(
    'a tg:// link no other app handles ends with a notice, not a loop',
    (tester) async {
      final outcome = await _openLink(
        tester,
        _unroutedLink,
        keepTelegramInApp: false,
        bridge: _Bridge.noOtherApp,
      );
      expect(outcome.bridged, [_unroutedLink]);
      expect(outcome.launched, isEmpty);
      expect(outcome.noticeShown, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  // Where Mithka claims tg://, a missing bridge must not fall back to
  // url_launcher: that is exactly the launch that could come back.
  testWidgets(
    'a missing bridge on Android ends with a notice, not url_launcher',
    (tester) async {
      final outcome = await _openLink(
        tester,
        _unroutedLink,
        keepTelegramInApp: false,
        bridge: _Bridge.missing,
      );
      expect(outcome.launched, isEmpty);
      expect(outcome.noticeShown, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );

  // iOS cannot exclude Mithka from tg:// handlers, so it never relaunches.
  testWidgets(
    'iOS shows a notice instead of relaunching tapped tg:// links',
    (tester) async {
      final outcome = await _openLink(
        tester,
        _unroutedLink,
        keepTelegramInApp: false,
      );
      expect(outcome.bridged, isEmpty);
      expect(outcome.launched, isEmpty);
      expect(outcome.noticeShown, isTrue);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  // Linux and Windows have no bridge and Mithka registers no tg:// handler
  // there, so url_launcher cannot bring the link back: it stays the fallback.
  testWidgets(
    'without a bridge or a Mithka tg:// handler, url_launcher opens it',
    (tester) async {
      final outcome = await _openLink(
        tester,
        _unroutedLink,
        keepTelegramInApp: false,
        bridge: _Bridge.missing,
      );
      expect(outcome.bridged, isEmpty);
      expect(outcome.launched, [_unroutedLink]);
      expect(outcome.noticeShown, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );
}
