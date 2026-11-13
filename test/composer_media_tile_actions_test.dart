//
//  composer_media_tile_actions_test.dart
//
//  Long-press on a sticker or GIF tile in the unified media panel opens the
//  media-tile action sheet wired to the real composer actions: the sheet's
//  send/silent-send rows route through the view model, the recents pseudo-pack
//  is the only place the delete-from-recent row appears, the favorites section
//  renders ahead of every pack when favorites exist, and its tiles offer
//  remove-from-favorites instead.
//

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/favorite_sticker_store.dart';
import 'package:mithka/chat/gif_item.dart';
import 'package:mithka/chat/gif_store.dart';
import 'package:mithka/chat/message_send_options.dart';
import 'package:mithka/chat/sticker_item.dart';
import 'package:mithka/chat/sticker_store.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts sendSticker/sendGif calls and captures the handed-in configuration
/// the way the integration harness does, without a real TDLib round trip.
class _SpyChatViewModel extends ChatViewModel {
  _SpyChatViewModel() : super(chatId: 1, title: 'Test', markReadOnOpen: false);

  int stickerSends = 0;
  int gifSends = 0;
  final List<MessageSendConfiguration?> stickerConfigurations = [];

  @override
  Future<bool> sendSticker(
    StickerItem sticker, {
    MessageSendConfiguration? sendConfiguration,
  }) async {
    stickerSends++;
    stickerConfigurations.add(sendConfiguration);
    return true;
  }

  @override
  Future<bool> sendGif(
    GifItem gif, {
    MessageSendConfiguration? sendConfiguration,
  }) async {
    gifSends++;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final supportDir = await Directory.systemTemp.createTemp(
      'mithka_media_tile_actions',
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
        'getFavoriteStickers' => {
          '@type': 'stickers',
          'stickers': <Map<String, dynamic>>[],
        },
        _ => {'@type': 'ok'},
      },
    );
    final slot = TdClient.shared.addSlot();
    final clientId = TdClient.shared.clientId(slot);
    TdClient.shared.debugSetActiveAccountForTesting(slot, clientId ?? 0);
  });

  setUp(() async {
    FavoriteStickerStore.shared.resetForTest();
    // The switch on + an extras preference makes the favorites section real:
    // server favorites stay empty (the query override answers none) while the
    // locally saved extras render.
    SharedPreferences.setMockInitialValues({
      FavoriteStickerStore.unlimitedPreferenceKey: true,
      'mithka.faveStickers.v1.user.7': '[[7001, null, 128, 128, "⭐", 0, 0, 0]]',
    });
    final prefs = await SharedPreferences.getInstance();
    FavoriteStickerStore.shared.initialize(prefs);
    FavoriteStickerStore.shared.setActiveAccountUserId(7);
  });

  tearDown(() {
    FavoriteStickerStore.shared.resetForTest();
    StickerStore.shared.reset();
    GifStore.shared.replaceItemsForTest(const []);
  });

  testWidgets('long-pressing a sticker tile opens the action sheet', (
    tester,
  ) async {
    await _pumpComposer(tester);
    await _openPanelAndScrollToSticker(tester, 'sticker-4101');

    final tile = find.byKey(const ValueKey('sticker-4101'));
    await tester.longPress(tile, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mediaTileAction-send')), findsOneWidget);
    // A normal pack tile is not a recent tile: no delete-from-recent row.
    expect(
      find.byKey(const ValueKey('mediaTileAction-removeFromRecent')),
      findsNothing,
    );
    // Panels can only long-press when wired: viewSet renders because the
    // seeded item carries a set id.
    expect(
      find.byKey(const ValueKey('mediaTileAction-viewSet')),
      findsOneWidget,
    );
  });

  testWidgets('a recents tile offers the delete-from-recent row', (
    tester,
  ) async {
    await _pumpComposer(tester);
    await _openPanelAndScrollToSticker(tester, 'sticker-1001');

    await tester.longPress(
      find.byKey(const ValueKey('sticker-1001')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mediaTileAction-send')), findsOneWidget);
    // Seven rows exceed the phone-height sheet, which scrolls: the
    // destructive row sits at the bottom of the list.
    await tester.dragUntilVisible(
      find.byKey(const ValueKey('mediaTileAction-removeFromRecent')),
      find.byType(ListView),
      const Offset(0, -64),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mediaTileAction-removeFromRecent')),
      findsOneWidget,
    );
  });

  testWidgets('the favorites section renders first with its own header', (
    tester,
  ) async {
    await _pumpComposer(tester);
    // The favorites tile sits at the very top of the sticker section, so this
    // opens the panel and lands there without scrolling past the header.
    await _openPanelAndScrollToSticker(tester, 'sticker-7001');

    final favoritesHeader = find.byKey(
      const ValueKey('mediaStickerPack-favorites'),
      skipOffstage: false,
    );
    expect(favoritesHeader, findsOneWidget);
    // Ahead of every pack: the first pack header renders below it.
    final firstPack = find.byKey(
      const ValueKey('mediaStickerPack-${StickerStore.recentPackId}'),
      skipOffstage: false,
    );
    expect(firstPack, findsOneWidget);
    expect(
      tester.getTopLeft(favoritesHeader).dy,
      lessThan(tester.getTopLeft(firstPack).dy),
    );

    // The favorites tile long-press offers remove-from-favorites (not add,
    // not delete-from-recent): the store knows the id already.
    await tester.longPress(
      find.byKey(const ValueKey('sticker-7001')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    final removeLabel = AppStrings.t(
      AppStringKeys.mediaTileRemoveFromFavorites,
    );
    expect(find.text(removeLabel), findsOneWidget);
    expect(
      find.byKey(const ValueKey('mediaTileAction-removeFromRecent')),
      findsNothing,
    );
  });

  testWidgets('tapping send in the sheet pops it and sends via the vm', (
    tester,
  ) async {
    final vm = _SpyChatViewModel();
    await _pumpComposer(tester, vm: vm);
    await _openPanelAndScrollToSticker(tester, 'sticker-4101');

    await tester.longPress(
      find.byKey(const ValueKey('sticker-4101')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mediaTileAction-send')));
    await tester.pumpAndSettle();

    expect(vm.stickerSends, 1);
    expect(vm.stickerConfigurations.single, isNull);
    expect(find.byKey(const ValueKey('mediaTileAction-send')), findsNothing);
  });

  testWidgets('sendWithoutSound arms a silent configuration', (tester) async {
    final vm = _SpyChatViewModel();
    await _pumpComposer(tester, vm: vm);
    await _openPanelAndScrollToSticker(tester, 'sticker-4101');

    await tester.longPress(
      find.byKey(const ValueKey('sticker-4101')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('mediaTileAction-sendWithoutSound')),
    );
    await tester.pumpAndSettle();

    expect(vm.stickerSends, 1);
    final captured = vm.stickerConfigurations.single;
    expect(captured, isNotNull);
    expect(captured!.disableNotification, isTrue);
  });

  testWidgets('a gif tile sheet has send and save but no viewSet', (
    tester,
  ) async {
    await _pumpComposer(tester);
    await _openPanelAndScrollToSticker(tester, 'sticker-4101');
    GifStore.shared.replaceItemsForTest([
      GifItem(
        id: 200,
        duration: 2,
        width: 320,
        height: 180,
        mimeType: 'video/mp4',
        file: TdFileRef(id: 200, localPath: 'pubspec.yaml'),
        thumbnail: TdFileRef(id: 9201, localPath: 'assets/penguin.png'),
      ),
    ]);
    await tester.pump();

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('gif-200')),
      300,
      scrollable: _panelScrollable(),
    );
    await tester.pump();
    await tester.longPress(
      find.byKey(const ValueKey('gif-200')),
      warnIfMissed: false,
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('mediaTileAction-send')), findsOneWidget);
    expect(find.byKey(const ValueKey('mediaTileAction-save')), findsOneWidget);
    expect(find.byKey(const ValueKey('mediaTileAction-viewSet')), findsNothing);
    expect(
      find.byKey(const ValueKey('mediaTileAction-removeFromRecent')),
      findsNothing,
    );
  });
}

Finder _panelScrollable() => find.descendant(
  of: find.byKey(const ValueKey('mediaUnifiedScroll')),
  matching: find.byType(Scrollable),
);

Future<void> _pumpComposer(WidgetTester tester, {ChatViewModel? vm}) async {
  vm ??= ChatViewModel(chatId: 1, title: 'Test', markReadOnOpen: false);
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

/// Opens the media panel on the sticker segment and walks the unified scroll
/// down to the given sticker tile so it is on screen and long-pressable.
Future<void> _openPanelAndScrollToSticker(
  WidgetTester tester,
  String tileKey,
) async {
  await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
  await tester.pump();
  _seedStickerPacks();
  await tester.pump();
  await tester.tap(find.byKey(const ValueKey('mediaSegment-sticker')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await tester.scrollUntilVisible(
    find.byKey(ValueKey(tileKey)),
    200,
    scrollable: _panelScrollable(),
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
        StickerItem(
          id: 4101,
          width: 128,
          height: 128,
          emoji: '😀',
          setId: 3101,
        ),
        StickerItem(id: 4102, width: 128, height: 128, emoji: '😃'),
      ],
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
