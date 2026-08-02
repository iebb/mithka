import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/l10n/app_localizations.dart';
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

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(vm.sentTexts, ['first']);
  });
}

Future<_EnterToSendViewModel> _pumpComposer(
  WidgetTester tester, {
  required bool enterToSend,
}) async {
  final vm = _EnterToSendViewModel();
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
            enterToSend: enterToSend,
            quickRepliesEnabled: false,
            onStartCall: (_) {},
            onMessageSent: () {},
          ),
        ),
      ),
    ),
  );
  return vm;
}
