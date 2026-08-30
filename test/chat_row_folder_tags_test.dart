//
//  chat_row_folder_tags_test.dart
//
//  文件夹标签 on a chat-list row: the folders a chat sits in, drawn on their own
//  line between the chat's name and its message preview.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_folder_tag_controller.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _foldersUpdate = {
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
};

ChatSummary _chat({Set<int> folders = const {}}) {
  final chat = ChatSummary(
    id: 42,
    title: 'NekokoLPA insider',
    lastMessage: 'you lucky',
    lastMessageId: 1,
    date: 0,
    unreadCount: 0,
    order: 1,
    isMuted: false,
  );
  chat.folderIds.addAll(folders);
  return chat;
}

void main() {
  Future<ChatFolderTagController> pumpRow(
    WidgetTester tester,
    ChatSummary chat, {
    bool enabled = true,
  }) async {
    SharedPreferences.setMockInitialValues({
      if (enabled) ChatFolderTagController.preferenceKey: true,
    });
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final folders = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(folders.close);
    final tags = ChatFolderTagController(
      preferences,
      query: (_) async => {'@type': 'ok'},
      folderUpdates: folders.stream,
      initialFolders: _foldersUpdate,
    );
    addTearDown(tags.dispose);

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
          home: Scaffold(body: ChatRowView(chat: chat)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return tags;
  }

  testWidgets('tags sit along the bottom, under the message', (tester) async {
    await pumpRow(tester, _chat(folders: {3}));

    final tagLine = find.byKey(const ValueKey('chat-row-folder-tags'));
    expect(tagLine, findsOneWidget);
    expect(find.text('Personal'), findsOneWidget);

    final name = tester.getCenter(find.text('NekokoLPA insider')).dy;
    final tag = tester.getCenter(find.text('Personal')).dy;
    final message = tester.getCenter(find.byType(ChatPreviewText)).dy;
    expect(message, greaterThan(name));
    expect(tag, greaterThan(message));
    expect(tester.takeException(), isNull);
  });

  testWidgets('every folder the chat is in gets a name, in folder order', (
    tester,
  ) async {
    await pumpRow(tester, _chat(folders: {7, 3}));

    expect(find.text('Personal'), findsOneWidget);
    expect(find.text('Work'), findsOneWidget);
    expect(
      tester.getCenter(find.text('Personal')).dx,
      lessThan(tester.getCenter(find.text('Work')).dx),
    );
  });

  testWidgets('a folder draws in its own colour, or the accent without one', (
    tester,
  ) async {
    await pumpRow(tester, _chat(folders: {3, 7}));

    expect(
      tester.widget<Text>(find.text('Personal')).style?.color,
      chatFolderTagColors[1],
    );
    expect(tester.widget<Text>(find.text('Work')).style?.color, AppTheme.brand);
  });

  testWidgets('a chat in no folder keeps the plain two-line row', (
    tester,
  ) async {
    await pumpRow(tester, _chat());

    expect(find.byKey(const ValueKey('chat-row-folder-tags')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the switched-off preference draws no tags', (tester) async {
    await pumpRow(tester, _chat(folders: {3}), enabled: false);

    expect(find.byKey(const ValueKey('chat-row-folder-tags')), findsNothing);
    expect(find.text('Personal'), findsNothing);
  });

  testWidgets('turning the preference on adds the line live', (tester) async {
    final tags = await pumpRow(tester, _chat(folders: {3}), enabled: false);
    expect(find.byKey(const ValueKey('chat-row-folder-tags')), findsNothing);

    await tags.setEnabled(true);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-row-folder-tags')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  group('folder membership on the chat summary', () {
    Map<String, dynamic> rawChat() => {
      '@type': 'chat',
      'id': 42,
      'title': 'NekokoLPA insider',
      'type': {'@type': 'chatTypePrivate', 'user_id': 7},
      'positions': const <Object>[],
    };

    Map<String, dynamic> folderPosition(int folderId, int order) => {
      '@type': 'updateChatPosition',
      'chat_id': 42,
      'position': {
        '@type': 'chatPosition',
        'list': {'@type': 'chatListFolder', 'chat_folder_id': folderId},
        'order': order,
      },
    };

    test('survives the chat being re-ingested', () async {
      // The regression: a re-ingest builds a fresh ChatSummary, and a raw chat
      // only carries positions for chat lists TDLib has loaded — so the tags
      // rendered once and then vanished on the next update for that chat.
      final model = ChatListViewModel();
      addTearDown(model.dispose);
      await model.ingestRawChatForTesting(rawChat());
      model.applyUpdateForTesting(folderPosition(3, 100));

      expect(model.chatsForFolder(3).single.folderIds, {3});

      await model.ingestRawChatForTesting(rawChat());

      expect(
        model.chatsForFolder(3).single.folderIds,
        {3},
        reason: 're-ingesting must not drop folder membership',
      );
    });

    test('clears when the chat actually leaves the folder', () async {
      final model = ChatListViewModel();
      addTearDown(model.dispose);
      await model.ingestRawChatForTesting(rawChat());
      model.applyUpdateForTesting(folderPosition(3, 100));
      expect(model.chatsForFolder(3), hasLength(1));

      model.applyUpdateForTesting(folderPosition(3, 0));

      expect(model.chatsForFolder(3), isEmpty);
    });
  });

  testWidgets('the tag line still fits at a large text scale', (tester) async {
    SharedPreferences.setMockInitialValues({
      ChatFolderTagController.preferenceKey: true,
    });
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    final folders = StreamController<Map<String, dynamic>>.broadcast();
    addTearDown(folders.close);
    final tags = ChatFolderTagController(
      preferences,
      query: (_) async => {'@type': 'ok'},
      folderUpdates: folders.stream,
      initialFolders: _foldersUpdate,
    );
    addTearDown(tags.dispose);

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
          home: MediaQuery(
            data: const MediaQueryData(textScaler: TextScaler.linear(2)),
            child: Scaffold(
              body: ChatRowView(chat: _chat(folders: {3})),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('chat-row-folder-tags')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
