//
//  chat_folder_management_view_test.dart
//
//  文件夹标签 is no longer gated: the switch works for every account. Telegram
//  only lets a Premium account write it to the server, so a non-Premium one
//  keeps its choice on this device and the rows still draw the tags.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_folder_tag_controller.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/chat_folder_management_view.dart';
import 'package:mithka/settings/chat_folder_service.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<ChatFolderTagController> pumpView(
    WidgetTester tester,
    _FolderTagHarness harness, {
    Map<String, Object> initialPreferences = const {},
  }) async {
    addTearDown(harness.dispose);
    SharedPreferences.setMockInitialValues(initialPreferences);
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final tags = ChatFolderTagController(
      preferences,
      query: harness.query,
      folderUpdates: harness.folders.stream,
    );
    addTearDown(tags.dispose);
    await tags.refresh();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<ChatFolderTagController>.value(value: tags),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [AppLocalizations.delegate],
          theme: ThemeData(extensions: [AppColors.light]),
          home: ChatFolderManagementView(
            service: ChatFolderService(query: harness.query),
            updates: harness.updates.stream,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tags;
  }

  testWidgets('a non-Premium account gets a working, unlocked toggle', (
    tester,
  ) async {
    final harness = _FolderTagHarness(isPremium: false);
    final tags = await pumpView(tester, harness);

    expect(find.byKey(const ValueKey('tags-title')), findsOneWidget);
    expect(find.byKey(const ValueKey('folder-tags')), findsOneWidget);
    final row = find.byType(SettingsSwitchRow);
    expect(tester.widget<SettingsSwitchRow>(row).enabled, isTrue);
    expect(tester.widget<SettingsSwitchRow>(row).value, isFalse);

    await tester.tap(row);
    await tester.pumpAndSettle();

    expect(tester.widget<SettingsSwitchRow>(row).value, isTrue);
    expect(tags.enabled, isTrue);
    // The server setting is Premium-only, so nothing was sent.
    expect(harness.toggleRequests, isEmpty);
  });

  testWidgets('a non-Premium choice is kept on this device', (tester) async {
    final harness = _FolderTagHarness(isPremium: false);
    await pumpView(tester, harness);

    await tester.tap(find.byType(SettingsSwitchRow));
    await tester.pumpAndSettle();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(ChatFolderTagController.preferenceKey), isTrue);
  });

  testWidgets('a stored preference survives the next launch', (tester) async {
    final harness = _FolderTagHarness(isPremium: false);
    final tags = await pumpView(
      tester,
      harness,
      initialPreferences: const {ChatFolderTagController.preferenceKey: true},
    );

    expect(tags.enabled, isTrue);
    expect(
      tester.widget<SettingsSwitchRow>(find.byType(SettingsSwitchRow)).value,
      isTrue,
    );
  });

  testWidgets('a Premium account also writes the setting to the server', (
    tester,
  ) async {
    final harness = _FolderTagHarness(isPremium: true);
    await pumpView(tester, harness);

    await tester.tap(find.byType(SettingsSwitchRow));
    await tester.pumpAndSettle();

    expect(harness.toggleRequests, hasLength(1));
    expect(harness.toggleRequests.single['are_tags_enabled'], isTrue);
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool(ChatFolderTagController.preferenceKey), isTrue);
  });

  testWidgets('a refused server write does not undo the local choice', (
    tester,
  ) async {
    final harness = _FolderTagHarness(isPremium: true)
      ..toggleResponse = () async => throw StateError('toggle failed');
    final tags = await pumpView(tester, harness);

    await tester.tap(find.byType(SettingsSwitchRow));
    await tester.pumpAndSettle();

    expect(tags.enabled, isTrue);
    expect(
      tester.widget<SettingsSwitchRow>(find.byType(SettingsSwitchRow)).value,
      isTrue,
    );
    expect(harness.toggleRequests, hasLength(1));
  });

  testWidgets("a Premium account adopts the server's own value", (
    tester,
  ) async {
    final harness = _FolderTagHarness(isPremium: true);
    final tags = await pumpView(tester, harness);
    expect(tags.enabled, isFalse);

    harness.folders.add(const {
      '@type': 'updateChatFolders',
      'chat_folders': <Object>[],
      'are_tags_enabled': true,
    });
    await tester.pumpAndSettle();

    expect(tags.enabled, isTrue);
  });

  testWidgets("a non-Premium account ignores the server's always-off value", (
    tester,
  ) async {
    final harness = _FolderTagHarness(isPremium: false);
    final tags = await pumpView(
      tester,
      harness,
      initialPreferences: const {ChatFolderTagController.preferenceKey: true},
    );
    expect(tags.enabled, isTrue);

    harness.folders.add(const {
      '@type': 'updateChatFolders',
      'chat_folders': <Object>[],
      'are_tags_enabled': false,
    });
    await tester.pumpAndSettle();

    expect(tags.enabled, isTrue);
  });

  group('folder tags', () {
    test('read each folder name and its palette colour', () async {
      SharedPreferences.setMockInitialValues({
        ChatFolderTagController.preferenceKey: true,
      });
      final preferences = await SharedPreferences.getInstance();
      final folders = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(folders.close);
      final tags = ChatFolderTagController(
        preferences,
        query: (_) async => {'@type': 'ok'},
        folderUpdates: folders.stream,
        initialFolders: const {
          '@type': 'updateChatFolders',
          'chat_folders': [
            {
              'id': 3,
              'name': {
                'text': {'text': 'Personal'},
              },
              'color_id': 1,
            },
            {
              'id': 7,
              'name': {
                'text': {'text': 'Work'},
              },
              'color_id': -1,
            },
          ],
        },
      );
      addTearDown(tags.dispose);

      expect(tags.folders[3]!.title, 'Personal');
      expect(tags.folders[3]!.color, chatFolderTagColors[1]);
      // No colour of its own; the row falls back to the accent.
      expect(tags.folders[7]!.color, isNull);

      expect(tags.tagsFor({7, 3}).map((tag) => tag.title), [
        'Personal',
        'Work',
      ]);
      expect(tags.tagsFor(const <int>{}), isEmpty);
    });

    test('report nothing while the preference is off', () async {
      SharedPreferences.setMockInitialValues({});
      final preferences = await SharedPreferences.getInstance();
      final folders = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(folders.close);
      final tags = ChatFolderTagController(
        preferences,
        query: (_) async => {'@type': 'ok'},
        folderUpdates: folders.stream,
        initialFolders: const {
          '@type': 'updateChatFolders',
          'chat_folders': [
            {
              'id': 3,
              'name': {
                'text': {'text': 'Personal'},
              },
              'color_id': 1,
            },
          ],
        },
      );
      addTearDown(tags.dispose);

      expect(tags.tagsFor({3}), isEmpty);
    });
  });
}

class _FolderTagHarness {
  _FolderTagHarness({required this.isPremium});

  bool isPremium;
  final updates = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final folders = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final requests = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> Function()? toggleResponse;

  Iterable<Map<String, dynamic>> get toggleRequests =>
      requests.where((request) => request['@type'] == 'toggleChatFolderTags');

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    requests.add(request);
    return switch (request['@type']) {
      'getRecommendedChatFolders' => {
        '@type': 'recommendedChatFolders',
        'chat_folders': <Object>[],
      },
      'getOption' => {
        '@type': 'optionValueBoolean',
        'value': request['name'] == 'is_premium' && isPremium,
      },
      'toggleChatFolderTags' =>
        toggleResponse == null ? {'@type': 'ok'} : await toggleResponse!(),
      _ => {'@type': 'ok'},
    };
  }

  Future<void> dispose() =>
      Future.wait<void>([updates.close(), folders.close()]);
}
