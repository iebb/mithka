import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/moments/moments_view.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _channelId = -100500;

Map<String, dynamic> _text(int id, int date, String text) => {
  '@type': 'message',
  'id': id,
  'chat_id': _channelId,
  'date': date,
  'is_outgoing': false,
  'is_channel_post': true,
  'sender_id': {'@type': 'messageSenderChat', 'chat_id': _channelId},
  'content': {
    '@type': 'messageText',
    'text': {
      '@type': 'formattedText',
      'text': text,
      'entities': <Map<String, dynamic>>[],
    },
  },
};

Map<String, dynamic> _photo(int id, int date) => {
  '@type': 'message',
  'id': id,
  'chat_id': _channelId,
  'date': date,
  'is_outgoing': false,
  'is_channel_post': true,
  'media_album_id': 77,
  'sender_id': {'@type': 'messageSenderChat', 'chat_id': _channelId},
  'content': {
    '@type': 'messagePhoto',
    'photo': {
      '@type': 'photo',
      'sizes': [
        {
          '@type': 'photoSize',
          'type': 'x',
          'width': 800,
          'height': 600,
          'photo': {'@type': 'file', 'id': 900 + id, 'size': 0},
        },
      ],
    },
    'caption': {
      '@type': 'formattedText',
      'text': '',
      'entities': <Map<String, dynamic>>[],
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory supportDir;
  late List<Map<String, dynamic>> requests;
  late List<Map<String, dynamic>> history;
  var firstPageServed = false;

  setUpAll(() async {
    supportDir = await Directory.systemTemp.createTemp('mithka-channel-feed');
    addTearDown(() {
      if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
    });
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final bindings = _FakeBindings();
    TdClient.shared.prepareForTesting(
      prefs: prefs,
      supportDir: supportDir.path,
      bindings: bindings,
      queryOverride: (request, clientId) async {
        requests.add(Map<String, dynamic>.from(request));
        switch (request['@type']) {
          case 'getChatHistory':
            final from = request['from_message_id'] as int;
            final newestFirst = history.reversed.toList();
            // An uncached channel: TDLib's first page is the last message.
            if (!firstPageServed) {
              firstPageServed = true;
              return {
                '@type': 'messages',
                'messages': newestFirst.take(1).toList(),
              };
            }
            return {
              '@type': 'messages',
              'messages': newestFirst
                  .where((m) => from == 0 || (m['id'] as int) <= from)
                  .take(request['limit'] as int)
                  .toList(),
            };
          case 'getMe':
            return {'@type': 'user', 'id': 42, 'first_name': 'Me'};
          case 'getChatMember':
            return {
              '@type': 'chatMember',
              'status': {'@type': 'chatMemberStatusMember'},
            };
          case 'getMessageProperties':
            return {
              '@type': 'messageProperties',
              'can_get_message_thread': false,
            };
        }
        return {'@type': 'ok'};
      },
    );
    final slot = TdClient.shared.addSlot();
    final clientId = TdClient.shared.clientId(slot);
    TdClient.shared.debugSetActiveAccountForTesting(slot, clientId ?? 0);
  });

  setUp(() {
    requests = [];
    firstPageServed = false;
    history = [
      _text(1, 1000, 'Recent meals'),
      for (var id = 2; id <= 5; id++) _photo(id, 1001),
      _text(6, 2000, 'Tonight'),
    ];
  });

  testWidgets(
    "a channel's feed shows the album TDLib left off the first page",
    (tester) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues({});
      final theme = ThemeController(await SharedPreferences.getInstance());
      addTearDown(theme.dispose);
      final channel = ChatSummary(
        id: _channelId,
        title: 'Bakery Oven',
        lastMessage: '',
        lastMessageId: 6,
        date: 2000,
        unreadCount: 0,
        order: 0,
        isMuted: true,
        kind: ChatKind.channel,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            theme: ThemeData(extensions: [AppColors.light]),
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: ChannelMomentsView(channel: channel),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(minutes: 2));
      }

      expect(find.text('Tonight', findRichText: true), findsOneWidget);
      expect(find.text('Recent meals', findRichText: true), findsOneWidget);
      for (var id = 2; id <= 5; id++) {
        expect(find.byKey(ValueKey('moments-media-$id')), findsOneWidget);
      }
      // A muted channel still shows, and its feed has no mute filter.
      expect(find.byIcon(HeroAppIcons.bellSlash.data), findsNothing);
      expect(find.byIcon(HeroAppIcons.solidBell.data), findsNothing);

      final historyReads = requests.where(
        (request) => request['@type'] == 'getChatHistory',
      );
      expect(historyReads, isNotEmpty);
      expect(historyReads.map((request) => request['chat_id']).toSet(), {
        _channelId,
      });
      // One channel never loads the whole chat list.
      expect(
        requests.map((request) => request['@type']),
        isNot(contains('loadChats')),
      );

      await tester.pumpWidget(const SizedBox());
      // The album tiles' image loads wait up to 25 s for a download update
      // the fake client never sends.
      await tester.pump(const Duration(seconds: 30));
    },
  );
}

/// Synthetic tdjson bindings: lets [TdClient.prepareForTesting] register a
/// client without loading the shared library.
class _FakeBindings implements TdBindings {
  int _nextClientId = 300;

  @override
  int createClientId() => _nextClientId++;

  // Every query the feed sends is answered by the query override.
  @override
  void send(int clientId, String request) {}

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
