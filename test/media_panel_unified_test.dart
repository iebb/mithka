//
//  media_panel_unified_test.dart
//
//  Covers the Telegram-iOS-style unified composer media panel: a single
//  toolbar entry opens one panel whose top segmented selector switches
//  between the emoji, sticker and GIF regions (each keeping its own
//  secondary strip, search tab and content). Send closes the panel, and
//  desktop renders the same panel inside a single anchored popover.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/emoji_recents_store.dart';
import 'package:mithka/chat/emoji_store.dart';
import 'package:mithka/chat/gif_item.dart';
import 'package:mithka/chat/gif_store.dart';
import 'package:mithka/chat/sticker_item.dart';
import 'package:mithka/chat/sticker_store.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<ChatViewModel> _pumpMobileComposer(
  WidgetTester tester, {
  VoidCallback? onMessageSent,
  Widget Function(GifItem item)? gifPreviewBuilder,
  TextScaler? textScaler,
  TextDirection? textDirection,
}) async {
  final vm = _UnifiedPanelTestViewModel();
  addTearDown(vm.dispose);
  Widget bar = ChatInputBar(
    vm: vm,
    quickRepliesEnabled: false,
    gifPreviewBuilder: gifPreviewBuilder,
    onStartCall: (_) {},
    onMessageSent: onMessageSent ?? () {},
  );
  if (textScaler != null) {
    // Capture the wrapped widget in a local: a closure that reads `bar`
    // would see the Builder itself once bar is reassigned, recursing forever.
    final content = bar;
    final scaler = textScaler;
    bar = Builder(
      builder: (context) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: scaler),
        child: content,
      ),
    );
  }
  if (textDirection != null) {
    bar = Directionality(textDirection: textDirection, child: bar);
  }
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
      theme: ThemeData(extensions: [AppColors.light]),
      home: Scaffold(
        body: Align(alignment: Alignment.bottomCenter, child: bar),
      ),
    ),
  );
  return vm;
}

Finder get _mediaButton => find
    .ancestor(
      of: find.byIcon(HeroAppIcons.solidFaceSmile.data),
      matching: find.byType(AppInteractiveSurface),
    )
    .first;
Finder get _segments => find.byKey(const ValueKey('mediaKindSegments'));
Finder get _emojiTabs => find.byKey(const ValueKey('emojiPanelTabs'));
Finder get _stickerTabs => find.byKey(const ValueKey('stickerPanelTabs'));
Finder get _gifTabs => find.byKey(const ValueKey('gifPanelTabs'));
Finder get _search => find.byKey(const ValueKey('composerMediaSearch'));

void main() {
  setUpAll(() async {
    await AppStrings.ensureLoaded(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EmojiRecentsStore.shared.resetForTesting();
    EmojiStore.shared.reset();
    // Pre-mark the sticker and GIF stores loaded so opening the panel (which
    // calls loadIfNeeded on them) never fires a real TdClient query that would
    // leave a dangling future and hang test teardown. Individual tests that
    // need specific content override these with their own *ForTest calls.
    StickerStore.shared.replacePacksForTest(const []);
    GifStore.shared.replaceItemsForTest(const []);
  });

  tearDown(() {
    EmojiRecentsStore.shared.resetForTesting();
    EmojiStore.shared.reset();
    StickerStore.shared.reset();
    GifStore.shared.replaceItemsForTest(const []);
  });

  testWidgets('one media button opens the panel with the segmented selector', (
    tester,
  ) async {
    await _pumpMobileComposer(tester);

    // Exactly one media entry: the former sticker grip button is gone.
    expect(_mediaButton, findsOneWidget);
    expect(find.byIcon(HeroAppIcons.grip.data), findsNothing);
    expect(_segments, findsNothing);

    await tester.tap(_mediaButton);
    await tester.pump();

    expect(_segments, findsOneWidget);
    for (final kind in ['emoji', 'sticker', 'gif']) {
      expect(
        find.byKey(ValueKey('mediaSegment-$kind')),
        findsOneWidget,
        reason: 'missing $kind segment',
      );
    }
    // The panel opens on the emoji segment, with the #197 emoji strip.
    expect(_emojiTabs, findsOneWidget);
    expect(_stickerTabs, findsNothing);
    expect(_gifTabs, findsNothing);

    // Tapping the toolbar button again closes the panel.
    await tester.tap(_mediaButton);
    await tester.pump();
    expect(_segments, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switching segments swaps the secondary strip and content', (
    tester,
  ) async {
    final store = StickerStore.shared;
    store.replacePacksForTest([
      StickerPack(
        id: StickerStore.recentPackId,
        title: 'Recent',
        loaded: true,
        stickers: const [
          StickerItem(id: 900, width: 128, height: 128, emoji: '🙂'),
        ],
      ),
    ]);
    final gifStore = GifStore.shared;
    final originalGifs = gifStore.items;
    gifStore.replaceItemsForTest([
      GifItem(
        id: 901,
        duration: 2,
        width: 320,
        height: 180,
        mimeType: 'video/mp4',
        file: TdFileRef(id: 901),
      ),
    ]);
    addTearDown(() => gifStore.replaceItemsForTest(originalGifs));

    await _pumpMobileComposer(
      tester,
      gifPreviewBuilder: (_) => const SizedBox.expand(),
    );
    await tester.tap(_mediaButton);
    await tester.pump();
    expect(_emojiTabs, findsOneWidget);

    // Emoji -> Stickers: the sticker pack strip and grid take over.
    await tester.tap(find.byKey(const ValueKey('mediaSegment-sticker')));
    await tester.pump();
    expect(_stickerTabs, findsOneWidget);
    expect(_emojiTabs, findsNothing);
    expect(find.byKey(const ValueKey('sticker-900')), findsOneWidget);

    // Stickers -> GIF: the saved-GIFs strip and grid take over.
    await tester.tap(find.byKey(const ValueKey('mediaSegment-gif')));
    await tester.pump();
    expect(_gifTabs, findsOneWidget);
    expect(_stickerTabs, findsNothing);
    expect(find.byKey(const ValueKey('gif-901')), findsOneWidget);

    // GIF -> Emoji restores the emoji region.
    await tester.tap(find.byKey(const ValueKey('mediaSegment-emoji')));
    await tester.pump();
    expect(_emojiTabs, findsOneWidget);
    expect(_gifTabs, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('each segment keeps its own search tab over the shared field', (
    tester,
  ) async {
    await _pumpMobileComposer(tester);
    await tester.tap(_mediaButton);
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('emojiSearchTab')));
    await tester.pump();
    expect(_search, findsOneWidget);

    // The sticker segment starts on its content tabs, not search.
    await tester.tap(find.byKey(const ValueKey('mediaSegment-sticker')));
    await tester.pump();
    expect(_search, findsNothing);
    await tester.tap(find.byKey(const ValueKey('stickerSearchTab')));
    await tester.pump();
    expect(_search, findsOneWidget);

    // GIF shares the sticker tab id, so its search tab picks the selection up.
    await tester.tap(find.byKey(const ValueKey('mediaSegment-gif')));
    await tester.pump();
    expect(_search, findsOneWidget);
    expect(_gifTabs, findsOneWidget);

    // Returning to the saved-GIFs tab hides the field again.
    await tester.tap(find.byKey(const ValueKey('gifSavedTab')));
    await tester.pump();
    expect(_search, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('sending a sticker from the unified panel closes it', (
    tester,
  ) async {
    final store = StickerStore.shared;
    store.replacePacksForTest([
      StickerPack(
        id: StickerStore.recentPackId,
        title: 'Recent',
        loaded: true,
        stickers: const [
          StickerItem(id: 902, width: 128, height: 128, emoji: '🙂'),
        ],
      ),
    ]);
    var sentCallbacks = 0;
    await _pumpMobileComposer(tester, onMessageSent: () => sentCallbacks++);

    await tester.tap(_mediaButton);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('mediaSegment-sticker')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sticker-902')));
    await tester.pump();
    await tester.pump();

    expect(sentCallbacks, 1);
    expect(_segments, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop renders the unified panel in a single popover', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);

    final vm = _UnifiedPanelTestViewModel();
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
          platform: TargetPlatform.macOS,
          extensions: [AppColors.light],
        ),
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SizedBox(
              width: 760,
              child: ChatInputBar(
                vm: vm,
                quickRepliesEnabled: false,
                onStartCall: (_) {},
                onMessageSent: () {},
              ),
            ),
          ),
        ),
      ),
    );

    final action = find.byKey(const ValueKey('desktopComposerMediaAction'));
    expect(action, findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktopComposerStickerAction')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('desktopComposerEmojiAction')),
      findsNothing,
    );

    await tester.tap(action);
    await tester.pump();
    expect(find.byKey(const ValueKey('desktopMediaPopover')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktopMediaPopoverContent')),
      findsOneWidget,
    );
    expect(_segments, findsOneWidget);

    // Segments work inside the desktop popover too.
    await tester.tap(find.byKey(const ValueKey('mediaSegment-sticker')));
    await tester.pump();
    expect(_stickerTabs, findsOneWidget);

    // Tapping the toolbar button's location again closes the popover; the
    // open popover's dismiss layer intercepts the tap, so target it by
    // coordinates like the older desktop popover tests did.
    await tester.tapAt(tester.getCenter(action));
    await tester.pump();
    expect(find.byKey(const ValueKey('desktopMediaPopover')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('RTL lays out segments right-to-left without overflow', (
    tester,
  ) async {
    await _pumpMobileComposer(tester, textDirection: TextDirection.rtl);
    await tester.tap(_mediaButton);
    await tester.pump();

    final emoji = tester.getCenter(
      find.byKey(const ValueKey('mediaSegment-emoji')),
    );
    final sticker = tester.getCenter(
      find.byKey(const ValueKey('mediaSegment-sticker')),
    );
    final gif = tester.getCenter(
      find.byKey(const ValueKey('mediaSegment-gif')),
    );
    // RTL: the first segment (emoji) sits at the right edge.
    expect(emoji.dx, greaterThan(sticker.dx));
    expect(sticker.dx, greaterThan(gif.dx));
    // Segments still fit inside the panel width with no render overflow.
    expect(tester.takeException(), isNull);
  });

  testWidgets('a large text scaler shrinks segment labels without overflow', (
    tester,
  ) async {
    await _pumpMobileComposer(tester, textScaler: const TextScaler.linear(1.6));
    await tester.tap(_mediaButton);
    await tester.pump();

    expect(_segments, findsOneWidget);
    for (final kind in ['emoji', 'sticker', 'gif']) {
      expect(
        find.byKey(ValueKey('mediaSegment-$kind')),
        findsOneWidget,
        reason: 'missing $kind segment at large text',
      );
    }
    // The FittedBox keeps the pill labels on one line, so nothing overflows.
    expect(tester.takeException(), isNull);
  });
}

class _UnifiedPanelTestViewModel extends ChatViewModel {
  _UnifiedPanelTestViewModel()
    : super(chatId: 1, title: 'Test', markReadOnOpen: false);

  @override
  void sendTyping() {}

  @override
  Future<bool> currentUserIsPremium() async => true;

  @override
  Future<void> persistComposerDraft() async {}

  @override
  Future<bool> sendSticker(StickerItem sticker) async => true;

  @override
  Future<bool> sendGif(GifItem gif) async => true;
}
