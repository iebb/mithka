import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';

class _ReplyBannerViewModel extends ChatViewModel {
  _ReplyBannerViewModel()
    : super(chatId: 1, title: 'Test', markReadOnOpen: false);

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

Future<_ReplyBannerViewModel> _pumpComposer(WidgetTester tester) async {
  final vm = _ReplyBannerViewModel();
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
  return vm;
}

ChatMessage _replyTarget() => ChatMessage(
  id: 501,
  isOutgoing: false,
  senderName: 'Alice',
  text: 'Original message body',
  date: 1,
);

const _bannerKey = ValueKey('composerReplyBanner');
const _closeKey = ValueKey('composerReplyClose');

void main() {
  testWidgets('close button clears a focused reply banner', (tester) async {
    final vm = await _pumpComposer(tester);

    vm.setReply(_replyTarget());
    await tester.pump();
    expect(find.byKey(_bannerKey), findsOneWidget);

    // Replying focuses the field (the keyboard opens on a real device), and
    // while focused the composer skips bare revision rebuilds — the exact
    // state the close button must still work in.
    await tester.tap(find.byType(TextField));
    await tester.pump();
    final focused = tester.widget<TextField>(find.byType(TextField));
    expect(focused.focusNode?.hasFocus ?? false, isTrue);

    await tester.tap(find.byKey(_closeKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(vm.replyTo, isNull);
    expect(find.byKey(_bannerKey), findsNothing);
  });

  testWidgets('close button clears a cross-chat reply banner', (tester) async {
    final vm = await _pumpComposer(tester);

    vm.setExternalReply(_replyTarget(), 77);
    await tester.pump();
    expect(find.byKey(_bannerKey), findsOneWidget);

    await tester.tap(find.byKey(_closeKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(vm.replyTo, isNull);
    expect(vm.replyToChatId, isNull);
    expect(find.byKey(_bannerKey), findsNothing);
  });

  test('cross-chat reply serializes as inputMessageReplyToExternalMessage', () {
    final vm = _ReplyBannerViewModel();
    vm.setExternalReply(_replyTarget(), 77);
    expect(vm.replyToInput, {
      '@type': 'inputMessageReplyToExternalMessage',
      'chat_id': 77,
      'message_id': 501,
    });
    expect(vm.replyTo, isNotNull);

    vm.setReply(_replyTarget());
    expect(vm.replyToInput, {
      '@type': 'inputMessageReplyToMessage',
      'message_id': 501,
    });
  });

  testWidgets('tapping the banner body requests reply options', (tester) async {
    var requested = 0;
    final vm = _ReplyBannerViewModel();
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
          body: Align(
            alignment: Alignment.bottomCenter,
            child: ChatInputBar(
              vm: vm,
              quickRepliesEnabled: false,
              onStartCall: (_) {},
              onMessageSent: () {},
              onReplyOptionsRequested: () => requested++,
            ),
          ),
        ),
      ),
    );

    vm.setReply(_replyTarget());
    await tester.pump();

    await tester.tap(find.text('Reply to Alice'));
    await tester.pump();
    expect(requested, 1);
  });
}
