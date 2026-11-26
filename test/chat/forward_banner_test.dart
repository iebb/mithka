//
//  forward_banner_test.dart
//
//  The composer's pending-forward banner (forward-to-chat, the reference client
//  parity): rendering, close, options sheet opening, and send-commit.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/composer/chat_input_bar.dart';
import 'package:mithka/chat/forward_handoff.dart';
import 'package:mithka/chat/forward_options_sheet.dart';
import 'package:mithka/chat/messages/forward_markdown.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ForwardBannerViewModel extends ChatViewModel {
  _ForwardBannerViewModel()
    : super(chatId: 1, title: 'Test', markReadOnOpen: false);

  int forwardSends = 0;
  List<Map<String, dynamic>> forwardRequests = [];

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
  Future<void> sendPendingForward() async {
    forwardSends++;
    final forward = pendingForward!;
    forwardRequests.add({
      'from_chat_id': forward.fromChatId,
      'remove_sender': forward.removeSender,
      'remove_caption': forward.removeCaption,
      'message_ids': [for (final message in forward.messages) message.id],
    });
    // The TDLib request itself is covered by the forward ownership and
    // pending-options suites; this harness pins the composer wiring only.
    pendingForward = null;
    notifyListeners();
  }
}

ChatMessage _forwardedMessage({int id = 5, String text = 'Original body'}) =>
    ChatMessage(
      id: id,
      isOutgoing: false,
      senderName: 'Alice',
      text: text,
      date: 1,
      contentType: 'messageText',
    );

ForwardMessagesHandoff _handoff({
  List<ChatMessage>? messages,
  bool hasCaption = false,
}) => ForwardMessagesHandoff(
  fromChatId: 99,
  messages: messages ?? [_forwardedMessage()],
  accountSlot: 0,
  clientId: 0,
  hasCaption: hasCaption,
  markdownOffer: const ForwardMarkdownOffer.none(),
);

Future<_ForwardBannerViewModel> _pumpComposer(
  WidgetTester tester, {
  VoidCallback? onForwardOptionsRequested,
}) async {
  final vm = _ForwardBannerViewModel();
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
            onForwardOptionsRequested: onForwardOptionsRequested,
          ),
        ),
      ),
    ),
  );
  return vm;
}

const _bannerKey = ValueKey('composerForwardBanner');
const _closeKey = ValueKey('composerForwardClose');
const _sendKey = ValueKey('composerSendButton');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('banner renders for an adopted forward and close drops it', (
    tester,
  ) async {
    final vm = await _pumpComposer(tester);

    vm.adoptForwardHandoff(_handoff());
    await tester.pump();
    expect(find.byKey(_bannerKey), findsOneWidget);

    await tester.tap(find.byKey(_closeKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(vm.pendingForward, isNull);
    expect(find.byKey(_bannerKey), findsNothing);
  });

  testWidgets('send button commits the pending forward and consumes it', (
    tester,
  ) async {
    final vm = await _pumpComposer(tester);

    vm.adoptForwardHandoff(_handoff());
    await tester.pump();
    // The send button must be offered while a forward is pending even with
    // an empty draft.
    expect(find.byKey(_sendKey), findsOneWidget);

    await tester.tap(find.byKey(_sendKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(vm.forwardSends, 1);
    expect(
      vm.forwardRequests.single['remove_sender'],
      isFalse,
      reason: 'a plain adopted forward keeps the sender attributed',
    );
    expect(vm.pendingForward, isNull);
  });

  testWidgets('a forward addressed to this same chat still adopts', (
    tester,
  ) async {
    final vm = await _pumpComposer(tester);
    // fromChatId == the receiving chat's chatId (1): the composer must hold
    // it as a pending forward (repeat-style send), not silently drop it.
    vm.adoptForwardHandoff(
      ForwardMessagesHandoff(
        fromChatId: 1,
        messages: [_forwardedMessage()],
        accountSlot: 0,
        clientId: 0,
        hasCaption: false,
        markdownOffer: const ForwardMarkdownOffer.none(),
      ),
    );
    await tester.pump();
    expect(find.byKey(_bannerKey), findsOneWidget);
    expect(vm.pendingForward, isNotNull);
  });

  testWidgets('banner body requests the options sheet', (tester) async {
    var requested = 0;
    final vm = await _pumpComposer(
      tester,
      onForwardOptionsRequested: () => requested++,
    );

    vm.adoptForwardHandoff(_handoff());
    await tester.pump();

    await tester.tap(find.byKey(_bannerKey));
    await tester.pump();
    expect(requested, 1);
  });

  testWidgets('options sheet hides the caption row without captioned media', (
    tester,
  ) async {
    final forward = pendingForwardFromHandoff(_handoff());
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
        home: ForwardOptionsSheet(forward: forward),
      ),
    );
    expect(
      find.byKey(const ValueKey('composerForwardOptionCaption')),
      findsNothing,
      reason: 'a forward without captioned media offers no 移除说明',
    );
    expect(
      find.byKey(const ValueKey('composerForwardOptionSender')),
      findsOneWidget,
    );
  });

  testWidgets('options sheet shows the caption row for captioned media', (
    tester,
  ) async {
    final forward = pendingForwardFromHandoff(
      _handoff(
        hasCaption: true,
        messages: [
          ChatMessage(
            id: 5,
            isOutgoing: false,
            text: 'caption text',
            date: 1,
            image: TdFileRef(id: 1),
          ),
        ],
      ),
    );
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
        home: ForwardOptionsSheet(forward: forward),
      ),
    );
    expect(
      find.byKey(const ValueKey('composerForwardOptionCaption')),
      findsOneWidget,
    );
  });

  /// The options sheet is interactive: tapping a toggle row re-renders it
  /// immediately (action label flips, checkbox follows) — the reference client
  /// ToggleButton behavior. The regression this pins: a stateless sheet left
  /// the rows visually frozen ("toggles can't be tapped").
  Future<void> pumpSheet(
    WidgetTester tester,
    PendingForward forward, {
    Widget? hostChild,
  }) async {
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
        home: ForwardOptionsHost(
          onForwardOptionsChanged: () {},
          child: Scaffold(body: ForwardOptionsSheet(forward: forward)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  String rowLabel(WidgetTester tester, Key key) => tester
      .widget<Text>(
        find.descendant(of: find.byKey(key), matching: find.byType(Text)).first,
      )
      .data!;

  testWidgets('tapping hide-sender flips the action label immediately', (
    tester,
  ) async {
    final forward = pendingForwardFromHandoff(
      _handoff(
        hasCaption: true,
        messages: [
          ChatMessage(
            id: 5,
            isOutgoing: false,
            text: 'caption',
            date: 1,
            image: TdFileRef(id: 1),
          ),
        ],
      ),
    );
    await pumpSheet(tester, forward);
    expect(
      rowLabel(tester, const ValueKey('composerForwardOptionSender')),
      'Remove sender',
    );
    await tester.tap(find.byKey(const ValueKey('composerForwardOptionSender')));
    await tester.pumpAndSettle();
    expect(
      rowLabel(tester, const ValueKey('composerForwardOptionSender')),
      'Show sender',
    );
    expect(forward.removeSender, isTrue);
  });

  testWidgets('hiding the caption visibly forces the sender row too', (
    tester,
  ) async {
    final forward = pendingForwardFromHandoff(
      _handoff(
        hasCaption: true,
        messages: [
          ChatMessage(
            id: 5,
            isOutgoing: false,
            text: 'caption',
            date: 1,
            image: TdFileRef(id: 1),
          ),
        ],
      ),
    );
    await pumpSheet(tester, forward);
    expect(
      rowLabel(tester, const ValueKey('composerForwardOptionCaption')),
      'Remove caption',
    );
    await tester.tap(
      find.byKey(const ValueKey('composerForwardOptionCaption')),
    );
    await tester.pumpAndSettle();
    // The caption→copy rule hid the sender as well; both rows show the state.
    expect(forward.removeCaption, isTrue);
    expect(forward.removeSender, isTrue);
    expect(
      rowLabel(tester, const ValueKey('composerForwardOptionSender')),
      'Show sender',
    );
    expect(
      rowLabel(tester, const ValueKey('composerForwardOptionCaption')),
      'Show caption',
    );
  });

  testWidgets('a protected-copy forward hides the sender and caption rows', (
    tester,
  ) async {
    final forward = pendingForwardFromHandoff(
      ForwardMessagesHandoff(
        fromChatId: 99,
        messages: [
          ChatMessage(
            id: 5,
            isOutgoing: false,
            text: 'caption',
            date: 1,
            image: TdFileRef(id: 1),
          ),
        ],
        accountSlot: 0,
        clientId: 0,
        hasCaption: true,
        markdownOffer: const ForwardMarkdownOffer.none(),
        protectedCopy: true,
      ),
    );
    await pumpSheet(tester, forward);
    // The copy path re-sends as fresh messages: no forward header to hide a
    // sender from, and the caption always travels with the copy. Both toggle
    // rows are meaningless there and must not render.
    expect(
      find.byKey(const ValueKey('composerForwardOptionSender')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('composerForwardOptionCaption')),
      findsNothing,
    );
  });
}
