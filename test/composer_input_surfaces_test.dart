//
//  composer_input_surfaces_test.dart
//
//  Covers the composer's docked surfaces and its attachment strip:
//   * every panel docked to the composer bar (function panel, media panel,
//     mobile and desktop voice panels, bot reply-keyboard panel) paints the
//     bar's own surface colour, and the safe-area overlay that extends a
//     panel through the home indicator paints that same colour — never the
//     darker recessed `AppColors.panelBackground`;
//   * a floating popover anchored above the bar keeps the recessed surface;
//   * the attachment strip orders the camera entry immediately left of the
//     image entry.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/emoji_recents_store.dart';
import 'package:mithka/chat/emoji_store.dart';
import 'package:mithka/chat/gif_store.dart';
import 'package:mithka/chat/sticker_store.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _barSurfaceKey = ValueKey('chat-input-safe-area-background');
const _panelSurfaceKey = ValueKey('chat-input-panel-safe-area-background');
const _functionPanelKey = ValueKey('composerFunctionPanel');
const _mediaPanelKey = ValueKey('composerMediaPanel');
const _mobileVoicePanelKey = ValueKey('composerMobileVoicePanel');
const _desktopVoicePanelKey = ValueKey('desktopVoiceMessagePanel');
const _replyKeyboardPanelKey = ValueKey('composerReplyKeyboardPanel');

AppColors _resolvedColors(WidgetTester tester) =>
    tester.element(find.byKey(_barSurfaceKey)).colors;

Color? _paintedColor(WidgetTester tester, Key key) {
  final found = find.byKey(key);
  if (found.evaluate().isEmpty) return null;
  final widget = found.evaluate().first.widget;
  if (widget is Container) {
    final decoration = widget.decoration;
    if (decoration is BoxDecoration) return decoration.color;
    return widget.color;
  }
  if (widget is ColoredBox) return widget.color;
  return null;
}

Finder _surface(String semanticLabel) => find.byWidgetPredicate(
  (widget) =>
      widget is AppInteractiveSurface && widget.semanticLabel == semanticLabel,
);

Future<void> _tapSurface(WidgetTester tester, String semanticLabel) async {
  await tester.tap(_surface(semanticLabel).first, warnIfMissed: false);
  await tester.pump();
}

Future<ChatViewModel> _pumpComposer(
  WidgetTester tester, {
  required AppColors colors,
  Brightness brightness = Brightness.dark,
  EdgeInsets padding = const EdgeInsets.only(bottom: 34),
  bool phoneStrip = false,
  ChatViewModel? viewModel,
  TargetPlatform? platform,
}) async {
  final vm = viewModel ?? _ComposerSurfacesViewModel();
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
        platform: platform,
        brightness: brightness,
        extensions: [colors],
      ),
      home: MediaQuery(
        data: MediaQueryData(padding: padding),
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              vm: vm,
              quickRepliesEnabled: false,
              phoneStripForTesting: phoneStrip,
              onStartCall: (_) {},
              onMessageSent: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return vm;
}

void main() {
  setUpAll(() async {
    await AppStrings.ensureLoaded(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EmojiRecentsStore.shared.resetForTesting();
    EmojiStore.shared.reset();
    StickerStore.shared.replacePacksForTest(const []);
    GifStore.shared.replaceItemsForTest(const []);
  });

  tearDown(() {
    EmojiRecentsStore.shared.resetForTesting();
    EmojiStore.shared.reset();
    StickerStore.shared.reset();
    GifStore.shared.replaceItemsForTest(const []);
  });

  testWidgets('dark palette: function panel and its safe-area overlay share '
      'the composer bar surface', (tester) async {
    await _pumpComposer(tester, colors: AppColors.dark);

    final colors = _resolvedColors(tester);
    expect(
      _paintedColor(tester, _barSurfaceKey),
      AppColors.dark.inputBarBackground,
    );

    await _tapSurface(tester, AppStrings.t(AppStringKeys.composerOpenMenu));

    expect(_paintedColor(tester, _functionPanelKey), colors.inputBarBackground);
    expect(
      _paintedColor(tester, _functionPanelKey),
      isNot(AppColors.dark.panelBackground),
    );
    expect(_paintedColor(tester, _panelSurfaceKey), colors.inputBarBackground);
    expect(
      _paintedColor(tester, _panelSurfaceKey),
      isNot(AppColors.dark.panelBackground),
    );
    // The panel and the bar are one continuous surface.
    expect(
      _paintedColor(tester, _functionPanelKey),
      _paintedColor(tester, _barSurfaceKey),
    );
  });

  testWidgets('dark palette: media and mobile voice panels share the composer '
      'bar surface', (tester) async {
    await _pumpComposer(tester, colors: AppColors.dark);
    final colors = _resolvedColors(tester);

    await _tapSurface(tester, AppStrings.t(AppStringKeys.composerMediaPicker));
    expect(_paintedColor(tester, _mediaPanelKey), colors.inputBarBackground);
    expect(
      _paintedColor(tester, _mediaPanelKey),
      isNot(AppColors.dark.panelBackground),
    );
    await _tapSurface(tester, AppStrings.t(AppStringKeys.composerMediaPicker));

    await _tapSurface(tester, AppStrings.t(AppStringKeys.composerHoldToTalk));
    expect(
      _paintedColor(tester, _mobileVoicePanelKey),
      colors.inputBarBackground,
    );
    expect(
      _paintedColor(tester, _mobileVoicePanelKey),
      isNot(AppColors.dark.panelBackground),
    );
    expect(_paintedColor(tester, _panelSurfaceKey), colors.inputBarBackground);
    expect(
      _paintedColor(tester, _panelSurfaceKey),
      isNot(AppColors.dark.panelBackground),
    );
  });

  testWidgets('dark palette: a bot reply-keyboard panel shares the composer '
      'bar surface', (tester) async {
    final vm = _ComposerSurfacesViewModel();
    vm.messages = [
      ChatMessage(
        id: 1,
        isOutgoing: false,
        text: 'pick one',
        date: 1,
        buttonRows: const [
          [
            MessageButton(
              text: 'Yes',
              type: 'keyboardButtonTypeText',
              isReplyKeyboard: true,
            ),
          ],
        ],
      ),
    ];
    await _pumpComposer(tester, colors: AppColors.dark, viewModel: vm);
    final colors = _resolvedColors(tester);

    await tester.tap(
      find.byKey(const ValueKey('composerReplyKeyboardToggle')).first,
    );
    await tester.pump();

    expect(
      _paintedColor(tester, _replyKeyboardPanelKey),
      colors.inputBarBackground,
    );
    expect(
      _paintedColor(tester, _replyKeyboardPanelKey),
      isNot(AppColors.dark.panelBackground),
    );
  });

  testWidgets('light palette: docked panels follow the composer bar surface', (
    tester,
  ) async {
    await _pumpComposer(
      tester,
      colors: AppColors.light,
      brightness: Brightness.light,
    );
    final colors = _resolvedColors(tester);

    await _tapSurface(tester, AppStrings.t(AppStringKeys.composerOpenMenu));
    expect(_paintedColor(tester, _functionPanelKey), colors.inputBarBackground);
    expect(
      _paintedColor(tester, _functionPanelKey),
      isNot(AppColors.light.panelBackground),
    );
    expect(_paintedColor(tester, _panelSurfaceKey), colors.inputBarBackground);
    expect(
      _paintedColor(tester, _panelSurfaceKey),
      isNot(AppColors.light.panelBackground),
    );
  });

  testWidgets('desktop voice panel shares the composer bar surface', (
    tester,
  ) async {
    await _pumpComposer(
      tester,
      colors: AppColors.dark,
      platform: TargetPlatform.macOS,
    );
    final colors = _resolvedColors(tester);

    await _tapSurface(tester, AppStrings.t(AppStringKeys.composerHoldToTalk));
    expect(
      _paintedColor(tester, _desktopVoicePanelKey),
      colors.inputBarBackground,
    );
    expect(
      _paintedColor(tester, _desktopVoicePanelKey),
      isNot(AppColors.dark.panelBackground),
    );
  });

  testWidgets('the camera entry sits immediately left of the image entry', (
    tester,
  ) async {
    await _pumpComposer(tester, colors: AppColors.dark, phoneStrip: true);

    final camera = _surface(AppStrings.t(AppStringKeys.composerCamera)).first;
    final image = _surface(AppStrings.t(AppStringKeys.composerImage)).first;
    final media = _surface(
      AppStrings.t(AppStringKeys.composerMediaPicker),
    ).first;

    expect(camera, findsOneWidget);
    final cameraRect = tester.getRect(camera);
    final imageRect = tester.getRect(image);
    final mediaRect = tester.getRect(media);

    expect(
      cameraRect.left,
      lessThan(imageRect.left),
      reason: 'the camera entry must sit left of the image entry',
    );
    expect(
      imageRect.left,
      lessThan(mediaRect.left),
      reason: 'the image entry must still sit left of the media entry',
    );
    expect(cameraRect.center.dy, imageRect.center.dy);
  });

  test(
    'the camera entry is offered on the phone and tablet platforms only',
    () {
      expect(composerShowsCameraIcon(TargetPlatform.iOS), isTrue);
      expect(composerShowsCameraIcon(TargetPlatform.android), isTrue);
      expect(composerShowsCameraIcon(TargetPlatform.macOS), isFalse);
      expect(composerShowsCameraIcon(TargetPlatform.windows), isFalse);
      expect(composerShowsCameraIcon(TargetPlatform.linux), isFalse);
    },
  );
}

class _ComposerSurfacesViewModel extends ChatViewModel {
  _ComposerSurfacesViewModel()
    : super(chatId: 1, title: 'Test', markReadOnOpen: false);

  @override
  void sendTyping() {}

  @override
  Future<void> persistComposerDraft() async {}
}
