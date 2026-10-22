import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/emoji_text_controller.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/components/keyboard_dismiss_on_tap.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

class _FormatPanelViewModel extends ChatViewModel {
  _FormatPanelViewModel()
    : super(chatId: 1, title: 'Format panel', markReadOnOpen: false);

  final sent = <(String, List<Map<String, dynamic>>)>[];

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
  Future<bool> prepareMessageSend() => Future.value(true);

  @override
  Future<bool> currentUserIsPremium() async => true;

  @override
  Future<bool> sendFormatted(
    String text,
    List<Map<String, dynamic>> entities,
  ) async {
    sent.add((text, entities));
    return true;
  }
}

Future<EmojiTextEditingController> _pumpComposer(
  WidgetTester tester, {
  Size size = const Size(420, 900),
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final vm = _FormatPanelViewModel();
  addTearDown(vm.dispose);
  await tester.pumpWidget(
    MaterialApp(
      // The app wraps every route in the outside-tap dismissal (main.dart);
      // reproduce it so the strip keeps the composer's tap-region grouping.
      builder: (context, child) => Material(
        // The link dialog hosts a bare TextField, whose debug-only Material
        // assertion needs an ancestor above the Navigator. Release builds do
        // not require one; the app has none, so this harness supplies it.
        type: MaterialType.transparency,
        child: AppKeyboardDismissOnTap(child: child ?? const SizedBox.shrink()),
      ),
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
  final field = find.byType(TextField).first;
  return tester.widget<TextField>(field).controller!
      as EmojiTextEditingController;
}

/// The strip entry itself, independent of the semantics tree: the format
/// panel's own header also reads "Format".
Finder _stripEntry(String semanticLabel) => find.byWidgetPredicate(
  (widget) =>
      widget is AppInteractiveSurface && widget.semanticLabel == semanticLabel,
);

Finder _cell(String name) => find.byKey(ValueKey('composerFormatAction-$name'));

SemanticsProperties _cellSemantics(WidgetTester tester, String name) {
  final semantics = tester.widget<Semantics>(
    find.ancestor(of: _cell(name), matching: find.byType(Semantics)).first,
  );
  return semantics.properties;
}

const _actionNames = [
  'quote',
  'spoiler',
  'bold',
  'italic',
  'monospace',
  'link',
  'strikethrough',
  'underline',
  'codeBlock',
];

Map<String, dynamic> _entity(
  int offset,
  int length,
  Map<String, dynamic> type,
) {
  return {
    '@type': 'textEntity',
    'offset': offset,
    'length': length,
    'type': type,
  };
}

/// The captured range as the panel records it, defaulting the content, revision
/// and account bindings to values that match whatever the case supplies.
bool _stale({
  required int capturedStart,
  required int capturedEnd,
  required int capturedTextLength,
  required int currentTextLength,
  String capturedText = 'hello worl',
  String? currentText,
  int capturedTextRevision = 7,
  int? currentTextRevision,
  int capturedOwnerClientId = 100,
  int? currentOwnerClientId,
}) {
  return composerFormatRangeIsStale(
    capturedStart: capturedStart,
    capturedEnd: capturedEnd,
    capturedTextLength: capturedTextLength,
    currentTextLength: currentTextLength,
    capturedText: capturedText,
    currentText: currentText ?? capturedText,
    capturedTextRevision: capturedTextRevision,
    currentTextRevision: currentTextRevision ?? capturedTextRevision,
    capturedOwnerClientId: capturedOwnerClientId,
    currentOwnerClientId: currentOwnerClientId ?? capturedOwnerClientId,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('composerFormatRangeFor', () {
    test('rejects a collapsed caret', () {
      expect(
        composerFormatRangeFor(const TextSelection.collapsed(offset: 3), 10),
        isNull,
      );
    });

    test('rejects an invalid selection', () {
      expect(
        composerFormatRangeFor(
          const TextSelection(baseOffset: -1, extentOffset: 3),
          10,
        ),
        isNull,
      );
    });

    test('rejects a range past the end of the text', () {
      expect(
        composerFormatRangeFor(
          const TextSelection(baseOffset: 2, extentOffset: 12),
          10,
        ),
        isNull,
      );
    });

    test('normalizes a reversed drag', () {
      expect(
        composerFormatRangeFor(
          const TextSelection(baseOffset: 7, extentOffset: 2),
          10,
        ),
        (2, 7),
      );
    });

    test('keeps a valid range inclusive of the full text', () {
      expect(
        composerFormatRangeFor(
          const TextSelection(baseOffset: 2, extentOffset: 7),
          10,
        ),
        (2, 7),
      );
      expect(
        composerFormatRangeFor(
          const TextSelection(baseOffset: 0, extentOffset: 10),
          10,
        ),
        (0, 10),
      );
    });
  });

  group('composerFormatRangeIsStale', () {
    test('keeps a range whose text is unchanged', () {
      expect(
        _stale(
          capturedStart: 2,
          capturedEnd: 7,
          capturedTextLength: 10,
          currentTextLength: 10,
        ),
        isFalse,
      );
    });

    test('drops a same-length replacement of the draft', () {
      expect(
        _stale(
          capturedStart: 2,
          capturedEnd: 7,
          capturedTextLength: 10,
          currentTextLength: 10,
          currentText: 'jello worl',
        ),
        isTrue,
      );
    });

    test('drops a range captured for another account', () {
      expect(
        _stale(
          capturedStart: 2,
          capturedEnd: 7,
          capturedTextLength: 10,
          currentTextLength: 10,
          currentOwnerClientId: 101,
        ),
        isTrue,
      );
    });

    test('drops a range whose text revision moved without new text', () {
      expect(
        _stale(
          capturedStart: 2,
          capturedEnd: 7,
          capturedTextLength: 10,
          currentTextLength: 10,
          capturedTextRevision: 4,
          currentTextRevision: 5,
        ),
        isTrue,
      );
    });

    test('drops the range once the text length changes', () {
      expect(
        _stale(
          capturedStart: 2,
          capturedEnd: 7,
          capturedTextLength: 10,
          currentTextLength: 11,
        ),
        isTrue,
      );
      expect(
        _stale(
          capturedStart: 2,
          capturedEnd: 7,
          capturedTextLength: 10,
          currentTextLength: 6,
        ),
        isTrue,
      );
    });

    test('treats an empty or out-of-bounds capture as stale', () {
      expect(
        _stale(
          capturedStart: 4,
          capturedEnd: 4,
          capturedTextLength: 10,
          currentTextLength: 10,
        ),
        isTrue,
      );
      expect(
        _stale(
          capturedStart: 12,
          capturedEnd: 14,
          capturedTextLength: 14,
          currentTextLength: 10,
        ),
        isTrue,
      );
      expect(
        _stale(
          capturedStart: -1,
          capturedEnd: 3,
          capturedTextLength: 10,
          currentTextLength: 10,
        ),
        isTrue,
      );
    });
  });

  group('format panel', () {
    testWidgets('a same-length draft replacement disables the cells', (
      tester,
    ) async {
      final controller = await _pumpComposer(tester);
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'hello world');
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();

      await tester.tap(_stripEntry(AppStrings.t(AppStringKeys.composerFormat)));
      await tester.pump();
      expect(_cellSemantics(tester, 'bold').enabled, isTrue);

      // The view model replaces the draft while the field is unfocused, the
      // exact path _syncFromVm takes: same length, different words.
      controller.text = 'jello world';
      await tester.pump();

      expect(_cellSemantics(tester, 'bold').enabled, isFalse);
      expect(_cellSemantics(tester, 'link').enabled, isFalse);
      final cell = tester.widget<GestureDetector>(_cell('bold'));
      expect(cell.onTap, isNull);

      await tester.tap(_cell('bold'), warnIfMissed: false);
      await tester.pump();
      final (_, entities) = controller.toFormatted();
      expect(entities, isEmpty);
    });

    testWidgets('a same-length replacement while the link dialog is open '
        'applies nothing', (tester) async {
      final controller = await _pumpComposer(tester);
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'hello world');
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 6,
        extentOffset: 11,
      );
      await tester.pump();

      await tester.tap(_stripEntry(AppStrings.t(AppStringKeys.composerFormat)));
      await tester.pump();
      await tester.tap(_cell('link'));
      await tester.pumpAndSettle();
      expect(find.text('Enter URL'), findsOneWidget);

      // The pending capture addresses "world" at 6..11; the draft is replaced
      // with another word at the same offsets before the URL is submitted.
      controller.text = 'hello there';
      await tester.pump();

      await tester.enterText(find.byType(TextField).at(1), 'example.com/foo');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      final (text, entities) = controller.toFormatted();
      expect(text, 'hello there');
      expect(entities, isEmpty);
    });

    testWidgets('strip entry sits between the emoji and more entries', (
      tester,
    ) async {
      await _pumpComposer(tester);
      final emoji = tester.getCenter(
        _stripEntry(AppStrings.t(AppStringKeys.composerMediaPicker)),
      );
      final format = tester.getCenter(
        _stripEntry(AppStrings.t(AppStringKeys.composerFormat)),
      );
      final more = tester.getCenter(
        _stripEntry(AppStrings.t(AppStringKeys.composerOpenMenu)),
      );

      expect(format.dx, greaterThan(emoji.dx));
      expect(format.dx, lessThan(more.dx));
      expect(format.dy, closeTo(emoji.dy, 0.5));
      expect(format.dy, closeTo(more.dy, 0.5));
    });

    testWidgets('opens a docked grid with all nine actions and closes', (
      tester,
    ) async {
      await _pumpComposer(tester);
      final panel = find.byKey(const ValueKey('composerFormatPanel'));
      expect(panel, findsNothing);
      await tester.tap(_stripEntry(AppStrings.t(AppStringKeys.composerFormat)));
      await tester.pump();

      expect(panel, findsOneWidget);
      final panelWidget = tester.widget<Container>(panel);
      expect(panelWidget.color, AppColors.light.inputBarBackground);
      final panelRect = tester.getRect(panel);
      expect(panelRect.height, 268);
      expect(
        panelRect.top,
        greaterThanOrEqualTo(
          tester
              .getRect(_stripEntry(AppStrings.t(AppStringKeys.composerFormat)))
              .bottom,
        ),
        reason: 'the panel docks directly under the icon strip',
      );

      for (final name in _actionNames) {
        expect(_cell(name), findsOneWidget, reason: name);
      }

      // Five columns at phone width, so the fifth action shares the first row
      // and the sixth wraps: this is a grid, not one row or a scroller.
      final firstRowTop = tester.getCenter(_cell('quote')).dy;
      for (final name in ['spoiler', 'bold', 'italic', 'monospace']) {
        expect(tester.getCenter(_cell(name)).dy, closeTo(firstRowTop, 0.5));
      }
      expect(tester.getCenter(_cell('link')).dy, greaterThan(firstRowTop));
      expect(
        tester.getCenter(_cell('monospace')).dx,
        greaterThan(tester.getCenter(_cell('italic')).dx),
      );

      await tester.tap(_stripEntry(AppStrings.t(AppStringKeys.composerFormat)));
      await tester.pump();
      expect(panel, findsNothing);
    });

    testWidgets('narrow phones wrap the grid at four columns', (tester) async {
      await _pumpComposer(tester, size: const Size(360, 900));
      await tester.tap(_stripEntry(AppStrings.t(AppStringKeys.composerFormat)));
      await tester.pump();

      final firstRowTop = tester.getCenter(_cell('quote')).dy;
      for (final name in ['spoiler', 'bold', 'italic']) {
        expect(tester.getCenter(_cell(name)).dy, closeTo(firstRowTop, 0.5));
      }
      expect(tester.getCenter(_cell('monospace')).dy, greaterThan(firstRowTop));
    });

    testWidgets('a cell applies its entity over the captured selection', (
      tester,
    ) async {
      final controller = await _pumpComposer(tester);
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'hello world');
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();

      await tester.tap(_stripEntry(AppStrings.t(AppStringKeys.composerFormat)));
      await tester.pump();
      expect(_cellSemantics(tester, 'bold').enabled, isTrue);

      await tester.tap(_cell('bold'));
      await tester.pump();

      var (text, entities) = controller.toFormatted();
      expect(text, 'hello world');
      expect(entities, [
        _entity(0, 5, const {'@type': 'textEntityTypeBold'}),
      ]);
      expect(_cellSemantics(tester, 'bold').selected, isTrue);
      // The panel stays open so formats can be stacked.
      expect(find.byKey(const ValueKey('composerFormatPanel')), findsOneWidget);

      await tester.tap(_cell('bold'));
      await tester.pump();

      (text, entities) = controller.toFormatted();
      expect(text, 'hello world');
      expect(entities, isEmpty);
      expect(_cellSemantics(tester, 'bold').selected, isFalse);
    });

    testWidgets('reopening on a formatted selection shows the cell selected', (
      tester,
    ) async {
      final controller = await _pumpComposer(tester);
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'hello world');
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();

      final entry = _stripEntry(AppStrings.t(AppStringKeys.composerFormat));
      await tester.tap(entry);
      await tester.pump();
      await tester.tap(_cell('bold'));
      await tester.pump();

      await tester.tap(entry);
      await tester.pump();
      await tester.tap(entry);
      await tester.pump();

      expect(_cellSemantics(tester, 'bold').selected, isTrue);
      final (_, entities) = controller.toFormatted();
      expect(entities, [
        _entity(0, 5, const {'@type': 'textEntityTypeBold'}),
      ]);
    });

    testWidgets('the link cell prompts for a URL and applies the text URL', (
      tester,
    ) async {
      final controller = await _pumpComposer(tester);
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'hello world');
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 6,
        extentOffset: 11,
      );
      await tester.pump();

      await tester.tap(_stripEntry(AppStrings.t(AppStringKeys.composerFormat)));
      await tester.pump();
      await tester.tap(_cell('link'));
      await tester.pumpAndSettle();

      expect(find.text('Enter URL'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
      await tester.enterText(find.byType(TextField).at(1), 'example.com/foo');
      await tester.tap(find.text('Apply'));
      await tester.pumpAndSettle();

      final (text, entities) = controller.toFormatted();
      expect(text, 'hello world');
      expect(entities, [
        _entity(6, 5, const {
          '@type': 'textEntityTypeTextUrl',
          'url': 'https://example.com/foo',
        }),
      ]);
    });

    testWidgets('editing the text after opening leaves the cells disabled', (
      tester,
    ) async {
      final controller = await _pumpComposer(tester);
      final field = find.byType(TextField).first;
      await tester.enterText(field, 'hello world');
      await tester.pump();
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      await tester.pump();

      await tester.tap(_stripEntry(AppStrings.t(AppStringKeys.composerFormat)));
      await tester.pump();
      expect(_cellSemantics(tester, 'bold').enabled, isTrue);

      controller.text = 'hello world!';
      await tester.pump();

      expect(_cellSemantics(tester, 'bold').enabled, isFalse);
      expect(_cellSemantics(tester, 'link').enabled, isFalse);
      final cell = tester.widget<GestureDetector>(_cell('bold'));
      expect(cell.onTap, isNull);

      await tester.tap(_cell('bold'), warnIfMissed: false);
      await tester.pump();
      final (_, entities) = controller.toFormatted();
      expect(entities, isEmpty);
    });

    testWidgets('opening without a selection leaves the cells disabled', (
      tester,
    ) async {
      await _pumpComposer(tester);
      await tester.enterText(find.byType(TextField).first, 'hello');
      await tester.pump();

      await tester.tap(_stripEntry(AppStrings.t(AppStringKeys.composerFormat)));
      await tester.pump();

      expect(find.byKey(const ValueKey('composerFormatPanel')), findsOneWidget);
      for (final name in _actionNames) {
        expect(_cellSemantics(tester, name).enabled, isFalse, reason: name);
      }
    });
  });
}
