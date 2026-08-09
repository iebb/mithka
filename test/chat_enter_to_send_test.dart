import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/telegram_ai_service.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';

class _EnterToSendViewModel extends ChatViewModel {
  _EnterToSendViewModel()
    : super(chatId: 1, title: 'Test', markReadOnOpen: false);

  final sentTexts = <String>[];

  @override
  void sendTyping() {}

  @override
  void setDraft(
    String value, {
    String? formattedText,
    List<Map<String, dynamic>> entities = const [],
  }) {
    draft = value;
  }

  @override
  Future<bool> prepareMessageSend() async => true;

  @override
  Future<bool> currentUserIsPremium() async => true;

  @override
  Future<bool> sendFormatted(
    String text,
    List<Map<String, dynamic>> entities,
  ) async {
    sentTexts.add(text);
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Android IME fallback accepts only an unmodified terminal newline', () {
    const oldValue = TextEditingValue(
      text: 'hello',
      selection: TextSelection.collapsed(offset: 5),
    );
    const terminalNewline = TextEditingValue(
      text: 'hello\n',
      selection: TextSelection.collapsed(offset: 6),
    );

    expect(
      isComposerImeEnterFallback(
        oldValue,
        terminalNewline,
        shiftPressed: false,
        controlPressed: false,
      ),
      isTrue,
    );
    expect(
      isComposerImeEnterFallback(
        oldValue,
        terminalNewline,
        shiftPressed: true,
        controlPressed: false,
      ),
      isFalse,
    );
    expect(
      isComposerImeEnterFallback(
        oldValue,
        terminalNewline,
        shiftPressed: false,
        controlPressed: true,
      ),
      isFalse,
    );
    expect(
      isComposerImeEnterFallback(
        oldValue,
        const TextEditingValue(
          text: 'hello\nworld',
          selection: TextSelection.collapsed(offset: 11),
        ),
        shiftPressed: false,
        controlPressed: false,
      ),
      isFalse,
    );
  });

  testWidgets('enabled Android composer sends from the software action', (
    tester,
  ) async {
    final vm = await _pumpComposer(tester, enterToSend: true);
    final field = find.byType(TextField);

    expect(
      tester.widget<TextField>(field).textInputAction,
      TextInputAction.send,
    );
    await tester.tap(field);
    await tester.enterText(field, 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.send);
    await tester.pump();

    expect(vm.sentTexts, ['hello']);
    expect(tester.widget<TextField>(field).controller?.text, isEmpty);
  });

  testWidgets('disabled Android composer keeps the software newline action', (
    tester,
  ) async {
    final vm = await _pumpComposer(tester, enterToSend: false);
    final field = find.byType(TextField);

    expect(
      tester.widget<TextField>(field).textInputAction,
      TextInputAction.newline,
    );
    await tester.tap(field);
    await tester.enterText(field, 'hello');
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.pump();

    expect(vm.sentTexts, isEmpty);
    expect(tester.widget<TextField>(field).controller?.text, 'hello');
  });

  testWidgets('enabled Android composer handles an IME newline fallback once', (
    tester,
  ) async {
    final vm = await _pumpComposer(tester, enterToSend: true);
    final field = find.byType(TextField);

    await tester.tap(field);
    await tester.enterText(field, 'hello');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'hello\n',
        selection: TextSelection.collapsed(offset: 6),
      ),
    );
    await tester.pump();

    expect(vm.sentTexts, ['hello']);
    expect(tester.widget<TextField>(field).controller?.text, isEmpty);
  });

  testWidgets('Android IME fallback preserves a multiline edit', (
    tester,
  ) async {
    final vm = await _pumpComposer(tester, enterToSend: true);
    final field = find.byType(TextField);

    await tester.tap(field);
    await tester.enterText(field, 'hello');
    tester.testTextInput.updateEditingValue(
      const TextEditingValue(
        text: 'hello\nworld',
        selection: TextSelection.collapsed(offset: 11),
      ),
    );
    await tester.pump();

    expect(vm.sentTexts, isEmpty);
    expect(tester.widget<TextField>(field).controller?.text, 'hello\nworld');
  });

  testWidgets('enabled physical Enter sends but Ctrl-Enter does not', (
    tester,
  ) async {
    final vm = await _pumpComposer(tester, enterToSend: true);
    final field = find.byType(TextField);

    await tester.tap(field);
    await tester.enterText(field, 'first');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(vm.sentTexts, ['first']);

    await tester.enterText(field, 'second');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(vm.sentTexts, ['first']);
    expect(tester.widget<TextField>(field).controller?.text, 'second\n');
  });

  testWidgets('disabled physical Ctrl-Enter sends but Enter does not', (
    tester,
  ) async {
    final vm = await _pumpComposer(tester, enterToSend: false);
    final field = find.byType(TextField);

    await tester.tap(field);
    await tester.enterText(field, 'first');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(vm.sentTexts, isEmpty);
    expect(tester.widget<TextField>(field).controller?.text, 'first\n');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(vm.sentTexts, ['first\n']);
  });

  testWidgets('native desktop uses a compact toolbar above a flat composer', (
    tester,
  ) async {
    await _pumpComposer(
      tester,
      enterToSend: false,
      platform: TargetPlatform.macOS,
      aiCompositionSupported: true,
      includeSenderOptions: true,
    );

    final toolbar = find.byKey(const ValueKey('desktopComposerToolbar'));
    final input = find.byKey(const ValueKey('desktopComposerInput'));
    final inputBox = find.byKey(const ValueKey('composerTextInputBox'));
    final field = find.byType(TextField);

    expect(toolbar, findsOneWidget);
    expect(input, findsOneWidget);
    expect(tester.getSize(toolbar).height, 41);
    expect(
      tester.getTopLeft(toolbar).dy,
      lessThan(tester.getTopLeft(input).dy),
    );
    expect(
      tester.getSize(find.byKey(const ValueKey('desktopComposerEmojiAction'))),
      const Size.square(32),
    );
    final richTextAction = find.byKey(
      const ValueKey('desktopComposerRichTextAction'),
    );
    final aiReplyAction = find.byKey(
      const ValueKey('desktopComposerAiReplyAction'),
    );
    final aiEditorAction = find.byKey(
      const ValueKey('desktopComposerAiEditorAction'),
    );
    expect(richTextAction, findsOneWidget);
    expect(aiReplyAction, findsOneWidget);
    expect(aiEditorAction, findsOneWidget);
    expect(
      tester.widget<AppInteractiveSurface>(richTextAction).enabled,
      isTrue,
    );
    expect(
      tester.widget<AppInteractiveSurface>(aiReplyAction).enabled,
      isFalse,
    );
    expect(
      tester.widget<AppInteractiveSurface>(aiEditorAction).enabled,
      isFalse,
    );
    expect(find.byKey(const ValueKey('composerAiReplyButton')), findsNothing);
    expect(find.byKey(const ValueKey('composerAiPrefixButton')), findsNothing);
    final desktopSender = find.byKey(
      const ValueKey('desktopComposerSenderPicker'),
    );
    expect(desktopSender, findsOneWidget);
    expect(find.byKey(const ValueKey('composerSenderPicker')), findsNothing);
    expect(
      tester.widget<AppInteractiveSurface>(desktopSender).semanticLabel,
      'Send: Me',
    );

    final decoration = tester.widget<Container>(inputBox).decoration;
    expect(decoration, isA<BoxDecoration>());
    expect((decoration! as BoxDecoration).color, isNull);
    final textField = tester.widget<TextField>(field);
    expect(textField.minLines, isNull);
    expect(textField.maxLines, isNull);
    expect(textField.expands, isTrue);
    expect(textField.textInputAction, TextInputAction.newline);
    expect(
      textField.style?.fontSize,
      AppTextSize.messageBody(TargetPlatform.macOS),
    );

    await tester.tap(field);
    await tester.enterText(field, 'hello\nworld');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('desktopComposerSendButton')),
      findsOneWidget,
    );
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('desktopComposerShortcutHint')),
          )
          .data,
      'Ctrl+Enter',
    );
    expect(
      tester.widget<AppInteractiveSurface>(aiEditorAction).enabled,
      isTrue,
    );
    expect(find.byKey(const ValueKey('composerAiPrefixButton')), findsNothing);

    final resizeHandle = find.byKey(
      const ValueKey('desktopComposerResizeHandle'),
    );
    expect(resizeHandle, findsOneWidget);
    expect(tester.getSize(resizeHandle).height, 8);
    expect(
      tester.getTopLeft(resizeHandle).dy,
      closeTo(tester.getTopLeft(toolbar).dy, 0.01),
    );
    expect(
      find.byKey(const ValueKey('desktopComposerResizeIndicator')),
      findsNothing,
    );
  });

  testWidgets(
    'desktop bot controls stay in the toolbar and leave a full-width editor',
    (tester) async {
      await _pumpComposer(
        tester,
        enterToSend: false,
        platform: TargetPlatform.macOS,
        composerWidth: 700,
        includeReplyKeyboardWebApp: true,
      );

      final toolbar = find.byKey(const ValueKey('desktopComposerToolbar'));
      final miniApp = find.byKey(
        const ValueKey('desktopComposerMiniAppAction'),
      );
      final keyboard = find.byKey(
        const ValueKey('desktopComposerReplyKeyboardAction'),
      );
      expect(find.descendant(of: toolbar, matching: miniApp), findsOneWidget);
      expect(find.descendant(of: toolbar, matching: keyboard), findsOneWidget);
      expect(
        tester.widget<AppInteractiveSurface>(miniApp).semanticLabel,
        'Launch Mini App',
      );
      expect(
        tester.widget<AppInteractiveSurface>(keyboard).semanticLabel,
        'Show bot keyboard',
      );
      expect(
        find.byKey(const ValueKey('desktopComposerBotMenuAction')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('composerReplyKeyboardMiniAppAction')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('composerReplyKeyboardToggle')),
        findsNothing,
      );

      final editorRow = find.byKey(
        const ValueKey('desktopComposerFullWidthEditorRow'),
      );
      final inputBox = find.byKey(const ValueKey('composerTextInputBox'));
      final field = find.byType(TextField);
      expect(tester.getSize(inputBox).width, tester.getSize(editorRow).width);
      expect(
        tester.getSize(field).width,
        closeTo(tester.getSize(inputBox).width - 4, 0.01),
      );

      await tester.tap(keyboard);
      await tester.pump();
      expect(tester.widget<AppInteractiveSurface>(keyboard).selected, isTrue);
    },
  );

  testWidgets('desktop composer toolbar scrolls instead of overflowing', (
    tester,
  ) async {
    await _pumpComposer(
      tester,
      enterToSend: false,
      platform: TargetPlatform.macOS,
      composerWidth: 300,
    );

    expect(
      find.descendant(
        of: find.byKey(const ValueKey('desktopComposerToolbar')),
        matching: find.byType(SingleChildScrollView),
      ),
      findsOneWidget,
    );
    final toolbar = find.byKey(const ValueKey('desktopComposerToolbar'));
    final emoji = find.byKey(const ValueKey('desktopComposerEmojiAction'));
    expect(tester.getSize(toolbar).width, 300);
    expect(
      tester.getTopLeft(emoji).dx,
      closeTo(tester.getTopLeft(toolbar).dx + 10, 0.01),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('touch composer keeps AI editor in the input row', (
    tester,
  ) async {
    await _pumpComposer(
      tester,
      enterToSend: false,
      aiCompositionSupported: true,
      includeSenderOptions: true,
    );
    final field = find.byType(TextField);

    await tester.enterText(field, 'hello\nworld');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('composerAiPrefixButton')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('desktopComposerAiEditorAction')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('composerSenderPicker')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktopComposerSenderPicker')),
      findsNothing,
    );
  });

  testWidgets('desktop emoji action toggles the anchored popover', (
    tester,
  ) async {
    await _pumpComposer(
      tester,
      enterToSend: false,
      platform: TargetPlatform.macOS,
    );

    await tester.tapAt(
      tester.getCenter(
        find.byKey(const ValueKey('desktopComposerEmojiAction')),
      ),
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('emojiPanelTabs')), findsOneWidget);

    await tester.tapAt(
      tester.getCenter(
        find.byKey(const ValueKey('desktopComposerEmojiAction')),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('emojiPanelTabs')), findsNothing);
    expect(find.byKey(const ValueKey('composerFunctionPanel')), findsNothing);
  });

  testWidgets('enabled desktop Enter sends while Ctrl-Enter stays multiline', (
    tester,
  ) async {
    final vm = await _pumpComposer(
      tester,
      enterToSend: true,
      platform: TargetPlatform.macOS,
    );
    final field = find.byType(TextField);

    await tester.tap(field);
    await tester.enterText(field, 'first');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(vm.sentTexts, ['first']);

    await tester.enterText(field, 'second');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(vm.sentTexts, ['first']);
    expect(tester.widget<TextField>(field).controller?.text, 'second\n');
    expect(
      tester
          .widget<Text>(
            find.byKey(const ValueKey('desktopComposerShortcutHint')),
          )
          .data,
      'Enter',
    );
  });

  testWidgets('desktop Enter never sends an active IME composition', (
    tester,
  ) async {
    final vm = await _pumpComposer(
      tester,
      enterToSend: true,
      platform: TargetPlatform.macOS,
    );
    final field = find.byType(TextField);
    final controller = tester.widget<TextField>(field).controller!;

    await tester.tap(field);
    controller.value = const TextEditingValue(
      text: '候補',
      selection: TextSelection.collapsed(offset: 2),
      composing: TextRange(start: 0, end: 2),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(vm.sentTexts, isEmpty);
    expect(controller.text, '候補');

    controller.value = const TextEditingValue(
      text: '候補',
      selection: TextSelection.collapsed(offset: 2),
    );
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(vm.sentTexts, ['候補']);
  });

  testWidgets('disabled desktop Ctrl-Enter sends while Enter stays multiline', (
    tester,
  ) async {
    final vm = await _pumpComposer(
      tester,
      enterToSend: false,
      platform: TargetPlatform.macOS,
    );
    final field = find.byType(TextField);

    await tester.tap(field);
    await tester.enterText(field, 'first');
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(vm.sentTexts, isEmpty);
    expect(tester.widget<TextField>(field).controller?.text, 'first\n');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(vm.sentTexts, ['first\n']);
  });
}

Future<_EnterToSendViewModel> _pumpComposer(
  WidgetTester tester, {
  required bool enterToSend,
  TargetPlatform platform = TargetPlatform.android,
  bool aiCompositionSupported = false,
  bool includeSenderOptions = false,
  bool includeReplyKeyboardWebApp = false,
  double? composerWidth,
}) async {
  final vm = _EnterToSendViewModel();
  if (includeReplyKeyboardWebApp) {
    vm
      ..peerIsBot = true
      ..messages = [
        ChatMessage(
          id: 1,
          isOutgoing: false,
          text: '',
          date: 1,
          buttonRows: const [
            [
              MessageButton(
                text: 'Launch Mini App',
                type: 'keyboardButtonTypeWebApp',
                url: 'https://example.com/mini-app',
                isReplyKeyboard: true,
              ),
            ],
          ],
        ),
      ];
  }
  if (includeSenderOptions) {
    vm.availableMessageSenders = const [
      MessageSenderOption(
        sender: {'@type': 'messageSenderUser', 'user_id': 1},
        id: 1,
        title: 'Me',
      ),
      MessageSenderOption(
        sender: {'@type': 'messageSenderChat', 'chat_id': 2},
        id: 2,
        title: 'Test',
      ),
    ];
    vm.selectedMessageSender = vm.availableMessageSenders.first;
  }
  if (aiCompositionSupported) {
    vm.aiCapabilities = const TelegramAiCapabilities(
      tdlibVersion: 'test',
      compositionSupported: true,
      customStylesSupported: false,
      summarySupported: false,
      transcriptionSupported: false,
      styleTitleMax: 0,
      stylePromptMax: 0,
      addedStyleCountMax: 0,
    );
  }
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
      theme: ThemeData(platform: platform, extensions: [AppColors.light]),
      home: Scaffold(
        body: Align(
          alignment: Alignment.bottomCenter,
          child: SizedBox(
            width: composerWidth,
            child: ChatInputBar(
              vm: vm,
              enterToSend: enterToSend,
              quickRepliesEnabled: false,
              onStartCall: (_) {},
              onMessageSent: () {},
            ),
          ),
        ),
      ),
    ),
  );
  return vm;
}
