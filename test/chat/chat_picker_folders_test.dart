//
//  chat_picker_folders_test.dart
//
//  A forward picker offers the account's chat folders as tabs. Choosing one
//  narrows the destinations to that folder's own list, "All" restores the
//  whole account, and a picker that is not forwarding keeps its plain list.
//

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_picker_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/ai_translation/translation_controller.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart' show ChatSummary;
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/l10n_fixtures.dart';

const _workFolderId = 7;
const _emptyFolderId = 8;
const _inboxChatId = 42;
const _workChatId = 43;
const _lateWorkChatId = 44;
const _contactUserId = 77;

/// Whether the account has its folder yet. A chat position inside a folder is
/// itself proof the folder exists, so a folderless account must not report one.
bool _accountHasFolder = true;

/// How many pages of the folder TDLib has been asked for, and the page from
/// which chat 44 is part of it. Zero keeps the folder to chat 43 alone.
int _folderPagesLoaded = 0;
int _lateChatFromPage = 0;

/// Chat 42 sits in the Main list only; chats 43 and 44 are also filed under
/// the folder, 44 only on a later page of it.
Map<String, dynamic> _chatJson(int chatId) => {
  '@type': 'chat',
  'id': chatId,
  'title': switch (chatId) {
    _workChatId => 'Work mate',
    _lateWorkChatId => 'Late arrival',
    _ => 'Inbox friend',
  },
  'type': {'@type': 'chatTypePrivate', 'user_id': chatId},
  'last_read_inbox_message_id': 10,
  'unread_count': 0,
  'permissions': {'can_send_basic_messages': true},
  'positions': [
    {
      '@type': 'chatPosition',
      'list': {'@type': 'chatListMain'},
      'order': '${999999 - chatId}',
      'is_pinned': false,
    },
    if (chatId != _inboxChatId && _accountHasFolder)
      {
        '@type': 'chatPosition',
        'list': {'@type': 'chatListFolder', 'chat_folder_id': _workFolderId},
        'order': '500',
        'is_pinned': false,
      },
  ],
};

/// Stands in for tdjson; only the registry calls the picker path makes.
class _FakeBindings implements TdBindings {
  int _nextClientId = 100;

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {
    jsonDecode(request);
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
  late int slot;
  late int clientId;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('mithka-picker-folders');
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    client = TdClient.shared;
    client.prepareForTesting(
      prefs: prefs,
      supportDir: supportDir.path,
      bindings: _FakeBindings(),
      queryOverride: (request, _) async {
        final list = request['chat_list'];
        final folderId = list is Map<String, dynamic>
            ? list['chat_folder_id']
            : null;
        switch (request['@type']) {
          case 'loadChats':
            if (folderId == _workFolderId) _folderPagesLoaded++;
            return {'@type': 'ok'};
          case 'getChats':
            final lateChatLoaded =
                _lateChatFromPage > 0 &&
                _folderPagesLoaded >= _lateChatFromPage;
            final ids = switch ((list as Map<String, dynamic>)['@type']) {
              'chatListMain' => const [_inboxChatId, _workChatId],
              'chatListFolder' when folderId == _workFolderId => [
                _workChatId,
                if (lateChatLoaded) _lateWorkChatId,
              ],
              _ => const <int>[],
            };
            return {
              '@type': 'chats',
              'total_count': ids.length,
              'chat_ids': ids,
            };
          case 'getChat':
            return _chatJson(request['chat_id'] as int);
          case 'getContacts':
            return {
              '@type': 'users',
              'total_count': 1,
              'user_ids': const [_contactUserId],
            };
          case 'getUser':
            return {
              '@type': 'user',
              'id': request['user_id'],
              'first_name': 'Contact',
              'last_name': 'Only',
              'is_contact': true,
              'type': {'@type': 'userTypeRegular'},
            };
          default:
            return {'@type': 'ok'};
        }
      },
    );
    slot = client.addSlot();
    clientId = client.clientId(slot)!;
    client.setActive(slot);
  });
  tearDownAll(() async {
    await client.closeProxy();
    await supportDir.delete(recursive: true);
  });

  late ThemeController theme;
  late TranslationController translation;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    theme = ThemeController(await SharedPreferences.getInstance());
    translation = TranslationController(await SharedPreferences.getInstance());
    client.clearChatFoldersForTesting();
    _accountHasFolder = true;
    _folderPagesLoaded = 0;
    _lateChatFromPage = 0;
  });
  tearDown(() {
    theme.dispose();
    translation.dispose();
  });

  void pushWorkFolder() {
    client.routeUpdateForTesting({
      '@type': 'updateChatFolders',
      '@client_id': clientId,
      'chat_folders': [
        {
          '@type': 'chatFolderInfo',
          'id': _workFolderId,
          'name': {
            '@type': 'chatFolderName',
            'text': {'@type': 'formattedText', 'text': 'Work'},
          },
          'icon': {'@type': 'chatFolderIcon', 'name': 'Work'},
        },
        {
          '@type': 'chatFolderInfo',
          'id': _emptyFolderId,
          'name': {
            '@type': 'chatFolderName',
            'text': {'@type': 'formattedText', 'text': 'Empty'},
          },
          'icon': {'@type': 'chatFolderIcon', 'name': 'Custom'},
        },
      ],
    });
  }

  /// Unmounts the picker and drains the list model's deferred warm-up timers
  /// (`_deferWarmCaches` schedules 1.5 s and 5 s Futures that outlive dispose).
  Future<void> tearDownPicker(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Opens the picker from a host route and returns what it pops with.
  Future<Future<Object?>> pumpPicker(
    WidgetTester tester, {
    required bool forwarding,
    bool? showFolders,
  }) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<ThemeController>.value(value: theme),
          ChangeNotifierProvider<TranslationController>.value(
            value: translation,
          ),
        ],
        child: MaterialApp(
          navigatorKey: navigatorKey,
          theme: ThemeData(
            extensions: [AppColors.light],
            platform: TargetPlatform.iOS,
          ),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const SizedBox.shrink(),
        ),
      ),
    );
    final popped = navigatorKey.currentState!.push<Object?>(
      MaterialPageRoute(
        builder: (_) => ChatPickerView(
          accountSlot: slot,
          showForwardOptions: forwarding,
          showFolders: showFolders,
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Inbox friend'), findsOneWidget);
    expect(find.text('Work mate'), findsOneWidget);
    return popped;
  }

  final allTab = find.byKey(const ValueKey('chat-picker-folder-all'));
  final workTab = find.byKey(
    const ValueKey('chat-picker-folder-$_workFolderId'),
  );
  final emptyTab = find.byKey(
    const ValueKey('chat-picker-folder-$_emptyFolderId'),
  );

  testWidgets('a forward picker narrows its destinations to a chosen folder', (
    tester,
  ) async {
    pushWorkFolder();
    final popped = await pumpPicker(tester, forwarding: true);

    expect(allTab, findsOneWidget);
    expect(workTab, findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(find.text('Contact Only'), findsOneWidget);

    await tester.tap(workTab);
    await settle(tester);
    expect(find.text('Work mate'), findsOneWidget);
    expect(find.text('Inbox friend'), findsNothing);
    expect(
      find.text('Contact Only'),
      findsNothing,
      reason: 'a contact without a chat belongs to no folder',
    );

    await tester.tap(allTab);
    await settle(tester);
    expect(find.text('Inbox friend'), findsOneWidget);
    expect(find.text('Work mate'), findsOneWidget);
    expect(find.text('Contact Only'), findsOneWidget);

    await tester.tap(workTab);
    await settle(tester);
    await tester.tap(find.text('Work mate'));
    await settle(tester);
    final result = await popped;
    expect(result, isA<ChatPickerResult>());
    expect((result! as ChatPickerResult).chat.id, _workChatId);

    await tearDownPicker(tester);
  });

  testWidgets('search stays inside the chosen folder', (tester) async {
    pushWorkFolder();
    await pumpPicker(tester, forwarding: true);

    await tester.tap(workTab);
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'friend');
    await settle(tester);
    expect(find.text('Inbox friend'), findsNothing);
    expect(find.text('Work mate'), findsNothing);
    expect(find.text('No chats found'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'mate');
    await settle(tester);
    expect(find.text('Work mate'), findsOneWidget);
    expect(find.text('No chats found'), findsNothing);

    await tearDownPicker(tester);
  });

  testWidgets('a folder without chats says so instead of staying blank', (
    tester,
  ) async {
    pushWorkFolder();
    await pumpPicker(tester, forwarding: true);
    expect(find.text('No chats found'), findsNothing);

    await tester.tap(emptyTab);
    await settle(tester);
    expect(find.text('Inbox friend'), findsNothing);
    expect(find.text('Work mate'), findsNothing);
    expect(find.text('No chats found'), findsOneWidget);

    await tester.tap(workTab);
    await settle(tester);
    expect(find.text('Work mate'), findsOneWidget);
    expect(find.text('No chats found'), findsNothing);

    await tearDownPicker(tester);
  });

  testWidgets('a folder too short to scroll still pages in its later chats', (
    tester,
  ) async {
    pushWorkFolder();
    // The second page of the folder brings a chat the first one did not.
    _lateChatFromPage = 2;
    await pumpPicker(tester, forwarding: true);

    await tester.tap(workTab);
    await settle(tester);
    expect(find.text('Work mate'), findsOneWidget);
    expect(
      find.text('Late arrival'),
      findsOneWidget,
      reason: 'one row cannot be scrolled, so the picker pages on its own',
    );

    final pagesAfterSettling = _folderPagesLoaded;
    await settle(tester);
    expect(
      _folderPagesLoaded,
      pagesAfterSettling,
      reason: 'a page that adds no chat ends the run',
    );
    expect(pagesAfterSettling, lessThanOrEqualTo(4));

    await tearDownPicker(tester);
  });

  testWidgets('the tabs stay away without folders or outside forwarding', (
    tester,
  ) async {
    _accountHasFolder = false;
    await pumpPicker(tester, forwarding: true);
    expect(allTab, findsNothing, reason: 'the account has no folder yet');

    pushWorkFolder();
    await settle(tester);
    expect(allTab, findsOneWidget, reason: 'a new folder appears live');
    expect(workTab, findsOneWidget);
    await tearDownPicker(tester);

    _accountHasFolder = true;
    await pumpPicker(tester, forwarding: false);
    expect(allTab, findsNothing);
    expect(workTab, findsNothing);
    await tearDownPicker(tester);
  });

  testWidgets('a share picker opts into folders and still returns the chat', (
    tester,
  ) async {
    pushWorkFolder();
    final popped = await pumpPicker(
      tester,
      forwarding: false,
      showFolders: true,
    );
    expect(allTab, findsOneWidget);

    await tester.tap(workTab);
    await settle(tester);
    expect(find.text('Inbox friend'), findsNothing);
    await tester.tap(find.text('Work mate'));
    await settle(tester);
    final result = await popped;
    expect(result, isA<ChatSummary>());
    expect((result! as ChatSummary).id, _workChatId);

    await tearDownPicker(tester);
  });
}
