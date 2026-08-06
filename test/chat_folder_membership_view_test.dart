import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_info_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<Widget> testApp(Widget child) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    return ChangeNotifierProvider(
      create: (_) => ThemeController(prefs),
      child: MaterialApp(home: child),
    );
  }

  testWidgets('load failure becomes an actionable empty state', (tester) async {
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      await testApp(
        ChatFolderMembershipView(
          chatId: 42,
          title: 'Test chat',
          query: (request) async {
            requests.add(request);
            throw StateError('offline');
          },
          folderUpdate: () => null,
          updates: const Stream.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.t(AppStringKeys.chatInfoLoadFoldersFailed)),
      findsNothing,
    );
    expect(
      find.text(AppStrings.t(AppStringKeys.chatInfoNoFolders)),
      findsOneWidget,
    );
    expect(
      requests.where((request) => request['@type'] == 'getChatFolders'),
      isEmpty,
    );

    final screen = find.byType(ChatFolderMembershipView);
    expect(
      find.descendant(of: screen, matching: find.byType(Scaffold)),
      findsNothing,
    );
    expect(
      find.descendant(of: screen, matching: find.byType(AlertDialog)),
      findsNothing,
    );
    expect(
      find.descendant(of: screen, matching: find.byType(TextField)),
      findsNothing,
    );
    expect(
      find.descendant(of: screen, matching: find.byType(TextButton)),
      findsNothing,
    );
    expect(
      find.descendant(of: screen, matching: find.byType(CupertinoButton)),
      findsNothing,
    );
    expect(
      find.descendant(of: screen, matching: find.byType(CupertinoSwitch)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: screen,
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
  });

  testWidgets('cached updateChatFolders snapshot renders folders', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      await testApp(
        ChatFolderMembershipView(
          chatId: 42,
          title: 'Test chat',
          query: (request) async {
            requests.add(request);
            switch (request['@type']) {
              case 'getChat':
                throw StateError('chat not cached yet');
              case 'getChatFolder':
                return {
                  '@type': 'chatFolder',
                  'title': 'Friends',
                  'included_chat_ids': [42],
                  'excluded_chat_ids': <int>[],
                };
              default:
                return {'@type': 'ok'};
            }
          },
          folderUpdate: () => {
            '@type': 'updateChatFolders',
            'chat_folders': [
              {'@type': 'chatFolderInfo', 'id': 7, 'title': 'Friends'},
            ],
          },
          updates: const Stream.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Friends'), findsOneWidget);
    expect(
      requests.where((request) => request['@type'] == 'getChatFolder'),
      hasLength(1),
    );
    expect(
      find.text(AppStrings.t(AppStringKeys.chatInfoLoadFoldersFailed)),
      findsNothing,
    );
  });

  testWidgets('custom prompt creates and immediately displays a folder', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      await testApp(
        ChatFolderMembershipView(
          chatId: 42,
          title: 'Test chat',
          query: (request) async {
            requests.add(request);
            switch (request['@type']) {
              case 'getChat':
                return {'@type': 'chat', 'positions': <Object>[]};
              case 'createChatFolder':
                return {'@type': 'chatFolderInfo', 'id': 9};
              default:
                return {'@type': 'ok'};
            }
          },
          folderUpdate: () => {
            '@type': 'updateChatFolders',
            'chat_folders': <Object>[],
          },
          updates: const Stream.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-folder-empty-create')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('chat-folder-create-prompt')),
      findsOneWidget,
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.byType(TextField), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('chat-folder-name-input')),
      'Work',
    );
    await tester.pump();
    await tester.tap(find.text(AppStrings.t(AppStringKeys.chatInfoCreate)));
    await tester.pumpAndSettle();

    expect(
      requests.where((request) => request['@type'] == 'createChatFolder'),
      hasLength(1),
    );
    expect(find.text('Work'), findsOneWidget);
    final createRequest = requests.singleWhere(
      (request) => request['@type'] == 'createChatFolder',
    );
    final folder = createRequest['folder'] as Map<String, dynamic>;
    expect(folder['name']['text']['text'], 'Work');
    expect(folder['included_chat_ids'], [42]);
  });

  testWidgets('folder membership toggle sends a valid chatFolder request', (
    tester,
  ) async {
    final requests = <Map<String, dynamic>>[];
    await tester.pumpWidget(
      await testApp(
        ChatFolderMembershipView(
          chatId: 42,
          title: 'Test chat',
          query: (request) async {
            requests.add(request);
            switch (request['@type']) {
              case 'getChat':
                return {'@type': 'chat', 'positions': <Object>[]};
              case 'getChatFolder':
                return {
                  '@type': 'chatFolder',
                  'name': {
                    '@type': 'chatFolderName',
                    'text': {
                      '@type': 'formattedText',
                      'text': 'Friends',
                      'entities': <Object>[],
                    },
                    'animate_custom_emoji': true,
                  },
                  'icon': {'@type': 'chatFolderIcon', 'name': 'Custom'},
                  'color_id': 3,
                  'is_shareable': true,
                  'included_chat_ids': <int>[],
                  'excluded_chat_ids': <int>[],
                };
              case 'editChatFolder':
                return {'@type': 'chatFolderInfo', 'id': 7};
              default:
                return {'@type': 'ok'};
            }
          },
          folderUpdate: () => {
            '@type': 'updateChatFolders',
            'chat_folders': [
              {'@type': 'chatFolderInfo', 'id': 7, 'title': 'Friends'},
            ],
          },
          updates: const Stream.empty(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('chat-folder-toggle-7')));
    await tester.pumpAndSettle();

    final editRequest = requests.singleWhere(
      (request) => request['@type'] == 'editChatFolder',
    );
    final folder = editRequest['folder'] as Map<String, dynamic>;
    expect(folder['name']['text']['text'], 'Friends');
    expect(folder.containsKey('title'), isFalse);
    expect(folder['color_id'], 3);
    expect(folder['included_chat_ids'], [42]);
    expect(folder['excluded_chat_ids'], isEmpty);
  });
}
