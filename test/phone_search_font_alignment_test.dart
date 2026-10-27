import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoTextField;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/scaled_app_view.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/search_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

void main() {
  final updates = StreamController<Map<String, dynamic>>.broadcast();
  setUpAll(() {
    L10nFixtures.load().install();
    AppStrings.setLocale(const Locale('en'));
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => switch (request['@type']) {
          'getMe' => {'@type': 'user', 'id': 1, 'first_name': 'Fixture'},
          'getChats' => {
            '@type': 'chats',
            'chat_ids': <int>[],
            'total_count': 0,
          },
          _ => {'@type': 'ok'},
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  Future<void> pump(WidgetTester tester, Widget child, double os) async {
    SharedPreferences.setMockInitialValues({'communitiesEnabled': false});
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          theme: ThemeData(extensions: [AppColors.light]),
          builder: (context, route) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(os)),
            child: ScaledAppView(
              textScale: .9,
              interfaceScale: 1,
              child: route!,
            ),
          ),
          home: Scaffold(body: child),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  }

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    for (final os in [.823, 1.0, 2.0]) {
      testWidgets(
        'actual $platform chat-list search preserves geometry at OS $os',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          try {
            await pump(tester, const ChatListView(), os);
            final search = find.byKey(
              const ValueKey('chat-list-inline-search'),
            );
            final label = find.descendant(
              of: search,
              matching: find.byType(Text),
            );
            final text = tester.widget<Text>(label);
            final expectedFont = platform == TargetPlatform.macOS ? 14.0 : 16.0;
            expect(text.style!.fontSize, expectedFont);
            final rich = find.descendant(
              of: label,
              matching: find.byType(RichText),
            );
            final paragraph = tester.renderObject<RenderParagraph>(rich);
            final expectedOs = platform == TargetPlatform.macOS
                ? os
                : (os < 1 ? 1.0 : os);
            expect(
              paragraph.textScaler.scale(expectedFont),
              closeTo(expectedFont * expectedOs, 1e-6),
            );
            final field = find.descendant(
              of: search,
              matching: find.byWidgetPredicate(
                (w) =>
                    w is Container &&
                    w.constraints?.maxHeight == AppMetric.searchHeight,
              ),
            );
            expect(tester.getSize(field).height, 36);
            final icon = tester.widget<AppIcon>(
              find.descendant(of: search, matching: find.byType(AppIcon)),
            );
            expect(icon.size, 16);
            await dispose(tester);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
      testWidgets(
        'actual $platform search placeholder and typed text at OS $os',
        (tester) async {
          debugDefaultTargetPlatformOverride = platform;
          try {
            await pump(tester, const SearchView(), os);
            var field = tester.widget<CupertinoTextField>(
              find.byType(CupertinoTextField),
            );
            final expectedFont = platform == TargetPlatform.macOS ? 15.0 : 16.0;
            expect(field.style!.fontSize, expectedFont);
            expect(field.placeholderStyle!.fontSize, expectedFont);
            final placeholder = find.text(field.placeholder!);
            final paragraph = tester.renderObject<RenderParagraph>(
              find.descendant(of: placeholder, matching: find.byType(RichText)),
            );
            final expectedOs = platform == TargetPlatform.macOS
                ? os
                : (os < 1 ? 1.0 : os);
            expect(
              paragraph.textScaler.scale(expectedFont),
              closeTo(expectedFont * expectedOs, 1e-6),
            );
            await tester.enterText(
              find.byType(CupertinoTextField),
              'PUBLIC FONT FIXTURE',
            );
            await tester.pump(const Duration(milliseconds: 300));
            field = tester.widget<CupertinoTextField>(
              find.byType(CupertinoTextField),
            );
            expect(field.controller!.text, 'PUBLIC FONT FIXTURE');
            final editable = tester
                .state<EditableTextState>(find.byType(EditableText))
                .renderEditable;
            expect(
              editable.textScaler.scale(expectedFont),
              closeTo(expectedFont * expectedOs, 1e-6),
            );
            await dispose(tester);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        },
      );
    }
  }
}
