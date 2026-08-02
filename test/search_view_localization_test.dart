import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/mini_apps_page.dart';
import 'package:mithka/chats/search_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('Mini App terminology is localized in every non-English CJK locale', () {
    const expectedNames = {
      'ja': 'ミニアプリ',
      'ko': '미니 앱',
      'zhHans': '小程序',
      'zhHant': '迷你應用程式',
    };
    const visibleMiniAppKeys = [
      AppStringKeys.miniAppCannotStart,
      AppStringKeys.miniAppClose,
      AppStringKeys.miniAppName,
      AppStringKeys.miniAppNoMatches,
      AppStringKeys.miniAppRecentEmpty,
      AppStringKeys.miniAppReload,
    ];

    for (final entry in expectedNames.entries) {
      expect(
        AppStrings.tForLocale(entry.key, AppStringKeys.miniAppName),
        entry.value,
      );
      for (final key in visibleMiniAppKeys) {
        expect(
          AppStrings.tForLocale(entry.key, key),
          isNot(contains('Mini App')),
        );
      }
    }
  });

  testWidgets('search categories use concise localized plural labels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SearchView(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    for (final label in const [
      'Chats',
      'Mini Apps',
      'Messages',
      'Media',
      'Links',
      'Files',
      'Music',
      'Voice Messages',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Mini App'), findsNothing);
    expect(find.text('Message'), findsNothing);
    expect(find.text('File'), findsNothing);
  });

  testWidgets('search categories translate Mini Apps in Simplified Chinese', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SearchView(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('小程序'), findsOneWidget);
    expect(find.text('Mini App'), findsNothing);
    expect(find.text('Mini Apps'), findsNothing);
  });

  testWidgets('Mini App result heading follows the selected locale', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'telegramMiniAppRecents.v1': jsonEncode([
        {
          'title': '演示小程序',
          'url': 'https://example.com/app',
          'botUserId': 10,
          'chatId': 20,
          'updatedAt': 30,
        },
      ]),
    });

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: MiniAppsSearchTab(query: '演示')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('小程序'), findsOneWidget);
    expect(find.text('Mini App'), findsNothing);
  });
}
