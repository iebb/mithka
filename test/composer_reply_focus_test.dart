//
//  composer_reply_focus_test.dart
//
//  A swipe on the transcript is a shortcut to typing, so the reply target it
//  produces arrives with the caret already in the composer. Setting a reply
//  target from anywhere else must not move the caret: the action menu answers
//  with the banner alone, and a chat that cannot send keeps the keyboard down.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';

class _ReplyFocusViewModel extends ChatViewModel {
  _ReplyFocusViewModel({bool canSend = true})
    : super(chatId: 1, title: 'Test', markReadOnOpen: false) {
    canSendMessages = canSend;
  }

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
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final replyTarget = ChatMessage(
    id: 7,
    isOutgoing: false,
    text: 'Answer me',
    date: 1,
    senderName: 'Sender',
  );

  bool composerHasCaret(WidgetTester tester) {
    final fields = find.byType(TextField);
    expect(fields, findsOneWidget);
    return tester.widget<TextField>(fields).focusNode!.hasFocus;
  }

  Future<_ReplyFocusViewModel> pumpComposer(
    WidgetTester tester, {
    bool canSend = true,
  }) async {
    final vm = _ReplyFocusViewModel(canSend: canSend);
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
              onStartCall: (_) {},
              onMessageSent: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return vm;
  }

  testWidgets('a reply target alone leaves the caret where it was', (
    tester,
  ) async {
    final vm = await pumpComposer(tester);

    vm.setReply(replyTarget);
    await tester.pump();

    expect(vm.replyTo, same(replyTarget));
    expect(composerHasCaret(tester), isFalse);
  });

  testWidgets('a transcript reply request raises the caret', (tester) async {
    final vm = await pumpComposer(tester);
    expect(vm.composerFocusTick, 0);

    // What a swipe on the transcript does: target first, then the caret.
    vm
      ..setReply(replyTarget)
      ..requestComposerFocus();
    await tester.pump();
    await tester.pump();

    expect(vm.replyTo, same(replyTarget));
    expect(vm.composerFocusTick, 1);
    expect(composerHasCaret(tester), isTrue);
  });

  testWidgets('a chat that cannot send keeps the keyboard down', (
    tester,
  ) async {
    final vm = await pumpComposer(tester, canSend: false);

    vm
      ..setReply(replyTarget)
      ..requestComposerFocus();
    await tester.pump();
    await tester.pump();

    expect(vm.composerFocusTick, 1);
    expect(composerHasCaret(tester), isFalse);
  });

  testWidgets('a deferred reply focus cannot move to a replacement chat', (
    tester,
  ) async {
    final previous = await pumpComposer(tester);
    previous
      ..setReply(replyTarget)
      ..requestComposerFocus();

    // Replace the model before the pending post-frame focus callback runs.
    final replacement = await pumpComposer(tester);
    await tester.pump();
    expect(replacement.replyTo, isNull);
    expect(composerHasCaret(tester), isFalse);
  });
}
