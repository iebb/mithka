//
//  composer_media_panels_test.dart
//
//  The composer media panel is a three-way selector over per-kind panels:
//  emoji and stickers each keep a horizontally scrollable strip above ONE
//  continuously scrollable list (emoji: recents + catalog categories +
//  custom-emoji packs; stickers: favorites + recents + every installed pack),
//  GIF is a plain saved-animations grid. The strip anchors into the list in
//  both directions, the segment switch is instant (no inter-kind scrolling),
//  and the search button still swaps the panel for the search overlay.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/composer/chat_input_bar.dart';
import 'package:mithka/chat/stickers/gif_item.dart';
import 'package:mithka/chat/stickers/gif_store.dart';
import 'package:mithka/chat/stickers/sticker_item.dart';
import 'package:mithka/chat/stickers/sticker_store.dart';
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
      'mithka_media_panels',
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

  testWidgets('opening shows the emoji panel with its own strip', (
    tester,
  ) async {
    await _pumpComposer(tester);
    final icon = find.byIcon(HeroAppIcons.solidFaceSmile.data).first;

    expect(find.byKey(const ValueKey('mediaKindSegments')), findsNothing);
    await tester.tap(icon);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byKey(const ValueKey('emojiPanelTabs')), findsOneWidget);
    expect(find.byKey(const ValueKey('emojiPanelScroll')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mediaSegmentSelected-emoji')),
      findsOneWidget,
    );
    // The unified inter-kind scroll surface is gone.
    expect(find.byKey(const ValueKey('mediaUnifiedScroll')), findsNothing);
    // Only the active kind's strip renders.
    expect(find.byKey(const ValueKey('stickerPanelTabs')), findsNothing);
    expect(find.byKey(const ValueKey('gifPanelTabs')), findsNothing);
  });

  testWidgets('the sticker panel continuously stacks packs under its strip', (
    tester,
  ) async {
    final changed = <String>[];
    await _pumpComposer(tester, onMediaKindChanged: changed.add);
    _seedStickerPacks();
    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mediaSegment-sticker')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('stickerPanelTabs')), findsOneWidget);
    expect(find.byKey(const ValueKey('stickerPanelScroll')), findsOneWidget);
    expect(changed, contains('sticker'));

    // The recents pseudo-pack and every installed pack stack in ONE scroller.
    final scrollable = _stickerScrollable();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('sticker-4101')),
      200,
      scrollable: scrollable,
    );
    expect(find.byKey(const ValueKey('sticker-4101')), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('sticker-4201')),
      200,
      scrollable: scrollable,
    );
    expect(find.byKey(const ValueKey('sticker-4201')), findsOneWidget);
  });

  testWidgets('tapping a pack tab scrolls the sticker panel to that pack', (
    tester,
  ) async {
    await _pumpComposer(tester);
    _seedStickerPacks();
    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mediaSegment-sticker')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('stickerPackTab-3201')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // The Beta pack's sticker is on screen without any manual scrolling.
    expect(find.byKey(const ValueKey('sticker-4201')), findsOneWidget);
  });

  testWidgets('the gif segment shows the plain saved-animations grid', (
    tester,
  ) async {
    await _pumpComposer(tester);
    _seedGifs();
    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mediaSegment-gif')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mediaSegmentSelected-gif')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('gif-200')), findsOneWidget);
    expect(find.byKey(const ValueKey('gifPanelTabs')), findsOneWidget);
  });

  testWidgets('segment switches are instant with no inter-kind scroller', (
    tester,
  ) async {
    await _pumpComposer(tester);
    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('mediaSegment-gif')));
    await tester.pump();
    // No animation frames are needed: the gif content is present immediately
    // (a single pump flushes the post-tap frame only — no settling flight).
    expect(
      find.byKey(const ValueKey('mediaSegmentSelected-gif')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('gifPanelTabs')), findsOneWidget);
    expect(find.byKey(const ValueKey('emojiPanelTabs')), findsNothing);
    expect(find.byKey(const ValueKey('mediaUnifiedScroll')), findsNothing);
  });

  testWidgets('the search button swaps the panel and cancel restores it', (
    tester,
  ) async {
    await _pumpComposer(tester);
    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    await tester.tap(find.byKey(const ValueKey('mediaPanelSearchButton')));
    await tester.pump();
    expect(find.byKey(const ValueKey('composerMediaSearch')), findsOneWidget);
    expect(find.byKey(const ValueKey('emojiPanelScroll')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mediaPanelSearchButton')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const ValueKey('composerMediaSearch')), findsNothing);
    expect(find.byKey(const ValueKey('emojiPanelScroll')), findsOneWidget);
  });

  testWidgets(
    'every seeded pack renders a header, recents use the l10n label',
    (tester) async {
      await _pumpComposer(tester);
      _seedStickerPacks();
      await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mediaSegment-sticker')));
      await tester.pumpAndSettle();

      final scrollable = _stickerScrollable();
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

  testWidgets('the emoji strip anchors into the continuous category stack', (
    tester,
  ) async {
    await _pumpComposer(tester);
    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('emojiPanelTabs')), findsOneWidget);
    // One of the category tabs jumps the stack to that category's emojis.
    await tester.tap(find.byKey(const ValueKey('emojiCategoryTab-1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    // The stack scrolled: the second category sits at the top instead of
    // thousands of pixels down.
    final position = tester.state<ScrollableState>(_emojiScrollable()).position;
    expect(position.pixels, greaterThan(0));
  });
}

Finder _stickerScrollable() => find.descendant(
  of: find.byKey(const ValueKey('stickerPanelScroll')),
  matching: find.byType(Scrollable),
);

Finder _emojiScrollable() => find.descendant(
  of: find.byKey(const ValueKey('emojiPanelScroll')),
  matching: find.byType(Scrollable),
);

Future<void> _pumpComposer(
  WidgetTester tester, {
  String? initialMediaKind,
  void Function(String kind)? onMediaKindChanged,
}) async {
  final vm = ChatViewModel(chatId: 1, title: 'Test', markReadOnOpen: false);
  addTearDown(vm.dispose);
  // The docked media panel plus the input row is taller than the default
  // 600pt test window, which pushes the segment control out of the hit-test
  // area — give the surface phone height.
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
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
