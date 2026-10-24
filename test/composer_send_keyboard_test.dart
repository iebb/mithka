import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/components/keyboard_dismiss_on_tap.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

class _SendKeyboardViewModel extends ChatViewModel {
  _SendKeyboardViewModel()
    : super(chatId: 1, title: 'Test', markReadOnOpen: false);

  final sentTexts = <String>[];
  Future<bool>? preparation;
  bool sendSucceeds = true;

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
  Future<bool> prepareMessageSend() => preparation ?? Future.value(true);

  @override
  Future<bool> currentUserIsPremium() async => true;

  @override
  Future<bool> sendFormatted(
    String text,
    List<Map<String, dynamic>> entities,
  ) async {
    if (sendSucceeds) sentTexts.add(text);
    return sendSucceeds;
  }
}

Future<_SendKeyboardViewModel> _pumpComposer(
  WidgetTester tester, {
  required bool enterToSend,
  TargetPlatform platform = TargetPlatform.android,
  Locale locale = const Locale('en'),
}) async {
  final vm = _SendKeyboardViewModel();
  addTearDown(vm.dispose);
  await tester.pumpWidget(
    MaterialApp(
      // The app wraps every route in the outside-tap dismissal (main.dart);
      // reproduce that here so composer taps see the same behavior.
      builder: (context, child) =>
          AppKeyboardDismissOnTap(child: child ?? const SizedBox.shrink()),
      locale: locale,
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

FocusNode _composerFocusNode(WidgetTester tester) =>
    tester.widget<EditableText>(find.byType(EditableText).first).focusNode;

void _expectInputConnectionRetained(WidgetTester tester) {
  expect(
    tester.testTextInput.log.where(
      (call) =>
          call.method == 'TextInput.clearClient' ||
          call.method == 'TextInput.setClient' ||
          call.method == 'TextInput.hide',
    ),
    isEmpty,
    reason: 'sending must retain the current input connection',
  );
  expect(_composerFocusNode(tester).hasFocus, isTrue);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('pointer down on send retains the keyboard on ${platform.name}', (
      tester,
    ) async {
      final vm = await _pumpComposer(
        tester,
        enterToSend: false,
        platform: platform,
      );
      final field = find.byType(TextField);

      await tester.tap(field);
      await tester.pump();
      expect(_composerFocusNode(tester).hasFocus, isTrue);

      await tester.enterText(field, 'hello');
      await tester.pump();

      // The dismiss-on-tap handler runs on pointer down, before the button's
      // onTap. Split the gesture so the intermediate state is observable: the
      // send button joins the composer tap region group, so pressing it must
      // not drop focus (which would collapse and then reopen the keyboard).
      final sendButton = find.byKey(const ValueKey('composerSendButton'));
      tester.testTextInput.log.clear();
      final gesture = await tester.startGesture(tester.getCenter(sendButton));
      await tester.pump();
      expect(
        _composerFocusNode(tester).hasFocus,
        isTrue,
        reason:
            'pressing send must not be treated as an outside tap; the keyboard '
            'would collapse and immediately reopen once the send path '
            're-focuses the composer',
      );
      await gesture.up();
      await tester.pump();

      expect(vm.sentTexts, ['hello']);
      _expectInputConnectionRetained(tester);
    });

    testWidgets(
      'software send retains the input connection on ${platform.name}',
      (tester) async {
        final vm = await _pumpComposer(
          tester,
          enterToSend: true,
          platform: platform,
        );
        final field = find.byType(TextField);

        await tester.tap(field);
        await tester.pump();
        await tester.enterText(field, 'hello');
        await tester.pump();

        tester.testTextInput.log.clear();
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pump();

        expect(vm.sentTexts, ['hello']);
        _expectInputConnectionRetained(tester);
      },
    );

    testWidgets('pending send preparation retains focus on ${platform.name}', (
      tester,
    ) async {
      final vm = await _pumpComposer(
        tester,
        enterToSend: true,
        platform: platform,
      );
      final field = find.byType(TextField);
      final ready = Completer<bool>();
      vm.preparation = ready.future;
      await tester.enterText(field, 'pending');
      await tester.pump();
      tester.testTextInput.log.clear();

      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(vm.sentTexts, isEmpty);
      expect(tester.widget<TextField>(field).controller!.text, 'pending');
      _expectInputConnectionRetained(tester);

      ready.complete(true);
      await tester.pump();
      expect(vm.sentTexts, ['pending']);
      expect(tester.widget<TextField>(field).controller!.text, isEmpty);
      _expectInputConnectionRetained(tester);
    });

    testWidgets('failed software send retains the draft on ${platform.name}', (
      tester,
    ) async {
      final vm = await _pumpComposer(
        tester,
        enterToSend: true,
        platform: platform,
      );
      vm.sendSucceeds = false;
      final field = find.byType(TextField);
      await tester.enterText(field, 'retry later');
      await tester.pump();
      tester.testTextInput.log.clear();
      await tester.testTextInput.receiveAction(TextInputAction.send);
      await tester.pump();
      expect(vm.sentTexts, isEmpty);
      expect(tester.widget<TextField>(field).controller!.text, 'retry later');
      _expectInputConnectionRetained(tester);
    });

    testWidgets('outside taps still dismiss the keyboard on ${platform.name}', (
      tester,
    ) async {
      await _pumpComposer(tester, enterToSend: true, platform: platform);
      await tester.enterText(find.byType(TextField), 'draft');
      await tester.pump();
      expect(_composerFocusNode(tester).hasFocus, isTrue);
      await tester.tapAt(const Offset(12, 12));
      await tester.pump();
      expect(_composerFocusNode(tester).hasFocus, isFalse);
    });

    testWidgets(
      'selection toolbar retains composer focus on ${platform.name}',
      (tester) async {
        await _pumpComposer(tester, enterToSend: true, platform: platform);
        final field = find.byType(TextField);
        await tester.enterText(field, 'Selected text');
        await tester.pump();
        final editable = tester.state<EditableTextState>(
          find.byType(EditableText),
        );
        editable.widget.controller.selection = const TextSelection(
          baseOffset: 0,
          extentOffset: 8,
        );
        await tester.pump();
        editable.showToolbar();
        await tester.pumpAndSettle();
        final cut = find.text('Cut');
        expect(cut, findsOneWidget);
        final press = await tester.startGesture(tester.getCenter(cut));
        await tester.pump();
        expect(
          _composerFocusNode(tester).hasFocus,
          isTrue,
          reason: 'system selection actions are inside the field tap region',
        );
        await press.up();
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(field).controller!.text, ' text');
      },
    );

    testWidgets('newline mode does not submit on ${platform.name}', (
      tester,
    ) async {
      final vm = await _pumpComposer(
        tester,
        enterToSend: false,
        platform: platform,
      );
      final field = find.byType(TextField);
      expect(
        tester.widget<TextField>(field).textInputAction,
        TextInputAction.newline,
      );
      await tester.enterText(field, 'first\nsecond');
      await tester.pump();
      tester.testTextInput.log.clear();
      await tester.testTextInput.receiveAction(TextInputAction.newline);
      await tester.pump();
      expect(vm.sentTexts, isEmpty);
      expect(tester.widget<TextField>(field).controller!.text, 'first\nsecond');
      _expectInputConnectionRetained(tester);
    });

    testWidgets(
      'software send commits composing text once on ${platform.name}',
      (tester) async {
        final vm = await _pumpComposer(
          tester,
          enterToSend: true,
          platform: platform,
        );
        final field = find.byType(TextField);
        await tester.enterText(field, 'hello');
        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: 'hello',
            selection: TextSelection.collapsed(offset: 5),
            composing: TextRange(start: 0, end: 5),
          ),
        );
        await tester.pump();
        tester.testTextInput.log.clear();
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.pump();
        expect(vm.sentTexts, ['hello']);
        expect(
          tester.widget<TextField>(field).controller!.value.composing,
          TextRange.empty,
        );
        _expectInputConnectionRetained(tester);
      },
    );
  }

  testWidgets('Android composer selection overflow uses Material icons', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(240, 640);
    addTearDown(tester.view.reset);

    await _pumpComposer(
      tester,
      enterToSend: false,
      locale: const Locale('zh', 'CN'),
    );
    const text = '选择这些文字';
    final field = find.byType(TextField);
    await tester.enterText(field, text);
    await tester.pump();
    final editable = tester.state<EditableTextState>(find.byType(EditableText));
    // Partial selection keeps the "全选" (select all) item in the menu, so the
    // Chinese toolbar (剪切/复制/粘贴/全选/格式) cannot fit the narrow screen
    // and the framework renders its overflow "more" button.
    editable.widget.controller.selection = const TextSelection(
      baseOffset: 0,
      extentOffset: 4,
    );
    await tester.pump();
    editable.showToolbar();
    await tester.pumpAndSettle();

    expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
    final moreButton = find.byKey(StandardComponentType.moreButton.key);
    expect(moreButton, findsOneWidget);
    final moreIcon = tester.widget<Icon>(
      find.descendant(of: moreButton, matching: find.byType(Icon)),
    );
    expect(moreIcon.icon, Icons.more_vert);
    expect(moreIcon.icon?.fontFamily, 'MaterialIcons');

    final pubspecLines = File('pubspec.yaml').readAsLinesSync();
    final flutterStart = pubspecLines.indexOf('flutter:');
    expect(flutterStart, greaterThanOrEqualTo(0));
    final nextSection = pubspecLines.indexWhere(
      (line) => line.isNotEmpty && !line.startsWith(RegExp(r'\s')),
      flutterStart + 1,
    );
    final flutterLines = pubspecLines.sublist(
      flutterStart + 1,
      nextSection < 0 ? pubspecLines.length : nextSection,
    );
    final materialDesignSetting = RegExp(
      r'^\s+uses-material-design\s*:\s*true\s*$',
    );
    expect(
      flutterLines.any(materialDesignSetting.hasMatch),
      isTrue,
      reason: 'Flutter must bundle MaterialIcons for selection toolbar icons',
    );
  });

  testWidgets('desktop retains its default tap-region grouping', (
    tester,
  ) async {
    final vm = await _pumpComposer(
      tester,
      enterToSend: true,
      platform: TargetPlatform.macOS,
    );
    expect(
      tester.widget<TextField>(find.byType(TextField)).groupId,
      EditableText,
    );
    expect(vm.sentTexts, isEmpty);
  });
}
