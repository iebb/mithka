//
//  composer_media_segment_persist_test.dart
//
//  The composer media panel reopens on the segment (emoji/sticker/gif) the
//  user last used. The last-used value lives in a silent ThemeController
//  preference; the input bar itself only takes an initial value and reports
//  changes through a callback, keeping it provider-free for unit tests.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/composer/chat_input_bar.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // Opening the media panel drives the real emoji/sticker/gif stores; give
    // the client a synthetic registry whose queries answer with empty sets so
    // no store throws into the zone.
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final supportDir = await Directory.systemTemp.createTemp(
      'mithka_media_segment',
    );
    addTearDown(() {
      if (supportDir.existsSync()) supportDir.deleteSync(recursive: true);
    });
    TdClient.shared.prepareForTesting(
      prefs: prefs,
      supportDir: supportDir.path,
      bindings: _FakeBindings(),
      queryOverride: (request, clientId) async => switch (request['@type']) {
        'getOption' => {'@type': 'optionValueBoolean', 'value': false},
        'getInstalledStickerSets' => {'@type': 'stickerSets', 'sets': []},
        'getRecentStickers' => {
          '@type': 'stickers',
          'stickers': <Map<String, dynamic>>[],
        },
        'getSavedAnimations' => {
          '@type': 'animations',
          'animations': <Map<String, dynamic>>[],
        },
        _ => {'@type': 'ok'},
      },
    );
    final slot = TdClient.shared.addSlot();
    final clientId = TdClient.shared.clientId(slot);
    TdClient.shared.debugSetActiveAccountForTesting(slot, clientId ?? 0);
  });

  test(
    'mediaPanelSegment reads the stored value and defaults to emoji',
    () async {
      SharedPreferences.setMockInitialValues(const {});
      var prefs = await SharedPreferences.getInstance();
      var controller = ThemeController(prefs);
      addTearDown(controller.dispose);
      expect(controller.mediaPanelSegment, 'emoji');

      SharedPreferences.setMockInitialValues(const {
        'mediaPanelSegment': 'sticker',
      });
      prefs = await SharedPreferences.getInstance();
      controller = ThemeController(prefs);
      addTearDown(controller.dispose);
      expect(controller.mediaPanelSegment, 'sticker');
    },
  );

  test('the silent setter writes without notifying and persists', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final controller = ThemeController(prefs);
    addTearDown(controller.dispose);
    var notifications = 0;
    controller.addListener(() => notifications++);

    controller.mediaPanelSegment = 'gif';
    expect(controller.mediaPanelSegment, 'gif');
    expect(notifications, 0);

    // A fresh controller over the same preferences reads the written value
    // back — the write actually persisted.
    final reread = ThemeController(prefs);
    addTearDown(reread.dispose);
    expect(reread.mediaPanelSegment, 'gif');
  });

  testWidgets('the panel opens on the restored segment and reports switches', (
    tester,
  ) async {
    final changed = <String>[];
    final vm = ChatViewModel(chatId: 1, title: 'Test', markReadOnOpen: false);
    addTearDown(vm.dispose);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          platform: TargetPlatform.android,
          extensions: [AppColors.light],
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              vm: vm,
              quickRepliesEnabled: false,
              initialMediaKind: 'gif',
              onMediaKindChanged: changed.add,
              onStartCall: (_) {},
              onMessageSent: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pumpAndSettle();
    // The panel reopens on the restored gif segment: the gif tab strip is
    // showing and the gif segment is selected.
    expect(
      find.byKey(const ValueKey('mediaSegmentSelected-gif')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('gifPanelTabs')), findsOneWidget);
    expect(changed, isEmpty);

    // Switching to the sticker segment reports it and swaps the panel for the
    // sticker tab strip — no scrolling between kinds anymore.
    await tester.tap(find.byKey(const ValueKey('mediaSegment-sticker')));
    await tester.pumpAndSettle();
    expect(changed, ['sticker']);
    expect(
      find.byKey(const ValueKey('mediaSegmentSelected-sticker')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('stickerPanelTabs')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mediaSegmentSelected-gif')),
      findsNothing,
    );
  });

  testWidgets(
    'opening on a restored gif segment still holds gif after extra frames',
    (tester) async {
      final changed = <String>[];
      final vm = ChatViewModel(chatId: 1, title: 'Test', markReadOnOpen: false);
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            platform: TargetPlatform.android,
            extensions: [AppColors.light],
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(
                vm: vm,
                quickRepliesEnabled: false,
                initialMediaKind: 'gif',
                onMediaKindChanged: changed.add,
                onStartCall: (_) {},
                onMessageSent: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('mediaSegmentSelected-gif')),
        findsOneWidget,
      );

      // The initial-anchor jump settles over several frames; the scroll-follow
      // logic must not interpret that settling as the user scrolling back up
      // and rewrite the persisted segment to emoji.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(
        find.byKey(const ValueKey('mediaSegmentSelected-gif')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mediaSegmentSelected-emoji')),
        findsNothing,
      );
      expect(changed, isEmpty);
    },
  );

  testWidgets(
    'opening on a restored sticker segment still holds sticker after settle',
    (tester) async {
      final changed = <String>[];
      final vm = ChatViewModel(chatId: 1, title: 'Test', markReadOnOpen: false);
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          theme: ThemeData(
            platform: TargetPlatform.android,
            extensions: [AppColors.light],
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(
                vm: vm,
                quickRepliesEnabled: false,
                initialMediaKind: 'sticker',
                onMediaKindChanged: changed.add,
                onStartCall: (_) {},
                onMessageSent: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
      await tester.pumpAndSettle();

      // The initial-anchor jump clamps to maxScrollExtent when the sticker
      // section is short; the scroll-follow must not read that programmatic
      // jump as the user scrolling and rewrite the persisted segment.
      expect(
        find.byKey(const ValueKey('mediaSegmentSelected-sticker')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('mediaSegmentSelected-emoji')),
        findsNothing,
      );
      expect(changed, isEmpty);
    },
  );
}

/// Synthetic tdjson bindings: lets [TdClient.prepareForTesting] register a
/// client without loading the pinned shared library.
class _FakeBindings implements TdBindings {
  int _nextClientId = 100;

  @override
  int createClientId() => _nextClientId++;

  @override
  void send(int clientId, String request) {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
