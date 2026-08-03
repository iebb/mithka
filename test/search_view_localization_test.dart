import 'dart:convert';

import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mithka/chat/telegram_mini_app_recents.dart';
import 'package:mithka/chats/mini_apps_page.dart';
import 'package:mithka/chats/search_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('desktop child search starts with its query and no root back', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SearchView(initialQuery: 'mao', showBackButton: false),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    final field = tester.widget<CupertinoTextField>(
      find.byType(CupertinoTextField),
    );
    expect(field.controller?.text, 'mao');
    expect(find.byKey(const ValueKey('search-view-back')), findsNothing);
  });

  test('untitled and legacy Mini App recents follow the active locale', () {
    Intl.withLocale('zh-Hans', () {
      for (final title in ['', 'Mini App']) {
        final recent = TelegramMiniAppRecent(
          title: title,
          url: 'https://example.com/app',
          botUserId: 1,
          chatId: 2,
          updatedAt: 3,
        );
        expect(recent.launchTitle, '小程序');
        expect(recent.displayTitle, '小程序');
      }
    });
  });

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
    final storageKey = TelegramMiniAppRecents.storageKeyForTesting(
      slot: 0,
      clientId: 0,
    );
    SharedPreferences.setMockInitialValues({
      storageKey: jsonEncode([
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
