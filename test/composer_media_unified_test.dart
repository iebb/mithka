//
//  composer_media_unified_test.dart
//
//  The composer media panel is one continuously-scrollable surface: emoji
//  categories, sticker packs and saved GIFs are stacked sections of a single
//  CustomScrollView, the segment control navigates between section anchors,
//  and the selected segment follows the scroll. Opening on a persisted
//  initialMediaKind starts the scroll at that section.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/gif_item.dart';
import 'package:mithka/chat/gif_store.dart';
import 'package:mithka/chat/sticker_item.dart';
import 'package:mithka/chat/sticker_store.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
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
      'mithka_media_unified',
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

  tearDown(() {
    StickerStore.shared.reset();
    GifStore.shared.replaceItemsForTest(const []);
  });

  testWidgets('the panel is one scrollable with emoji first', (tester) async {
    await _pumpComposer(tester);
    final icon = find.byIcon(HeroAppIcons.solidFaceSmile.data).first;

    expect(find.byKey(const ValueKey('mediaUnifiedScroll')), findsNothing);
    await tester.tap(icon);
    await tester.pump();

    expect(find.byKey(const ValueKey('mediaUnifiedScroll')), findsOneWidget);
    expect(find.byKey(const ValueKey('mediaSection-emoji')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mediaSegmentSelected-emoji')),
      findsOneWidget,
    );
    // The old per-kind tab strips are gone from the unified surface.
    expect(find.byKey(const ValueKey('emojiPanelTabs')), findsNothing);
    expect(find.byKey(const ValueKey('stickerPanelTabs')), findsNothing);
    expect(find.byKey(const ValueKey('gifPanelTabs')), findsNothing);
  });

  testWidgets('initialMediaKind gif opens scrolled to the gif section', (
    tester,
  ) async {
    await _pumpComposer(tester, initialMediaKind: 'gif');
    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('mediaSegmentSelected-gif')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mediaSection-gif')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mediaSegmentSelected-emoji')),
      findsNothing,
    );
  });

  testWidgets('scrolling down flips the selected segment to gif', (
    tester,
  ) async {
    await _pumpComposer(tester);
    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pump();
    _seedGifs();

    // The emoji catalog alone spans thousands of pixels, so walk the scroll
    // down to a seeded gif tile instead of one blind drag.
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('gif-200')),
      300,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('mediaUnifiedScroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('mediaSegmentSelected-gif')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mediaSection-gif')), findsOneWidget);
  });

  testWidgets('tapping the sticker segment scrolls to a seeded sticker', (
    tester,
  ) async {
    final changed = <String>[];
    await _pumpComposer(tester, onMediaKindChanged: changed.add);
    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pump();
    _seedStickerPacks();

    await tester.tap(find.byKey(const ValueKey('mediaSegment-sticker')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('sticker-4101')),
      200,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('mediaUnifiedScroll')),
        matching: find.byType(Scrollable),
      ),
    );
    expect(changed, contains('sticker'));
  });

  testWidgets('the search button swaps the panel and cancel restores it', (
    tester,
  ) async {
    await _pumpComposer(tester);
    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('mediaPanelSearchButton')));
    await tester.pump();
    expect(find.byKey(const ValueKey('composerMediaSearch')), findsOneWidget);
    expect(find.byKey(const ValueKey('mediaUnifiedScroll')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mediaPanelSearchButton')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('composerMediaSearch')), findsNothing);
    expect(find.byKey(const ValueKey('mediaUnifiedScroll')), findsOneWidget);
  });

  testWidgets(
    'every seeded pack renders a header, recents use the l10n label',
    (tester) async {
      await _pumpComposer(tester);
      await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
      await tester.pump();
      _seedStickerPacks();

      final scrollable = find.descendant(
        of: find.byKey(const ValueKey('mediaUnifiedScroll')),
        matching: find.byType(Scrollable),
      );
      await tester.scrollUntilVisible(
        find.text('Alpha'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Alpha'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Beta'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Beta'), findsOneWidget);
      // The recent pseudo-pack seeds with the localized stickerStoreRecent
      // title; it renders ahead of Alpha, so check it after scrolling back up.
      final recentTitle = AppStrings.t(AppStringKeys.stickerStoreRecent);
      await tester.scrollUntilVisible(
        find.text(recentTitle),
        -200,
        scrollable: scrollable,
      );
      expect(find.text(recentTitle), findsOneWidget);
    },
  );
}

Future<void> _pumpComposer(
  WidgetTester tester, {
  String? initialMediaKind,
  void Function(String kind)? onMediaKindChanged,
}) async {
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
            initialMediaKind: initialMediaKind,
            onMediaKindChanged: onMediaKindChanged,
            gifPreviewBuilder: (_) => const SizedBox.expand(),
            onStartCall: (_) {},
            onMessageSent: () {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void _seedStickerPacks() {
  final recentTitle = AppStrings.t(AppStringKeys.stickerStoreRecent);
  StickerStore.shared.replacePacksForTest([
    StickerPack(
      id: StickerStore.recentPackId,
      title: recentTitle,
      loaded: true,
      stickers: const [
        StickerItem(id: 1001, width: 128, height: 128, emoji: '🙂'),
      ],
    ),
    StickerPack(
      id: 3101,
      title: 'Alpha',
      loaded: true,
      stickers: const [
        StickerItem(id: 4101, width: 128, height: 128, emoji: '😀'),
        StickerItem(id: 4102, width: 128, height: 128, emoji: '😃'),
      ],
    ),
    StickerPack(
      id: 3201,
      title: 'Beta',
      loaded: true,
      stickers: const [
        StickerItem(id: 4201, width: 128, height: 128, emoji: '😄'),
      ],
    ),
  ]);
}

void _seedGifs() {
  GifStore.shared.replaceItemsForTest([
    GifItem(
      id: 200,
      duration: 2,
      width: 320,
      height: 180,
      mimeType: 'video/mp4',
      file: TdFileRef(id: 200),
    ),
  ]);
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
