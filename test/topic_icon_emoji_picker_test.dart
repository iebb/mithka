//
//  topic_icon_emoji_picker_test.dart
//
//  The topic-icon picker offers the user's installed custom-emoji packs
//  alongside Telegram's default status emoji, returns the picked id to the
//  topic draft, and keeps the explicit "no icon" choice working.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/channels/topic_list_actions.dart';
import 'package:mithka/chat/custom_emoji.dart';
import 'package:mithka/chat/emoji_store.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_icon_picker_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

final requests = <Map<String, dynamic>>[];
late StreamController<Map<String, dynamic>> updates;
var installedSetsFail = false;

const packOne = _FakePack(11, 'Pack One', [7001, 7002]);
const packTwo = _FakePack(12, 'Pack Two', [8001]);
var packs = <_FakePack>[packOne, packTwo];

void main() {
  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          requests.add(request);
          return _response(request);
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });
  setUp(() {
    requests.clear();
    installedSetsFail = false;
    packs = [packOne, packTwo];
    EmojiStore.shared.reset();
    CustomEmojiCenter.shared.reset();
  });
  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets('shows default status emoji then each installed pack in order', (
    tester,
  ) async {
    await _pumpPicker(tester);

    expect(find.text('Default'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-icon-emoji-9001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-icon-emoji-9002')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-icon-emoji-7001')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-icon-emoji-7002')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('profile-icon-emoji-8001')),
      findsOneWidget,
    );

    final defaultY = tester
        .getTopLeft(find.byKey(const ValueKey('profile-icon-emoji-9001')))
        .dy;
    final packOneY = tester
        .getTopLeft(find.byKey(const ValueKey('profile-icon-emoji-7001')))
        .dy;
    final packTwoY = tester
        .getTopLeft(find.byKey(const ValueKey('profile-icon-emoji-8001')))
        .dy;
    expect(defaultY, lessThan(packOneY));
    expect(packOneY, lessThan(packTwoY));
    expect(
      tester
          .getTopLeft(find.byKey(const ValueKey('profile-icon-emoji-7001')))
          .dx,
      lessThan(
        tester
            .getTopLeft(find.byKey(const ValueKey('profile-icon-emoji-7002')))
            .dx,
      ),
    );
    expect(find.byKey(const ValueKey('profile-icon-pack-11')), findsOneWidget);
    expect(find.byKey(const ValueKey('profile-icon-pack-12')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('topic draft sends the picked pack emoji as the icon id', (
    tester,
  ) async {
    await _pumpTopicSheet(tester);

    await tester.tap(find.byKey(const ValueKey('open-topic-sheet')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('topic-draft-emoji')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('profile-icon-emoji-7001')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('topic-draft-save')));
    await _settle(tester);

    final create = requests.lastWhere(
      (request) => request['@type'] == 'createForumTopic',
    );
    expect(create['name'], 'Topic');
    expect((create['icon'] as Map<String, dynamic>)['custom_emoji_id'], 7001);

    // The edit path carries the same pick as the flat field.
    await _pumpTopicSheet(tester, initialCustomEmojiId: 7001);
    await tester.tap(find.byKey(const ValueKey('open-topic-sheet')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('topic-draft-emoji')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('profile-icon-emoji-7001')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('topic-draft-save')));
    await _settle(tester);

    final edit = requests.lastWhere(
      (request) => request['@type'] == 'editForumTopic',
    );
    expect(edit['edit_icon_custom_emoji'], isTrue);
    expect(edit['icon_custom_emoji_id'], 7001);
    expect(tester.takeException(), isNull);
  });

  testWidgets('choosing None clears the icon with custom emoji id zero', (
    tester,
  ) async {
    await _pumpTopicSheet(tester, initialCustomEmojiId: 7001);

    await tester.tap(find.byKey(const ValueKey('open-topic-sheet')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('topic-draft-emoji')));
    await _settle(tester);
    expect(find.text('None'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('profile-icon-none')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('topic-draft-save')));
    await _settle(tester);

    final edit = requests.lastWhere(
      (request) => request['@type'] == 'editForumTopic',
    );
    expect(edit['edit_icon_custom_emoji'], isTrue);
    expect(edit['icon_custom_emoji_id'], 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty installed-pack list still renders the defaults', (
    tester,
  ) async {
    packs = const [];
    await _pumpPicker(tester);

    expect(find.text('Default'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-icon-emoji-9001')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('profile-icon-pack-11')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a failing installed-pack query does not break the picker', (
    tester,
  ) async {
    installedSetsFail = true;
    await _pumpPicker(tester);

    expect(find.text('Default'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('profile-icon-emoji-9001')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('profile-icon-emoji-7001')), findsNothing);
    expect(tester.takeException(), isNull);
  });
}

class _FakePack {
  const _FakePack(this.id, this.title, this.emojiIds);
  final int id;
  final String title;
  final List<int> emojiIds;
}

Map<String, dynamic> _response(Map<String, dynamic> request) {
  switch (request['@type']) {
    case 'getOption':
      return {
        '@type': 'optionValue',
        'name': request['name'],
        'value': request['name'] == 'is_premium',
      };
    case 'getDefaultChatEmojiStatuses':
    case 'getDefaultEmojiStatuses':
      return {
        '@type': 'emojiStatuses',
        'emoji_statuses': [
          for (final id in [9001, 9002])
            {
              '@type': 'emojiStatus',
              'custom_emoji_id': id,
              'expiration_date': 0,
            },
        ],
      };
    case 'getInstalledStickerSets':
      if ((request['sticker_type'] as Map<String, dynamic>?)?['@type'] !=
          'stickerTypeCustomEmoji') {
        return {'@type': 'stickerSets', 'sets': <Map<String, dynamic>>[]};
      }
      if (installedSetsFail) throw Exception('installed sets unavailable');
      return {
        '@type': 'stickerSets',
        'sets': [
          for (final pack in packs)
            {
              '@type': 'stickerSetInfo',
              'id': pack.id,
              'title': pack.title,
              'is_installed': true,
            },
        ],
      };
    case 'getStickerSet':
      final id = request['set_id'] as int;
      final pack = packs.firstWhere((pack) => pack.id == id);
      return {
        '@type': 'stickerSet',
        'id': pack.id,
        'title': pack.title,
        'stickers': [
          for (var index = 0; index < pack.emojiIds.length; index++)
            _customEmojiSticker(pack.emojiIds[index], pack.id * 100 + index),
        ],
      };
    case 'createForumTopic':
      return {
        '@type': 'forumTopicInfo',
        'chat_id': request['chat_id'],
        'forum_topic_id': 500,
        'name': request['name'],
      };
    case 'editForumTopic':
      return {
        '@type': 'forumTopicInfo',
        'chat_id': request['chat_id'],
        'forum_topic_id': request['forum_topic_id'],
        'name': request['name'],
      };
    case 'getCustomEmojiStickers':
      return {'@type': 'stickers', 'stickers': <Map<String, dynamic>>[]};
    case 'getBotApiAccountInfo':
      return {'@type': 'ok'};
    default:
      return {'@type': 'ok'};
  }
}

Map<String, dynamic> _customEmojiSticker(int customEmojiId, int fileId) => {
  '@type': 'sticker',
  'sticker': {'@type': 'file', 'id': fileId},
  'format': {'@type': 'stickerFormatWebp'},
  'width': 512,
  'height': 512,
  'emoji': '',
  'full_type': {
    '@type': 'stickerFullTypeCustomEmoji',
    'custom_emoji_id': customEmojiId,
    'needs_repainting': false,
  },
};

Future<void> _pumpPicker(WidgetTester tester) async {
  final theme = await _theme();
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    _shell(
      theme,
      const ProfileIconPickerView(
        selectedId: 0,
        title: 'Topic icon',
        source: ProfileIconSource.status,
      ),
    ),
  );
  await _settle(tester);
}

/// A host standing in for the topic list caller: it opens the shared draft
/// dialog and sends the request the caller would send for the returned draft.
Future<void> _pumpTopicSheet(
  WidgetTester tester, {
  int initialCustomEmojiId = 0,
}) async {
  final theme = await _theme();
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    _shell(
      theme,
      Builder(
        builder: (context) => Center(
          child: GestureDetector(
            key: const ValueKey('open-topic-sheet'),
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              final draft = await showDialog<TopicDraft>(
                context: context,
                builder: (_) => TopicDraftDialog(
                  title: 'New Topic',
                  initialName: 'Topic',
                  initialColor: topicIconColors.first,
                  initialCustomEmojiId: initialCustomEmojiId,
                  canChangeColor: true,
                ),
              );
              if (draft == null || draft.name.isEmpty) return;
              await TdClient.shared.query(
                initialCustomEmojiId == 0
                    ? createForumTopicRequest(
                        chatId: -42,
                        name: draft.name,
                        color: draft.color,
                        customEmojiId: draft.customEmojiId,
                      )
                    : editForumTopicRequest(
                        chatId: -42,
                        forumTopicId: 7,
                        name: draft.name,
                        customEmojiId: draft.customEmojiId,
                      ),
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<ThemeController> _theme() async {
  SharedPreferences.setMockInitialValues({});
  final preferences = await SharedPreferences.getInstance();
  return ThemeController(preferences);
}

Widget _shell(ThemeController theme, Widget home) =>
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: Brightness.light,
          extensions: [AppColors.light],
        ),
        home: home,
      ),
    );

Future<void> _settle(WidgetTester tester) => tester.pumpAndSettle(
  const Duration(milliseconds: 100),
  EnginePhase.sendSemanticsUpdate,
  const Duration(seconds: 5),
);
