import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderEditable;
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/composer/chat_input_bar.dart';
import 'package:mithka/chat/composer/outgoing_attachment.dart';
import 'package:mithka/chat/composer/rich_message_source.dart';
import 'package:mithka/chat/composer/rich_text_composer_view.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

class _ConversionViewModel extends ChatViewModel {
  _ConversionViewModel()
    : super(chatId: 1, title: 'Test', markReadOnOpen: false);

  final formatted = <(String, List<Map<String, dynamic>>)>[];
  final richHtml = <String>[];

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
    formatted.add((text, entities));
    return true;
  }

  @override
  Future<void> sendRichMessageHtml(
    String html, {
    List<RichMessageSendFile> files = const [],
    List<Map<String, dynamic>> blocks = const [],
  }) async {
    richHtml.add(html);
  }
}

RichTextComposerResult _result(
  String text, {
  bool hasRichBlocks = false,
  List<OutgoingAttachment> attachments = const [],
}) => RichTextComposerResult(
  text: text,
  entities: const [],
  attachments: attachments,
  segments: [RichMessageSendSegment.html('<p>$text</p>')],
  hasRichBlocks: hasRichBlocks,
);

Finder _icon(AppIconData icon) => find.byWidgetPredicate(
  (widget) => widget is AppIcon && widget.icon == icon,
);

const _pill = ValueKey('composerTextInputBox');
const _sender = ValueKey('composerSenderPicker');
const _pen = ValueKey('composerRichTextConvertButton');
const _send = ValueKey('composerSendButton');

RenderEditable _editor(WidgetTester tester) =>
    tester.state<EditableTextState>(find.byType(EditableText)).renderEditable;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final direction in TextDirection.values) {
    testWidgets(
      'standard phone composer centers one visual line ($direction)',
      (tester) async {
        await _pumpComposer(tester, phoneDirection: direction);
        final field = find.byType(TextField);
        final editable = find.byType(EditableText);
        final sender = find.byKey(_sender);
        final pen = find.byKey(_pen);
        final send = find.byKey(_send);

        void expectCentered({required bool hasText}) {
          final center = tester.getCenter(find.byKey(_pill)).dy;
          expect(tester.getCenter(editable).dy, closeTo(center, 1));
          expect(tester.getCenter(sender).dy, closeTo(center, 1));
          final editor = _editor(tester);
          final caret = editor.getLocalRectForCaret(editor.selection!.extent);
          expect(editor.localToGlobal(caret.center).dy, closeTo(center, 1));
          expect(editor.textAlign, TextAlign.start);
          expect(editor.textDirection, direction);
          if (hasText) {
            expect(tester.getCenter(pen).dy, closeTo(center, 1));
            expect(tester.getCenter(send).dy, closeTo(center, 1));
            expect(tester.getSize(send).height, 44);
          }
        }

        await tester.showKeyboard(field);
        await tester.pump();
        expectCentered(hasText: false);
        await tester.enterText(field, 'Hello');
        await tester.pump();
        expectCentered(hasText: true);

        tester.testTextInput.updateEditingValue(
          const TextEditingValue(
            text: '猫猫',
            selection: TextSelection.collapsed(offset: 2),
            composing: TextRange(start: 0, end: 2),
          ),
        );
        await tester.pump();
        expectCentered(hasText: true);
        expect(
          tester.widget<TextField>(field).controller!.value.composing.isValid,
          isTrue,
        );
        await tester.enterText(field, '猫猫');
        await tester.pump();
        expectCentered(hasText: true);
      },
      variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    );
  }

  testWidgets(
    'standard phone composer keeps multiline controls bottom-aligned',
    (tester) async {
      await _pumpComposer(tester, phoneDirection: TextDirection.ltr);
      final field = find.byType(TextField);
      final pill = find.byKey(_pill);
      final sender = find.byKey(_sender);
      final pen = find.byKey(_pen);
      final send = find.byKey(_send);
      final singleLineHeight = tester.getSize(pill).height;

      for (final draft in ['First\nSecond\nThird', 'W' * 30]) {
        await tester.enterText(field, draft);
        await tester.pump();
        final editor = _editor(tester);
        final lines = editor.startVerticalCaretMovement(
          const TextPosition(offset: 0),
        );
        expect(lines.moveNext(), isTrue);
        expect(lines.moveNext(), isTrue);
        expect(lines.moveNext(), isFalse);
        expect(tester.getSize(pill).height, greaterThan(singleLineHeight));
        expect(tester.getRect(sender).bottom, tester.getRect(pen).bottom);
        expect(tester.getRect(pen).bottom, tester.getRect(pill).bottom - 9);
        expect(tester.getRect(send).bottom, tester.getRect(pill).bottom);
        final caret = editor.getLocalRectForCaret(editor.selection!.extent);
        expect(caret.center.dy, inInclusiveRange(0, editor.size.height));
      }
      await tester.enterText(field, 'Hi');
      await tester.pump();
      expect(tester.getSize(pill).height, singleLineHeight);
      expect(tester.getCenter(send).dy, closeTo(tester.getCenter(pill).dy, 1));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );

  test('only inline documents within the plain length send inline', () {
    expect(_result('hello').sendsAsFormattedText, isTrue);
    expect(_result('').sendsAsFormattedText, isFalse);
    expect(
      _result('heading', hasRichBlocks: true).sendsAsFormattedText,
      isFalse,
    );
    expect(
      _result(
        'caption',
        attachments: const [
          OutgoingAttachment(
            path: '/tmp/a.jpg',
            kind: OutgoingAttachmentKind.photo,
          ),
        ],
      ).sendsAsFormattedText,
      isFalse,
    );
    // A long plain message only fits as a rich message; it must stay rich.
    expect(
      _result(
        'a' * (telegramTextMessageMaxCharacters + 1),
      ).sendsAsFormattedText,
      isFalse,
    );
  });

  testWidgets('strip has no format button and closes with a circled X', (
    tester,
  ) async {
    await _pumpComposer(tester);

    expect(find.text('A'), findsNothing);
    await tester.tap(_icon(HeroAppIcons.circlePlus));
    await tester.pumpAndSettle();

    expect(_icon(HeroAppIcons.circleXmark), findsOneWidget);
    expect(_icon(HeroAppIcons.xmark), findsNothing);
  });

  testWidgets('converted inline draft is sent as an ordinary message', (
    tester,
  ) async {
    final vm = await _pumpComposer(tester);
    const convert = ValueKey('composerRichTextConvertButton');

    expect(find.byKey(convert), findsNothing);
    await tester.enterText(find.byType(TextField), 'hello');
    await tester.pump();
    await tester.tap(find.byKey(convert));
    await tester.pumpAndSettle();

    expect(find.byType(RichTextComposerView), findsOneWidget);
    expect(find.text('hello'), findsWidgets);
    await tester.tap(find.byKey(const ValueKey('richTextComposerSubmit')));
    await tester.pumpAndSettle();

    expect(vm.formatted.map((sent) => sent.$1), ['hello']);
    expect(vm.richHtml, isEmpty);
  });
}

Future<_ConversionViewModel> _pumpComposer(
  WidgetTester tester, {
  TextDirection? phoneDirection,
}) async {
  final vm = _ConversionViewModel();
  if (phoneDirection != null) {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const sender = MessageSenderOption(id: 1, title: 'You', sender: {});
    vm.selectedMessageSender = sender;
    vm.availableMessageSenders = [
      sender,
      const MessageSenderOption(id: 2, title: 'Channel', sender: {}),
    ];
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
      theme: ThemeData(
        platform: phoneDirection == null
            ? TargetPlatform.android
            : TargetPlatform.iOS,
        extensions: [AppColors.light],
      ),
      builder: phoneDirection == null
          ? null
          : (context, child) =>
                Directionality(textDirection: phoneDirection, child: child!),
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
