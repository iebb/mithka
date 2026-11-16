import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/composer_reply_options_sheet.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  contentType: 'messageText',
);

const _bannerKey = ValueKey('composerReplyBanner');
const _closeKey = ValueKey('composerReplyClose');

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

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

  testWidgets('reply options sheet paints an opaque panel with the menu', (
    tester,
  ) async {
    // The sheet must paint its own opaque background — the original bug put
    // dark menu text straight on the dark scrim.
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
          body: ComposerReplyOptionsSheet(
            message: _replyTarget(),
            canQuote: true,
            canReplyInAnotherChat: true,
            quoteLengthLimit: 100,
          ),
        ),
      ),
    );
    await tester.pump();

    final material = tester.widget<Material>(
      find.byKey(const ValueKey('composerReplyOptionsSheet')),
    );
    expect(material.color, isNot(Colors.transparent));

    expect(find.text('Reply to Message'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composerReplyOptionQuote')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('composerReplyOptionAnotherChat')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('composerReplyOptionApply')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('composerReplyOptionCancel')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('composerReplyOptionsPreview')),
      findsOneWidget,
    );
  });

  testWidgets('opening with a quote highlights the quoted range', (
    tester,
  ) async {
    // Reference parity: the quoted range is visibly marked in the preview
    // (a highlighted span over quote.position..position+len).
    const quote = MessageTextQuote(text: 'message body', position: 9);
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
          body: ComposerReplyOptionsSheet(
            message: _replyTarget(), // 'Original message body'
            canQuote: true,
            canReplyInAnotherChat: false,
            quoteLengthLimit: 100,
            initialQuote: quote,
          ),
        ),
      ),
    );
    await tester.pump();

    Element? paragraphElement;
    void walk(Element e) {
      if (e.renderObject is RenderParagraph) {
        paragraphElement = e;
        return;
      }
      e.visitChildElements(walk);
    }

    walk(
      find
          .byKey(const ValueKey('composerReplyOptionsPreview'))
          .evaluate()
          .single,
    );
    final span = (paragraphElement!.renderObject as RenderParagraph).text;
    final flat = <TextSpan>[];
    void flatten(InlineSpan s) {
      if (s is TextSpan) {
        if (s.text != null) flat.add(s);
        s.children?.forEach(flatten);
      }
    }

    flatten(span);
    final marked = flat.where((s) => s.style?.background != null).toList();
    expect(marked, isNotNull);
    expect(marked.single.text, 'message body');

    // And the panel is in quote mode with the range marked.
    expect(find.text('Update Quote'), findsOneWidget);
  });

  testWidgets('quote row with no selection selects the full text', (
    tester,
  ) async {
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
          body: ComposerReplyOptionsSheet(
            message: _replyTarget(),
            canQuote: true,
            canReplyInAnotherChat: false,
            quoteLengthLimit: 100,
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey('composerReplyOptionQuote')));
    await tester.pump();
    await tester.pump();
    // Full text auto-selected as the quote and the header flipped.
    expect(find.text('Update Quote'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composerReplyOptionClearQuote')),
      findsOneWidget,
    );
  });

  testWidgets('counter row keeps its height when the selection empties', (
    tester,
  ) async {
    // Regression: dragging over the counter row used to collapse the
    // selection for a frame; the row's disappearance shifted the menu and
    // the layout oscillated ("menu flickers up and down"). The row must
    // keep a stable slot once a selection has existed.
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
          body: ComposerReplyOptionsSheet(
            message: _replyTarget(),
            canQuote: true,
            canReplyInAnotherChat: false,
            quoteLengthLimit: 100,
          ),
        ),
      ),
    );
    await tester.pump();

    const counterKey = ValueKey('composerReplyOptionsQuoteLength');
    expect(find.byKey(counterKey), findsNothing);
    final applyBefore = tester.getTopLeft(
      find.byKey(const ValueKey('composerReplyOptionApply')),
    );

    // Start a selection via the quote row (auto full-select).
    await tester.tap(find.byKey(const ValueKey('composerReplyOptionQuote')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(counterKey), findsOneWidget);
    final applyWithCounter = tester.getTopLeft(
      find.byKey(const ValueKey('composerReplyOptionApply')),
    );
    expect(applyWithCounter.dy, greaterThan(applyBefore.dy));

    // A transient empty selection must NOT remove the row.
    final state = tester.state<ComposerReplyOptionsSheetState>(
      find.byType(ComposerReplyOptionsSheet),
    );
    state.debugSimulateSelection(null, 0);
    await tester.pump();
    expect(find.byKey(counterKey), findsOneWidget);
    expect(
      tester.getTopLeft(find.byKey(const ValueKey('composerReplyOptionApply'))),
      applyWithCounter,
    );

    // An over-limit selection keeps the row and shows the raw length.
    state.debugSimulateSelection(null, 120);
    await tester.pump();
    expect(find.byKey(counterKey), findsOneWidget);
    expect(find.text('120 / 100'), findsOneWidget);
  });

  testWidgets('quote toggle clears an existing quote', (tester) async {
    const quote = MessageTextQuote(text: 'Original', position: 0);
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
          body: ComposerReplyOptionsSheet(
            message: _replyTarget(),
            canQuote: true,
            canReplyInAnotherChat: false,
            quoteLengthLimit: 100,
            initialQuote: quote,
          ),
        ),
      ),
    );
    await tester.pump();

    // With a quote attached the header switches to "Update Quote" and the
    // quote row becomes "Clear Quote".
    expect(find.text('Update Quote'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('composerReplyOptionClearQuote')),
    );
    await tester.pump();
    expect(find.text('Update Quote'), findsNothing);
    expect(find.text('Reply to Message'), findsOneWidget);
  });

  testWidgets('banner alternates the tap hint before the first session', (
    tester,
  ) async {
    final vm = await _pumpComposer(tester);
    vm.setReply(_replyTarget());
    await tester.pump();

    expect(find.text('Tap here for reply options'), findsNothing);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Tap here for reply options'), findsOneWidget);
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Original message body'), findsOneWidget);
  });
}
