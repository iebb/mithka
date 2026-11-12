//
//  chat_picker_owner_stream_test.dart
//
//  A picker pinned to an account must consume that account's live update
//  stream, not the foreground one. Chat ids are account-scoped, so a foreign
//  `updateNewChat` would otherwise add a selectable row whose id later gets
//  written through the pinned account, and a foreign `updateChatTitle` could
//  rename an unrelated row that shares the numeric id.
//

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_picker_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart' show ChatKind;
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

Map<String, dynamic> _chatJson(int chatId, String title) => {
  '@type': 'chat',
  'id': chatId,
  'title': title,
  'type': chatId < 0
      ? {
          '@type': 'chatTypeSupergroup',
          'supergroup_id': -chatId - 1000000000000,
          'is_channel': false,
        }
      : {'@type': 'chatTypePrivate', 'user_id': chatId.abs()},
  'last_read_inbox_message_id': 10,
  'unread_count': 0,
  'permissions': {'can_send_basic_messages': true},
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': 'chatListMain'},
      'order': '${999999 - chatId.abs()}',
      'is_pinned': false,
    },
  ],
};

/// Stands in for tdjson; only the registry calls the picker path makes.
class _FakeBindings implements TdBindings {
  final List<(int, Map<String, dynamic>)> sent = [];
  int _nextClientId = 100;

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {
    sent.add((clientId, jsonDecode(request) as Map<String, dynamic>));
  }

  @override
  void importSessionString(String sessionString, String destinationPath) {
    File(destinationPath).writeAsBytesSync(Uint8List.fromList(const [1]));
  }

  @override
  bool get supportsSessionStringBackup => false;

  @override
  bool get supportsTransferBoost => false;

  @override
  String? receive(double timeout) => throw UnimplementedError();

  @override
  Object? receiveJson(double timeout) => throw UnimplementedError();

  @override
  String? execute(String request) => throw UnimplementedError();

  @override
  String exportSessionString(
    String sourcePath, {
    required int apiId,
    required bool testMode,
    required int userId,
  }) => throw UnimplementedError();

  @override
  void configureTransferBoost({
    required int downloadChunkSize,
    required int downloadParallelism,
    required int uploadChunkSize,
    required int uploadParallelism,
  }) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  L10nFixtures.load().install();

  late Directory supportDir;
  late TdClient client;
  late int foregroundSlot;
  late int pinnedSlot;
  late int foregroundClientId;
  late int pinnedClientId;
  late List<(int, Map<String, dynamic>)> queries;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('mithka-picker-owner');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    client = TdClient.shared;
    client.prepareForTesting(
      prefs: prefs,
      supportDir: supportDir.path,
      bindings: _FakeBindings(),
      queryOverride: (request, clientId) async {
        queries.add((clientId, Map<String, dynamic>.from(request)));
        switch (request['@type']) {
          case 'loadChats':
          case 'getOption':
            return {'@type': 'ok'};
          case 'getChats':
            // Only the pinned account has a saved chat list.
            return clientId == pinnedClientId
                ? {
                    '@type': 'chats',
                    'total_count': 1,
                    'chat_ids': const [42],
                  }
                : {'@type': 'chats', 'total_count': 0, 'chat_ids': const []};
          case 'getChat':
            final id = request['chat_id'] as int;
            return _chatJson(id, id == 42 ? 'Pinned owner' : 'Fresh row');
          case 'getContacts':
            return {'@type': 'users', 'total_count': 0, 'user_ids': const []};
          default:
            return {'@type': 'ok'};
        }
      },
    );
    foregroundSlot = client.addSlot();
    pinnedSlot = client.addSlot();
    foregroundClientId = client.clientId(foregroundSlot)!;
    pinnedClientId = client.clientId(pinnedSlot)!;
    client.setActive(foregroundSlot);
  });
  tearDownAll(() async {
    await client.closeProxy();
    await supportDir.delete(recursive: true);
  });

  late ThemeController theme;
  late TranslationController translation;

  setUp(() async {
    queries = [];
    SharedPreferences.setMockInitialValues({});
    theme = ThemeController(await SharedPreferences.getInstance());
    translation = TranslationController(await SharedPreferences.getInstance());
  });
  tearDown(() {
    theme.dispose();
    translation.dispose();
  });

  /// Unmounts the picker and drains the list model's deferred warm-up timers
  /// (`_deferWarmCaches` schedules 1.5 s and 5 s Futures that outlive dispose).
  Future<void> tearDownPicker(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  }

  Future<void> pumpPicker(WidgetTester tester) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<TranslationController>.value(
            value: translation,
          ),
        ],
        child: MaterialApp(
          theme: ThemeData(
            extensions: [AppColors.light],
            platform: TargetPlatform.iOS,
          ),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: ChatPickerView(
            accountSlot: pinnedSlot,
            allowedKinds: const {ChatKind.privateChat},
          ),
        ),
      ),
    );
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(
      find.text('Pinned owner'),
      findsOneWidget,
      reason: 'the pinned account\'s own chat list must render',
    );
  }

  testWidgets('a foreground live chat never enters a pinned picker', (
    tester,
  ) async {
    await pumpPicker(tester);

    // The production router stamps the originating client on every update.
    client.routeUpdateForTesting({
      '@type': 'updateNewChat',
      '@client_id': foregroundClientId,
      'chat': _chatJson(3001, 'Foreground only'),
    });
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Foreground only'), findsNothing);
    expect(
      queries.where(
        (entry) =>
            entry.$1 == pinnedClientId &&
            entry.$2['@type'] == 'getChat' &&
            entry.$2['chat_id'] == 3001,
      ),
      isEmpty,
      reason: 'a foreign chat must not even be hydrated on the pinned client',
    );

    // Same update from the pinned account does arrive.
    client.routeUpdateForTesting({
      '@type': 'updateNewChat',
      '@client_id': pinnedClientId,
      'chat': _chatJson(43, 'Owner live chat'),
    });
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Owner live chat'), findsOneWidget);

    await tearDownPicker(tester);
  });
}
