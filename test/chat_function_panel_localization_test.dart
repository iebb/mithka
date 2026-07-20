import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/business_service.dart';

void main() {
  testWidgets('function panel keeps one location and one call entry', (
    tester,
  ) async {
    final previousLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'zh_Hans';
    addTearDown(() => Intl.defaultLocale = previousLocale);

    final vm = ChatViewModel(
      chatId: 1,
      title: 'Test group',
      markReadOnOpen: false,
    )..isGroup = true;
    addTearDown(vm.dispose);

    await tester.pumpWidget(
      _localizedApp(
        ChatInputBar(
          vm: vm,
          onStartCall: (_) {},
          onMessageSent: () {},
          onVoicePanelOpenedForTesting: () {},
        ),
      ),
    );

    await tester.tap(find.byIcon(HeroAppIcons.circlePlus.data));
    await tester.pump();

    expect(find.text('位置'), findsOneWidget);
    expect(find.text('场所'), findsNothing);
    expect(find.text('群通话'), findsOneWidget);
    expect(find.text('群视频'), findsNothing);
    expect(find.text('视频消息'), findsNothing);
    expect(find.text('联系人'), findsOneWidget);
    expect(find.text('定时消息'), findsOneWidget);

    await tester.tap(find.byIcon(HeroAppIcons.microphone.data));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('voicePanelVoiceMessage')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('voicePanelVideoMessage')),
      findsOneWidget,
    );
    expect(find.text('语音消息'), findsOneWidget);
    expect(find.text('视频消息'), findsOneWidget);
  });

  testWidgets('empty private-chat input opens inline quick replies', (
    tester,
  ) async {
    final previousLocale = Intl.defaultLocale;
    Intl.defaultLocale = 'zh_Hans';
    addTearDown(() => Intl.defaultLocale = previousLocale);

    final vm = _QuickReplyTestViewModel()
      ..peerUserId = 7
      ..meId = 1;
    addTearDown(vm.dispose);
    final sends = <(int, int)>[];

    await tester.pumpWidget(
      _localizedApp(
        ChatInputBar(
          vm: vm,
          onStartCall: (_) {},
          onMessageSent: () {},
          quickReplyLoader: () async => const [
            BusinessQuickReplyShortcut(
              id: 9,
              name: 'hello',
              messageCount: 1,
              preview: '你好，很高兴认识你',
            ),
          ],
          quickReplySender: (chatId, shortcutId) async {
            sends.add((chatId, shortcutId));
          },
        ),
      ),
    );
    await tester.pump();

    expect(find.text('快速回复'), findsNothing);
    await tester.tap(find.byType(TextField).first);
    await tester.pump();

    expect(find.byKey(const ValueKey('quickReplyContextMenu')), findsOneWidget);
    expect(find.text('快速回复'), findsOneWidget);
    expect(find.text('/hello'), findsOneWidget);
    expect(find.text('你好，很高兴认识你'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('quickReply-9')));
    await tester.pump();

    expect(sends, [(41, 9)]);
    expect(find.byKey(const ValueKey('quickReplyContextMenu')), findsNothing);
  });
}

Widget _localizedApp(Widget child) => MaterialApp(
  locale: const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hans'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Align(alignment: Alignment.bottomCenter, child: child),
  ),
);

class _QuickReplyTestViewModel extends ChatViewModel {
  _QuickReplyTestViewModel()
    : super(chatId: 41, title: 'Private chat', markReadOnOpen: false);

  @override
  void setDraft(
    String value, {
    String? formattedText,
    List<Map<String, dynamic>> entities = const [],
  }) {
    draft = value;
  }

  @override
  void sendTyping() {}
}
