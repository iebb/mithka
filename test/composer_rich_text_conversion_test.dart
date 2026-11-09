import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/outgoing_attachment.dart';
import 'package:mithka/chat/rich_message_source.dart';
import 'package:mithka/chat/rich_text_composer_view.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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

Future<_ConversionViewModel> _pumpComposer(WidgetTester tester) async {
  final vm = _ConversionViewModel();
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
  return vm;
}
