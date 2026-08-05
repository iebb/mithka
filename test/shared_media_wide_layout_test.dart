import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/shared_media_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamController<Map<String, dynamic>> updates;
  var messages = <Map<String, dynamic>>[];
  Completer<Map<String, dynamic>>? blockedSearch;

  setUpAll(() {
    updates = StreamController<Map<String, dynamic>>.broadcast();
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'searchMessages':
              final blocker = blockedSearch;
              if (blocker != null) return blocker.future;
              final chatList = request['chat_list'] as Map<String, dynamic>?;
              final isArchive = chatList?['@type'] == 'chatListArchive';
              return {
                '@type': 'foundMessages',
                'messages': isArchive ? <Map<String, dynamic>>[] : messages,
              };
            case 'searchChatMessages':
              return {'@type': 'foundChatMessages', 'messages': messages};
            case 'getFile':
              final fileId = request['file_id'] as int;
              final completed = fileId == 501;
              return {
                '@type': 'file',
                'id': fileId,
                'size': 6 * 1024 * 1024,
                'expected_size': 6 * 1024 * 1024,
                'local': {
                  '@type': 'localFile',
                  'path': '',
                  'downloaded_size': completed ? 6 * 1024 * 1024 : 0,
                  'downloaded_prefix_size': 0,
                  'is_downloading_active': false,
                  'is_downloading_completed': completed,
                },
              };
            case 'getChat':
              return {
                '@type': 'chat',
                'id': request['chat_id'],
                'title': 'Travel chat',
              };
            case 'deleteFile':
              return {'@type': 'ok'};
          }
          return {'@type': 'ok'};
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  setUp(() {
    messages = _videoMessages();
    blockedSearch = null;
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  testWidgets('wide macOS hides the inner header for Video and Music', (
    tester,
  ) async {
    _configureView(tester, const Size(1024, 768), TargetPlatform.macOS);

    await tester.pumpWidget(
      _app(
        const SharedMediaView(
          key: ValueKey('wide-video'),
          chatId: 0,
          title: 'Videos',
          initialTab: 4,
          displayTitle: AppStringKeys.sharedMediaVideos,
          lockedTab: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('shared-media-inner-header')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('shared-media-back-button')),
      findsNothing,
    );

    messages = const [];
    await tester.pumpWidget(
      _app(
        const SharedMediaView(
          key: ValueKey('wide-music'),
          chatId: 77,
          title: 'Music',
          initialTab: 5,
          displayTitle: AppStringKeys.profileDetailMusic,
          lockedTab: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('shared-media-inner-header')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('shared-media-back-button')),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('landscape iPad uses the wide Video and Music presentation', (
    tester,
  ) async {
    _configureView(tester, const Size(1180, 820), TargetPlatform.iOS);

    await tester.pumpWidget(
      _app(
        const SharedMediaView(
          key: ValueKey('ipad-video'),
          chatId: 0,
          title: 'Videos',
          initialTab: 4,
          displayTitle: AppStringKeys.sharedMediaVideos,
          lockedTab: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('shared-media-inner-header')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('shared-video-grid')), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-video-list')), findsNothing);

    messages = const [];
    await tester.pumpWidget(
      _app(
        const SharedMediaView(
          key: ValueKey('ipad-music'),
          chatId: 77,
          title: 'Music',
          initialTab: 5,
          displayTitle: AppStringKeys.profileDetailMusic,
          lockedTab: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('shared-media-inner-header')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('shared-media-back-button')),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'portrait iPad removes Video and Music headers but keeps the list layout',
    (tester) async {
      _configureView(tester, const Size(820, 1180), TargetPlatform.iOS);

      await tester.pumpWidget(
        _app(
          const SharedMediaView(
            key: ValueKey('portrait-ipad-video'),
            chatId: 0,
            title: 'Videos',
            initialTab: 4,
            displayTitle: AppStringKeys.sharedMediaVideos,
            lockedTab: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('shared-media-inner-header')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('shared-media-back-button')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey('shared-video-list')), findsOneWidget);
      expect(find.byKey(const ValueKey('shared-video-grid')), findsNothing);

      messages = const [];
      await tester.pumpWidget(
        _app(
          const SharedMediaView(
            key: ValueKey('portrait-ipad-music'),
            chatId: 77,
            title: 'Music',
            initialTab: 5,
            displayTitle: AppStringKeys.profileDetailMusic,
            lockedTab: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('shared-media-inner-header')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('shared-media-back-button')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('phone keeps the Video header, back action, and list layout', (
    tester,
  ) async {
    _configureView(tester, const Size(390, 844), TargetPlatform.iOS);

    await tester.pumpWidget(
      _app(
        const SharedMediaView(
          chatId: 0,
          title: 'Videos',
          initialTab: 4,
          displayTitle: AppStringKeys.sharedMediaVideos,
          lockedTab: true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('shared-media-inner-header')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('shared-media-back-button')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('shared-video-list')), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-video-grid')), findsNothing);
    expect(
      find.byKey(const ValueKey('shared-media-filter-strip')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'wide Video uses bounded grid cards and keeps filters and menus reachable',
    (tester) async {
      _configureView(tester, const Size(760, 720), TargetPlatform.macOS);

      await tester.pumpWidget(
        _app(
          const SharedMediaView(
            chatId: 0,
            title: 'Videos',
            initialTab: 4,
            displayTitle: AppStringKeys.sharedMediaVideos,
            lockedTab: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const ValueKey('shared-video-grid')), findsOneWidget);
      final first = find.byKey(const ValueKey('shared-video-card-101-1'));
      final second = find.byKey(const ValueKey('shared-video-card-101-4'));
      final fourth = find.byKey(const ValueKey('shared-video-card-101-2'));
      expect(first, findsOneWidget);
      expect(second, findsOneWidget);
      expect(fourth, findsOneWidget);

      final firstRect = tester.getRect(first);
      final secondRect = tester.getRect(second);
      final fourthRect = tester.getRect(fourth);
      expect(firstRect.width, inInclusiveRange(248, 320));
      expect(secondRect.left - firstRect.right, closeTo(16, 0.01));
      expect(fourthRect.top - firstRect.bottom, closeTo(18, 0.01));

      final cardSemantics = tester.getSemantics(first).getSemanticsData();
      expect(cardSemantics.label, contains('Alpine lake'));
      expect(cardSemantics.hasAction(SemanticsAction.tap), isTrue);

      final cardMenu = find.descendant(
        of: first,
        matching: find.byWidgetPredicate((widget) => widget is PopupMenuButton),
      );
      expect(cardMenu, findsOneWidget);
      await tester.tap(cardMenu);
      await tester.pumpAndSettle();

      final openOriginal = AppStrings.t(
        AppStringKeys.momentsOpenOriginalMessage,
      );
      final deleteCache = AppStrings.t(
        AppStringKeys.sharedMediaDeleteLocalCache,
      );
      expect(find.text(openOriginal), findsOneWidget);
      final deleteLabel = find.text(deleteCache);
      expect(deleteLabel, findsOneWidget);
      final deleteItem = tester.widget<PopupMenuItem>(
        find.ancestor(
          of: deleteLabel,
          matching: find.byWidgetPredicate((widget) => widget is PopupMenuItem),
        ),
      );
      expect(deleteItem.enabled, isTrue);

      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      // The states moved into a dropdown, so open it before choosing one.
      final filterDropdown = find.byKey(
        const ValueKey('shared-media-filter-dropdown'),
      );
      expect(filterDropdown, findsOneWidget);
      expect(
        tester
            .getSemantics(filterDropdown)
            .getSemanticsData()
            .hasAction(SemanticsAction.tap),
        isTrue,
      );
      await tester.tap(filterDropdown);
      await tester.pumpAndSettle();

      final downloadedFilter = find.byKey(
        const ValueKey('shared-media-filter-downloaded'),
      );
      expect(downloadedFilter, findsOneWidget);
      await tester.tap(downloadedFilter);
      await tester.pumpAndSettle();

      expect(first, findsOneWidget);
      expect(second, findsNothing);
      expect(fourth, findsNothing);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('wide Video keeps loading and empty states in the grid surface', (
    tester,
  ) async {
    _configureView(tester, const Size(900, 700), TargetPlatform.macOS);
    final search = Completer<Map<String, dynamic>>();
    blockedSearch = search;

    await tester.pumpWidget(
      _app(
        const SharedMediaView(
          chatId: 0,
          title: 'Videos',
          initialTab: 4,
          displayTitle: AppStringKeys.sharedMediaVideos,
          lockedTab: true,
        ),
      ),
    );
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('shared-video-grid')), findsNothing);

    search.complete({'@type': 'foundMessages', 'messages': const []});
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.t(AppStringKeys.sharedMediaEmpty)),
      findsOneWidget,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}

Widget _app(Widget home) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [AppLocalizations.delegate],
  supportedLocales: AppLocalizations.supportedLocales,
  home: home,
);

void _configureView(WidgetTester tester, Size size, TargetPlatform platform) {
  debugDefaultTargetPlatformOverride = platform;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
    debugDefaultTargetPlatformOverride = null;
  });
}

List<Map<String, dynamic>> _videoMessages() => [
  _videoMessage(1, 501, 'Alpine lake', 95),
  _videoMessage(2, 502, 'Night train', 142),
  _videoMessage(3, 503, 'Harbor walk', 63),
  _videoMessage(4, 504, 'Mountain road', 188),
];

Map<String, dynamic> _videoMessage(
  int id,
  int fileId,
  String caption,
  int duration,
) => {
  '@type': 'message',
  'id': id,
  'chat_id': 101,
  'date': 1700000000 + id,
  'is_outgoing': false,
  'content': {
    '@type': 'messageVideo',
    'caption': {
      '@type': 'formattedText',
      'text': caption,
      'entities': const [],
    },
    'video': {
      '@type': 'video',
      'duration': duration,
      'width': 1280,
      'height': 720,
      'video': {'@type': 'file', 'id': fileId},
    },
  },
};
