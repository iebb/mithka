import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/gif_item.dart';
import 'package:mithka/chat/gif_store.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/sticker_item.dart';
import 'package:mithka/chat/sticker_store.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ControlledMediaChatViewModel extends ChatViewModel {
  _ControlledMediaChatViewModel()
    : super(chatId: 1, title: 'Test', markReadOnOpen: false);

  final stickerSend = Completer<bool>();
  final gifSend = Completer<bool>();

  @override
  Future<bool> sendSticker(StickerItem sticker) => stickerSend.future;

  @override
  Future<bool> sendGif(GifItem gif) => gifSend.future;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('unconfirmed send timeout keeps its pending message on iOS', (
    _,
  ) async {
    final vm = ChatViewModel(chatId: 1, title: 'Test', markReadOnOpen: false);
    addTearDown(vm.dispose);

    await vm.waitForMessageSendTimeoutForTest(
      123,
      timeout: const Duration(milliseconds: 1),
    );

    expect(vm.isPendingMessageDiscardedForTest(123), isFalse);
  });

  testWidgets('composer media panels and sticker send work on iOS', (
    tester,
  ) async {
    final vm = _ControlledMediaChatViewModel();
    addTearDown(vm.dispose);
    final store = StickerStore.shared;
    store.replacePacksForTest([
      StickerPack(
        id: StickerStore.recentPackId,
        title: 'Recent',
        loaded: true,
        stickers: const [
          StickerItem(id: 100, width: 128, height: 128, emoji: '🙂'),
        ],
      ),
    ]);
    addTearDown(store.reset);
    final gifStore = GifStore.shared;
    final originalGifs = gifStore.items;
    gifStore.replaceItemsForTest([
      GifItem(
        id: 200,
        duration: 2,
        width: 320,
        height: 180,
        mimeType: 'video/mp4',
        file: TdFileRef(id: 200),
      ),
    ]);
    addTearDown(() => gifStore.replaceItemsForTest(originalGifs));
    var panelGeometryChanges = 0;
    var mediaSendTaps = 0;
    var messageSentCallbacks = 0;
    var panelWasClosedBeforeSendCallback = false;

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              vm: vm,
              onStartCall: (_) {},
              gifPreviewBuilder: (_) => const SizedBox.expand(),
              onPanelGeometryChanged: () => panelGeometryChanges++,
              onMediaSendTapped: () => mediaSendTaps++,
              onMessageSent: () {
                messageSentCallbacks++;
                panelWasClosedBeforeSendCallback = find
                    .byKey(const ValueKey('stickerPanelTabs'))
                    .evaluate()
                    .isEmpty;
              },
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byIcon(HeroAppIcons.grip.data));
    await tester.pump();
    final stickerTabs = find.byKey(const ValueKey('stickerPanelTabs'));
    final search = find.byKey(const ValueKey('composerMediaSearch'));
    expect(stickerTabs, findsOneWidget);
    expect(search, findsNothing);
    expect(find.byIcon(HeroAppIcons.palette.data), findsNothing);
    expect(panelGeometryChanges, 1);

    await tester.tap(find.byKey(const ValueKey('stickerSearchTab')));
    await tester.pump();
    expect(search, findsOneWidget);
    expect(
      tester.getTopLeft(stickerTabs).dy,
      lessThan(tester.getTopLeft(search).dy),
    );

    await tester.tap(find.byIcon(HeroAppIcons.clock.data));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('sticker-100')));
    await tester.pump();
    expect(mediaSendTaps, 1);
    expect(messageSentCallbacks, 0);
    expect(stickerTabs, findsOneWidget);

    vm.stickerSend.complete(true);
    await tester.pump();
    await tester.pump();
    expect(messageSentCallbacks, 1);
    expect(panelWasClosedBeforeSendCallback, isTrue);
    expect(panelGeometryChanges, 2);

    await tester.tap(find.byIcon(HeroAppIcons.grip.data));
    await tester.pump();
    await tester.tap(find.byIcon(HeroAppIcons.gif.data));
    await tester.pump();
    expect(find.byKey(const ValueKey('gif-200')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('gif-200')));
    await tester.pump();
    expect(mediaSendTaps, 2);
    expect(messageSentCallbacks, 1);
    expect(stickerTabs, findsOneWidget);

    vm.gifSend.complete(true);
    await tester.pump();
    await tester.pump();
    expect(messageSentCallbacks, 2);
    expect(panelWasClosedBeforeSendCallback, isTrue);
    expect(panelGeometryChanges, 4);

    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pump();
    final emojiTabs = find.byKey(const ValueKey('emojiPanelTabs'));
    expect(emojiTabs, findsOneWidget);
    expect(search, findsNothing);
    expect(panelGeometryChanges, 5);

    await tester.tap(find.byKey(const ValueKey('emojiSearchTab')));
    await tester.pump();
    expect(search, findsOneWidget);
    expect(
      tester.getTopLeft(emojiTabs).dy,
      lessThan(tester.getTopLeft(search).dy),
    );

    await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
    await tester.pump();
    expect(panelGeometryChanges, 6);
  });

  testWidgets('GIF preview text is not rendered as a media caption on iOS', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    final gifPreview = TDParse.messageText({
      '@type': 'messageAnimation',
      'caption': {'@type': 'formattedText', 'text': ''},
    });

    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageBubble(
              message: ChatMessage(
                id: 2,
                isOutgoing: true,
                text: gifPreview,
                date: 1,
                contentType: 'messageAnimation',
                video: TdFileRef(id: 21),
                videoDuration: 25,
                imageWidth: 320,
                imageHeight: 240,
              ),
              peerTitle: 'Test',
              isGroup: false,
            ),
          ),
        ),
      ),
    );

    expect(gifPreview, '[GIF]');
    expect(find.text(gifPreview), findsNothing);
    expect(find.text('0:25'), findsOneWidget);
  });
}
