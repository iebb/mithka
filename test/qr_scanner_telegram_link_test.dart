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

Future<List<String>> _openScannedLink(
  WidgetTester tester,
  String url, {
  required bool keepTelegramInApp,
}) async {
  final launched = <String>[];
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    _urlLauncherChannel,
    (call) async {
      final arguments = call.arguments;
      if (arguments is Map && arguments['url'] is String) {
        launched.add(arguments['url'] as String);
      }
      return true;
    },
  );
  addTearDown(
    () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      _urlLauncherChannel,
      null,
    ),
  );

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
        theme: ThemeData(
          platform: TargetPlatform.iOS,
          extensions: [AppColors.light],
        ),
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
  // Let the TDLib lookup fail over to the fallback, then let any toast finish.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(seconds: 1));
  }
  return launched;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('a scanned tg:// link Mithka cannot route stays in the app', (
    tester,
  ) async {
    final launched = await _openScannedLink(
      tester,
      'tg://mithka-unrouted?value=1',
      keepTelegramInApp: true,
    );
    expect(launched, isEmpty);
  });

  testWidgets('tapped tg:// links keep their external fallback', (
    tester,
  ) async {
    final launched = await _openScannedLink(
      tester,
      'tg://mithka-unrouted?value=1',
      keepTelegramInApp: false,
    );
    expect(launched, ['tg://mithka-unrouted?value=1']);
  });
}
