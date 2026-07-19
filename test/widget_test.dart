// Unit tests for the ported pure logic (date formatting, JSON helpers, parsing).

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_message_merge.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/emoji_catalog.dart';
import 'package:mithka/chat/emoji_text_controller.dart';
import 'package:mithka/chat/gif_item.dart';
import 'package:mithka/chat/gif_store.dart';
import 'package:mithka/chat/group_management_log_view.dart';
import 'package:mithka/chat/media_album_layout.dart';
import 'package:mithka/chat/message_bubble.dart';
import 'package:mithka/chat/music_player_controller.dart';
import 'package:mithka/chat/rich_text_composer_view.dart';
import 'package:mithka/chat/secret_chat_service.dart';
import 'package:mithka/chat/sponsored_messages_cache.dart';
import 'package:mithka/chat/sticker_item.dart';
import 'package:mithka/chat/sticker_store.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/keyboard_dismiss_on_tap.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_locale_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/country_message_filter.dart';
import 'package:mithka/settings/keyword_blocker.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/json_helpers.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/date_text.dart';
import 'package:mithka/theme/emoji_font_catalog.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<MusicPlayerController> _pumpMusicPlayerBar(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final theme = ThemeController(prefs);
  final player = MusicPlayerController.shared;
  final track = ChatMessage(
    id: 101,
    isOutgoing: false,
    text: '',
    date: 1,
    chatId: 202,
    senderName: 'Chat source',
    music: MessageMusic(
      title: 'Chat track',
      performer: 'Artist',
      duration: 180,
      file: TdFileRef(id: 303),
    ),
  );
  player
    ..current = track
    ..queue = [track]
    ..hidden = false
    ..collapsed = false;
  addTearDown(() {
    player
      ..current = null
      ..queue = const []
      ..hidden = true
      ..collapsed = false;
    theme.dispose();
  });

  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: Column(children: [Spacer(), GlobalMusicPlayerBar()]),
        ),
      ),
    ),
  );
  return player;
}

class _FocusTestChatViewModel extends ChatViewModel {
  _FocusTestChatViewModel()
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

class _ControlledMediaChatViewModel extends ChatViewModel {
  _ControlledMediaChatViewModel()
    : super(chatId: 1, title: 'Test', markReadOnOpen: false);

  final stickerSend = Completer<bool>();
  final gifSend = Completer<bool>();

  @override
  Future<bool> sendSticker(StickerItem sticker) => stickerSend.future;

  @override
  Future<bool> sendGif(GifItem gif) => gifSend.future;
}

void main() {
  group('AppKeyboardDismissOnTap', () {
    testWidgets('lets system text actions run before dismissing focus', (
      tester,
    ) async {
      final controller = TextEditingController(text: 'Selected text');
      final focusNode = FocusNode();
      addTearDown(controller.dispose);
      addTearDown(focusNode.dispose);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) =>
              AppKeyboardDismissOnTap(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Stack(
              children: [
                const Positioned.fill(
                  child: ColoredBox(
                    key: ValueKey('keyboard-dismiss-background'),
                    color: Colors.transparent,
                  ),
                ),
                Center(
                  child: TextField(
                    controller: controller,
                    focusNode: focusNode,
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      final field = find.byType(TextField);
      final fieldTopLeft = tester.getTopLeft(field);
      await tester.longPressAt(fieldTopLeft + const Offset(45, 24));
      await tester.pumpAndSettle();
      expect(find.text('Cut'), findsOneWidget);
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.text('Cut'));
      await tester.pumpAndSettle();
      expect(controller.text, isNot('Selected text'));

      await tester.tap(field);
      await tester.pump();
      expect(focusNode.hasFocus, isTrue);
      await tester.tapAt(const Offset(12, 12));
      await tester.pump();
      expect(focusNode.hasFocus, isFalse);
    });
  });

  group('GlobalMusicPlayerBar', () {
    testWidgets('preserves the swipe animation before minimizing', (
      tester,
    ) async {
      final player = await _pumpMusicPlayerBar(tester);

      final bar = find.byType(GlobalMusicPlayerBar);
      final slide = find.descendant(
        of: bar,
        matching: find.byType(AnimatedSlide),
      );
      expect(find.text('Chat track'), findsOneWidget);
      expect(player.collapsed, isFalse);

      final gesture = await tester.startGesture(tester.getCenter(bar));
      // The first movement wins the horizontal drag arena; the second one is
      // the live drag delta rendered by the player.
      await gesture.moveBy(const Offset(20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(280, 0));
      await tester.pump();
      expect(tester.widget<AnimatedSlide>(slide).offset.dx, greaterThan(0));
      expect(player.collapsed, isFalse);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 95));
      expect(tester.widget<AnimatedSlide>(slide).offset.dx, greaterThan(0));
      expect(player.collapsed, isFalse);

      await tester.pump(const Duration(milliseconds: 100));
      expect(player.collapsed, isTrue);
    });

    testWidgets('left swipe stops playback after sliding the player away', (
      tester,
    ) async {
      final player = await _pumpMusicPlayerBar(tester);
      final bar = find.byType(GlobalMusicPlayerBar);
      final slide = find.descendant(
        of: bar,
        matching: find.byType(AnimatedSlide),
      );

      final gesture = await tester.startGesture(tester.getCenter(bar));
      await gesture.moveBy(const Offset(-20, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-280, 0));
      await tester.pump();
      expect(tester.widget<AnimatedSlide>(slide).offset.dx, lessThan(0));
      expect(player.current, isNotNull);

      await gesture.up();
      await tester.pump(const Duration(milliseconds: 95));
      expect(tester.widget<AnimatedSlide>(slide).offset.dx, lessThan(0));
      expect(player.current, isNotNull);

      await tester.pump(const Duration(milliseconds: 100));
      expect(player.current, isNull);
      expect(player.queue, isEmpty);
      expect(player.hidden, isTrue);
    });
  });

  group('DateText', () {
    test('bubbleLabel pads to HH:mm', () {
      final unix = DateTime(2024, 6, 4, 9, 5).millisecondsSinceEpoch ~/ 1000;
      expect(DateText.bubbleLabel(unix), '09:05');
    });

    test('messageDetailLabel uses MM-dd HH:mm:ss', () {
      final unix = DateTime(2024, 6, 4, 9, 5, 7).millisecondsSinceEpoch ~/ 1000;
      expect(DateText.messageDetailLabel(unix), '06-04 09:05:07');
    });

    test('empty for non-positive unix', () {
      expect(DateText.listLabel(0), '');
      expect(DateText.separatorLabel(0), '');
    });

    test('labels use locale-independent numeric format', () {
      Intl.defaultLocale = 'zh_Hans';
      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      String expectedDate(DateTime value) => value.year == now.year
          ? '${two(value.month)}/${two(value.day)}'
          : '${value.year}/${two(value.month)}/${two(value.day)}';

      final today = DateTime(now.year, now.month, now.day, 9, 5);
      final yesterday = DateTime(
        now.year,
        now.month,
        now.day,
      ).subtract(const Duration(days: 1)).add(const Duration(minutes: 38));
      final previousYear = DateTime(now.year - 1, 6, 4, 7, 8);

      expect(DateText.listLabel(today.millisecondsSinceEpoch ~/ 1000), '09:05');
      expect(
        DateText.listLabel(yesterday.millisecondsSinceEpoch ~/ 1000),
        expectedDate(yesterday),
      );
      expect(
        DateText.separatorLabel(yesterday.millisecondsSinceEpoch ~/ 1000),
        '${expectedDate(yesterday)} 00:38',
      );
      expect(
        DateText.quoteLabel(yesterday.millisecondsSinceEpoch ~/ 1000),
        '${expectedDate(yesterday)} 00:38',
      );
      expect(
        DateText.quoteLabel(previousYear.millisecondsSinceEpoch ~/ 1000),
        '${expectedDate(previousYear)} 07:08',
      );
    });
  });

  group('EmojiCatalog', () {
    test('category labels resolve through localization', () {
      for (final category in EmojiCatalog.categories) {
        final localized = AppStrings.t(category.name);
        expect(localized, isNot(category.name));
        expect(localized, isNot(contains('emojiCategory')));
      }
    });
  });

  group('EmojiTextEditingController', () {
    test('inserts pasted text at the current selection', () {
      final controller = EmojiTextEditingController();
      addTearDown(controller.dispose);

      controller.text = 'hello world';
      controller.selection = const TextSelection(
        baseOffset: 6,
        extentOffset: 11,
      );
      controller.insertText('Mithka');

      expect(controller.text, 'hello Mithka');
      expect(controller.selection, const TextSelection.collapsed(offset: 12));
    });

    test('inserts preformatted table without corrupting existing entities', () {
      final controller = EmojiTextEditingController();
      addTearDown(controller.dispose);

      controller.text = 'hello world';
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 5,
      );
      controller.toggleFormat('textEntityTypeBold');
      controller.selection = const TextSelection.collapsed(offset: 5);
      controller.insertFormattedText(
        '\n| A | B |\n|---|---|\n|   |   |\n',
        type: 'textEntityTypePre',
      );

      final (text, entities) = controller.toFormatted();
      expect(text, startsWith('hello\n| A | B |'));
      expect(entities.map((e) => e['type']['@type']), [
        'textEntityTypeBold',
        'textEntityTypePre',
      ]);
      expect(entities[0]['offset'], 0);
      expect(entities[0]['length'], 5);
      expect(entities[1]['offset'], 5);
    });
  });

  group('RichTextComposerView', () {
    testWidgets('renders toolbar with semantics enabled', (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: RichTextComposerView(initialText: '', allowMedia: false),
        ),
      );
      await tester.pump();

      expect(find.byType(RichTextComposerView), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });

    testWidgets('keeps the editable text state while selection changes', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: RichTextComposerView(
            initialText: 'select this text',
            allowMedia: false,
          ),
        ),
      );
      await tester.pump();

      final field = find.byType(TextField).first;
      final editable = find.descendant(
        of: field,
        matching: find.byType(EditableText),
      );
      final editableBefore = tester.state<EditableTextState>(editable);
      final controller = tester.widget<TextField>(field).controller!;

      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 6,
      );
      await tester.pump();

      expect(tester.state<EditableTextState>(editable), same(editableBefore));
      expect(
        controller.selection,
        const TextSelection(baseOffset: 0, extentOffset: 6),
      );
    });

    testWidgets('offers inline formatting and every-block insertion', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: RichTextComposerView(
            initialText: 'format me',
            allowMedia: false,
          ),
        ),
      );
      await tester.pump();

      final fieldFinder = find.byType(TextField).first;
      final field = tester.widget<TextField>(fieldFinder);
      final controller = field.controller!;
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 6,
      );
      await tester.pump();
      final editableState = tester.state<EditableTextState>(
        find.descendant(of: fieldFinder, matching: find.byType(EditableText)),
      );
      final toolbar =
          field.contextMenuBuilder!(tester.element(fieldFinder), editableState)
              as AdaptiveTextSelectionToolbar;
      final labels = toolbar.buttonItems!.map((item) => item.label);

      expect(labels, contains('Format'));
      expect(labels, contains('Insert'));
    });

    testWidgets('table title is editable and table actions stay clickable', (
      tester,
    ) async {
      RichTextComposerResult? result;
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => GestureDetector(
              key: const ValueKey('open-rich-composer'),
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                result = await Navigator.of(context)
                    .push<RichTextComposerResult>(
                      PageRouteBuilder<RichTextComposerResult>(
                        pageBuilder: (_, _, _) => const RichTextComposerView(
                          initialText: '',
                          allowMedia: false,
                        ),
                      ),
                    );
              },
              child: const SizedBox.expand(),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('open-rich-composer')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Table'));
      await tester.pump();

      final title = find.byKey(const ValueKey('rich-table-title'));
      expect(title, findsOneWidget);
      expect(tester.widget<TextField>(title).controller?.text, 'Table 1');
      final addRowControl = find.byKey(const ValueKey('rich-table-add-row'));
      expect(
        tester.getCenter(addRowControl).dy,
        moreOrLessEquals(tester.getCenter(title).dy),
      );
      await tester.enterText(
        title,
        'A table name that is deliberately long enough to require its own row '
        'while keeping every table control visible and easy to use',
      );
      await tester.pump();
      expect(
        tester.getTopLeft(addRowControl).dy,
        greaterThan(tester.getBottomLeft(title).dy),
      );
      await tester.enterText(title, 'Quarterly <Plan>');
      await tester.pump();
      expect(
        tester.getCenter(addRowControl).dy,
        moreOrLessEquals(tester.getCenter(title).dy),
      );

      final originalTextFieldCount = find.byType(TextField).evaluate().length;
      final tableControlKeys = [
        'rich-table-add-row',
        'rich-table-add-column',
        'rich-table-toggle-header',
        'rich-table-align-horizontal',
        'rich-table-align-vertical',
        'rich-table-toggle-borderless',
      ];
      for (final key in tableControlKeys) {
        expect(find.byKey(ValueKey(key)), findsOneWidget);
      }
      final controlCenters = tableControlKeys
          .map((key) => tester.getCenter(find.byKey(ValueKey(key))))
          .toList();
      for (final center in controlCenters.skip(1)) {
        expect(center.dy, moreOrLessEquals(controlCenters.first.dy));
      }
      final headerControl = find.byKey(
        const ValueKey('rich-table-toggle-header'),
      );
      expect(
        find.descendant(
          of: headerControl,
          matching: find.byIcon(HeroAppIcons.hashtag.data),
        ),
        findsOneWidget,
      );
      final borderlessControl = find.byKey(
        const ValueKey('rich-table-toggle-borderless'),
      );
      expect(
        tester.getCenter(borderlessControl).dx,
        greaterThan(
          tester
              .getCenter(
                find.byKey(const ValueKey('rich-table-align-vertical')),
              )
              .dx,
        ),
      );
      await tester.tap(borderlessControl);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rich-table-add-row')));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(originalTextFieldCount + 3));
      await tester.tap(find.byKey(const ValueKey('rich-table-add-column')));
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(originalTextFieldCount + 7));
      final textFieldCount = find.byType(TextField).evaluate().length;

      final firstCell = find.byKey(const ValueKey('rich-table-cell-0-0'));
      final firstCellController =
          tester.widget<TextField>(firstCell).controller!
              as EmojiTextEditingController;
      expect(
        tester.widget<TextField>(firstCell).keyboardType,
        TextInputType.multiline,
      );
      expect(
        tester.widget<TextField>(firstCell).textInputAction,
        TextInputAction.newline,
      );
      expect(tester.widget<TextField>(firstCell).maxLines, isNull);
      await tester.enterText(firstCell, 'Column 1\nSecond line');
      await tester.pump();
      expect(firstCellController.text, 'Column 1\nSecond line');
      expect(
        tester
            .widget<EditableText>(
              find.descendant(
                of: firstCell,
                matching: find.byType(EditableText),
              ),
            )
            .focusNode
            .hasFocus,
        isTrue,
      );
      await tester.enterText(firstCell, 'Column 1');
      await tester.pump();

      await tester.tap(firstCell);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rich-table-toggle-header')));
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('rich-table-align-horizontal')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rich-table-align-vertical')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rich-table-align-vertical')));
      await tester.pump();
      expect(tester.widget<TextField>(firstCell).textAlign, TextAlign.center);
      expect(
        tester.widget<TextField>(firstCell).textAlignVertical,
        TextAlignVertical.bottom,
      );
      final firstCellEditable = tester.widget<EditableText>(
        find.descendant(of: firstCell, matching: find.byType(EditableText)),
      );
      expect(firstCellEditable.focusNode.hasFocus, isTrue);

      final secondCell = find.byKey(const ValueKey('rich-table-cell-0-1'));
      await tester.tap(secondCell);
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('rich-table-align-horizontal')),
      );
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('rich-table-align-horizontal')),
      );
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('rich-table-align-vertical')));
      await tester.pump();
      expect(tester.widget<TextField>(secondCell).textAlign, TextAlign.right);
      expect(
        tester.widget<TextField>(secondCell).textAlignVertical,
        TextAlignVertical.center,
      );
      expect(tester.widget<TextField>(firstCell).textAlign, TextAlign.center);
      expect(
        tester.widget<TextField>(firstCell).textAlignVertical,
        TextAlignVertical.bottom,
      );

      await tester.tap(firstCell);
      await tester.pump();
      await tester.longPress(firstCell);
      await tester.pumpAndSettle();

      expect(find.byType(AdaptiveTextSelectionToolbar), findsOneWidget);
      expect(find.text('Change Table'), findsOneWidget);
      expect(find.text('Format'), findsOneWidget);
      firstCellController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: firstCellController.text.length,
      );
      await tester.pump();
      await tester.tap(find.text('Format'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('rich-format-bold')),
          matching: find.byIcon(HeroAppIcons.check.data),
        ),
        findsNothing,
      );
      await tester.tap(find.text('Bold'));
      await tester.pumpAndSettle();
      final formattedCell = firstCellController.toFormatted();
      expect(
        formattedCell.$2.any(
          (entity) =>
              (entity['type'] as Map<String, dynamic>)['@type'] ==
              'textEntityTypeBold',
        ),
        isTrue,
      );

      firstCellController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: firstCellController.text.length,
      );
      await tester.pump();
      final formattedField = tester.widget<TextField>(firstCell);
      final formattedEditableState = tester.state<EditableTextState>(
        find.descendant(of: firstCell, matching: find.byType(EditableText)),
      );
      final formattedToolbar =
          formattedField.contextMenuBuilder!(
                tester.element(firstCell),
                formattedEditableState,
              )
              as AdaptiveTextSelectionToolbar;
      formattedToolbar.buttonItems!
          .singleWhere((item) => item.label == 'Format')
          .onPressed!();
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('rich-format-bold')),
          matching: find.byIcon(HeroAppIcons.check.data),
        ),
        findsOneWidget,
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      firstCellController.selection = const TextSelection.collapsed(offset: 0);
      await tester.pump();
      await tester.longPress(firstCell);
      await tester.pumpAndSettle();
      final selectAll = find.textContaining(
        RegExp('select all', caseSensitive: false),
      );
      expect(selectAll, findsOneWidget);
      await tester.tap(selectAll);
      await tester.pump();
      expect(firstCellController.selection.start, 0);
      expect(
        firstCellController.selection.end,
        firstCellController.text.length,
      );

      await tester.longPress(firstCell);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Change Table'));
      await tester.pump();
      expect(find.text('Borderless'), findsNothing);
      expect(find.text('Striped table'), findsNothing);
      expect(find.text('Header cell'), findsNothing);
      for (final removedAction in [
        'Align left',
        'Align center',
        'Align right',
        'Align top',
        'Align middle',
        'Align bottom',
      ]) {
        expect(find.text(removedAction), findsNothing);
      }
      final addRow = find.text('Add row above');
      expect(addRow, findsOneWidget);
      await tester.ensureVisible(addRow);
      await tester.tap(addRow);
      await tester.pump();
      expect(find.byType(TextField), findsNWidgets(textFieldCount + 4));

      await tester.tap(find.text('Post'));
      await tester.pumpAndSettle();

      expect(result, isNotNull);
      expect(result!.text, startsWith('Quarterly <Plan>\n\n|'));
      final html = result!.segments
          .where((segment) => segment.isHtml)
          .map((segment) => segment.html)
          .join();
      expect(html, contains('<table><caption>'));
      expect(html, isNot(contains('<table bordered')));
      expect(html, isNot(contains('striped')));
      expect(html, contains('<caption>Quarterly &lt;Plan&gt;</caption>'));
      expect(
        html,
        contains('<td align="center" valign="bottom"><b>Column 1</b></td>'),
      );
      expect(html, contains('<th align="right" valign="middle">Column 2</th>'));
    });

    testWidgets('block handle opens move and delete actions', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: RichTextComposerView(initialText: 'block', allowMedia: false),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(ReorderableDragStartListener).first);
      await tester.pumpAndSettle();

      expect(find.text('Move up'), findsOneWidget);
      expect(find.text('Move down'), findsOneWidget);
      expect(find.text('Remove block'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('inserting a block replaces an empty paragraph', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          localizationsDelegates: [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: RichTextComposerView(initialText: '', allowMedia: false),
        ),
      );
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.byTooltip('Block quote'));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      expect(
        tester.widget<TextField>(find.byType(TextField)).decoration?.hintText,
        'Block quote',
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ChatInputBar', () {
    test('builds awaitable sticker send requests', () {
      final vm = ChatViewModel(chatId: 42, title: 'Test', markReadOnOpen: false)
        ..paidMessageStarCount = 3;
      addTearDown(vm.dispose);

      final request = vm.stickerMessageRequest(
        const StickerItem(
          id: 100,
          remoteId: 'remote-sticker',
          width: 512,
          height: 384,
          emoji: '🙂',
        ),
      );

      expect(request['@type'], 'sendMessage');
      expect(request['chat_id'], 42);
      expect(request['options'], {
        '@type': 'messageSendOptions',
        'paid_message_star_count': 3,
      });
      expect(request['input_message_content'], {
        '@type': 'inputMessageSticker',
        'sticker': {
          '@type': 'inputSticker',
          'sticker': {'@type': 'inputFileRemote', 'id': 'remote-sticker'},
          'width': 512,
          'height': 384,
        },
        'emoji': '🙂',
      });
    });

    testWidgets('uses top tabs and dedicated search for stickers and emoji', (
      tester,
    ) async {
      final vm = ChatViewModel(
        chatId: 1,
        title: 'Test chat',
        markReadOnOpen: false,
      );
      addTearDown(vm.dispose);
      var panelGeometryChanges = 0;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(
                vm: vm,
                onStartCall: (_) {},
                onMessageSent: () {},
                onPanelGeometryChanged: () => panelGeometryChanges++,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(HeroAppIcons.grip.data));
      await tester.pump();

      final stickerTabs = find.byKey(const ValueKey('stickerPanelTabs'));
      final search = find.byKey(const ValueKey('composerMediaSearch'));
      expect(stickerTabs, findsOneWidget);
      expect(search, findsNothing);
      expect(panelGeometryChanges, 1);
      expect(find.byIcon(HeroAppIcons.palette.data), findsNothing);

      await tester.tap(find.byKey(const ValueKey('stickerSearchTab')));
      await tester.pump();

      expect(search, findsOneWidget);
      expect(
        tester.getTopLeft(stickerTabs).dy,
        lessThan(tester.getTopLeft(search).dy),
      );

      await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
      await tester.pump();

      final emojiTabs = find.byKey(const ValueKey('emojiPanelTabs'));
      expect(emojiTabs, findsOneWidget);
      expect(search, findsNothing);
      expect(panelGeometryChanges, 2);

      await tester.tap(find.byKey(const ValueKey('emojiSearchTab')));
      await tester.pump();

      expect(search, findsOneWidget);
      expect(
        tester.getTopLeft(emojiTabs).dy,
        lessThan(tester.getTopLeft(search).dy),
      );

      await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
      await tester.pump();
      expect(panelGeometryChanges, 3);
    });

    testWidgets('media taps request bottom scroll before send completion', (
      tester,
    ) async {
      final vm = _ControlledMediaChatViewModel();
      addTearDown(vm.dispose);
      final store = StickerStore.shared;
      store.replacePacksForTest([
        StickerPack(
          id: StickerStore.recentPackId,
          title: 'Recent',
          loaded: true,
          stickers: const [
            StickerItem(id: 100, width: 128, height: 128, emoji: '🙂'),
          ],
        ),
      ]);
      addTearDown(store.reset);
      final gifStore = GifStore.shared;
      final originalGifs = gifStore.items;
      gifStore.replaceItemsForTest([
        GifItem(
          id: 200,
          duration: 2,
          width: 320,
          height: 180,
          mimeType: 'video/mp4',
          file: TdFileRef(id: 200),
        ),
      ]);
      addTearDown(() => gifStore.replaceItemsForTest(originalGifs));
      var mediaSendTaps = 0;
      var messageSentCallbacks = 0;
      var everySentCallbackSawClosedPanel = true;

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(
                vm: vm,
                onStartCall: (_) {},
                gifPreviewBuilder: (_) => const SizedBox.expand(),
                onMediaSendTapped: () => mediaSendTaps++,
                onMessageSent: () {
                  messageSentCallbacks++;
                  everySentCallbackSawClosedPanel =
                      everySentCallbackSawClosedPanel &&
                      find
                          .byKey(const ValueKey('stickerPanelTabs'))
                          .evaluate()
                          .isEmpty;
                },
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(HeroAppIcons.grip.data));
      await tester.pump();
      expect(find.byKey(const ValueKey('sticker-100')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('sticker-100')));
      await tester.pump();

      expect(mediaSendTaps, 1);
      expect(messageSentCallbacks, 0);
      expect(find.byKey(const ValueKey('stickerPanelTabs')), findsOneWidget);

      vm.stickerSend.complete(true);
      await tester.pump();
      await tester.pump();
      expect(messageSentCallbacks, 1);
      expect(everySentCallbackSawClosedPanel, isTrue);

      await tester.tap(find.byIcon(HeroAppIcons.grip.data));
      await tester.pump();
      await tester.tap(find.byIcon(HeroAppIcons.gif.data));
      await tester.pump();
      expect(find.byKey(const ValueKey('gif-200')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('gif-200')));
      await tester.pump();

      expect(mediaSendTaps, 2);
      expect(messageSentCallbacks, 1);
      expect(find.byKey(const ValueKey('stickerPanelTabs')), findsOneWidget);

      vm.gifSend.complete(true);
      await tester.pump();
      await tester.pump();
      expect(messageSentCallbacks, 2);
      expect(everySentCallbackSawClosedPanel, isTrue);
    });

    testWidgets('more panel paints the bottom safe area with its background', (
      tester,
    ) async {
      final vm = ChatViewModel(
        chatId: 1,
        title: 'Test chat',
        markReadOnOpen: false,
      );
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: MediaQuery(
            data: const MediaQueryData(padding: EdgeInsets.only(bottom: 34)),
            child: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(
                  vm: vm,
                  onStartCall: (_) {},
                  onMessageSent: () {},
                ),
              ),
            ),
          ),
        ),
      );

      final safeAreaBackground = find.byKey(
        const ValueKey('chat-input-safe-area-background'),
      );
      final colors = tester.element(safeAreaBackground).colors;
      expect(
        tester.widget<ColoredBox>(safeAreaBackground).color,
        colors.inputBarBackground,
      );

      await tester.tap(find.byIcon(HeroAppIcons.circlePlus.data));
      await tester.pump();

      expect(
        tester.widget<ColoredBox>(safeAreaBackground).color,
        colors.panelBackground,
      );
    });

    testWidgets('pastes images from menus, shortcuts, and inserted content', (
      tester,
    ) async {
      const clipboardChannel = MethodChannel('mithka/clipboard');
      const pathProviderChannel = MethodChannel(
        'plugins.flutter.io/path_provider',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      final clipboardMethods = <String>[];
      messenger.setMockMethodCallHandler(clipboardChannel, (call) async {
        clipboardMethods.add(call.method);
        if (call.method != 'readImage' && call.method != 'readImageUri') {
          return null;
        }
        return <String, dynamic>{
          'mimeType': 'image/png',
          'data': base64Decode(
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
          ),
        };
      });
      messenger.setMockMethodCallHandler(pathProviderChannel, (call) async {
        if (call.method == 'getTemporaryDirectory') {
          return Directory.systemTemp.path;
        }
        return null;
      });
      addTearDown(() {
        messenger.setMockMethodCallHandler(clipboardChannel, null);
        messenger.setMockMethodCallHandler(pathProviderChannel, null);
      });
      final vm = ChatViewModel(chatId: 1, title: 'Test', markReadOnOpen: false);
      var vmDisposed = false;
      addTearDown(() {
        if (!vmDisposed) vm.dispose();
      });

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(
                vm: vm,
                onStartCall: (_) {},
                onMessageSent: () {},
              ),
            ),
          ),
        ),
      );
      final textFieldFinder = find.byType(TextField).first;
      final textField = tester.widget<TextField>(textFieldFinder);
      final editableTextState = tester.state<EditableTextState>(
        find.descendant(
          of: textFieldFinder,
          matching: find.byType(EditableText),
        ),
      );
      final toolbar = textField.contextMenuBuilder!(
        tester.element(textFieldFinder),
        editableTextState,
      );
      final buttonItems = (toolbar as AdaptiveTextSelectionToolbar).buttonItems;

      final pasteItems = buttonItems!.where(
        (item) => item.type == ContextMenuButtonType.paste,
      );
      expect(pasteItems, hasLength(1));

      await tester.runAsync(() async {
        Actions.invoke(
          tester.element(
            find.descendant(
              of: textFieldFinder,
              matching: find.byType(EditableText),
            ),
          ),
          const PasteTextIntent(SelectionChangedCause.keyboard),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Edit in rich text'), findsOneWidget);
      expect(find.text('Send'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(
        find.byKey(const ValueKey('clipboardImagePreview')),
        findsOneWidget,
      );

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        textField.contentInsertionConfiguration!.onContentInserted(
          const KeyboardInsertedContent(
            mimeType: 'image/png',
            uri: 'content://mithka/pasted-image',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('clipboardImagePreview')),
        findsOneWidget,
      );
      expect(
        clipboardMethods.where((method) => method == 'readImage'),
        hasLength(1),
      );
      expect(clipboardMethods, contains('readImageUri'));

      await tester.pumpWidget(const SizedBox.shrink());
      vm.dispose();
      vmDisposed = true;
    });

    testWidgets('format menu keeps input focused until tapping outside', (
      tester,
    ) async {
      final vm = _FocusTestChatViewModel();
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) =>
              AppKeyboardDismissOnTap(child: child ?? const SizedBox.shrink()),
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(
                vm: vm,
                onStartCall: (_) {},
                onMessageSent: () {},
              ),
            ),
          ),
        ),
      );

      final textFieldFinder = find.byType(TextField).first;
      final textField = tester.widget<TextField>(textFieldFinder);
      final controller = textField.controller!;
      final focusNode = textField.focusNode!;
      await tester.tap(textFieldFinder);
      await tester.enterText(textFieldFinder, 'format me');
      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 6,
      );
      await tester.pump();

      void openFormatMenu() {
        final editableTextState = tester.state<EditableTextState>(
          find.descendant(
            of: textFieldFinder,
            matching: find.byType(EditableText),
          ),
        );
        final toolbar = textField.contextMenuBuilder!(
          tester.element(textFieldFinder),
          editableTextState,
        );
        final items = (toolbar as AdaptiveTextSelectionToolbar).buttonItems!;
        items.singleWhere((item) => item.label == 'Format').onPressed!();
      }

      expect(focusNode.hasFocus, isTrue);
      openFormatMenu();
      await tester.pumpAndSettle();
      expect(find.text('Bold'), findsOneWidget);
      expect(focusNode.hasFocus, isTrue);

      await tester.tap(find.text('Bold'));
      await tester.pumpAndSettle();
      expect(focusNode.hasFocus, isTrue);

      controller.selection = const TextSelection(
        baseOffset: 0,
        extentOffset: 6,
      );
      openFormatMenu();
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(4, 4));
      await tester.pumpAndSettle();
      expect(find.text('Bold'), findsNothing);
      expect(focusNode.hasFocus, isFalse);
    });

    testWidgets(
      'uses a bot menu Mini App action and toggles the reply keyboard',
      (tester) async {
        final vm =
            ChatViewModel(chatId: 1, title: 'Test bot', markReadOnOpen: false)
              ..peerIsBot = true
              ..botMenu = const BotMenuInfo(
                type: 'botMenuButton',
                text: '小程序购买',
                url: 'menu://https://example.com/webapp',
              )
              ..botCommands = const [
                BotCommandOption(
                  command: 'start',
                  description: 'Start the bot',
                ),
              ]
              ..messages = [
                ChatMessage(
                  id: 1,
                  isOutgoing: false,
                  text: '',
                  date: 1,
                  buttonRows: [
                    [
                      const MessageButton(
                        text: '购买套餐',
                        type: 'keyboardButtonTypeText',
                        isReplyKeyboard: true,
                      ),
                    ],
                  ],
                ),
              ];
        addTearDown(vm.dispose);

        await tester.pumpWidget(
          MaterialApp(
            localizationsDelegates: const [
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: ChatInputBar(
                  vm: vm,
                  onStartCall: (_) {},
                  onMessageSent: () {},
                ),
              ),
            ),
          ),
        );

        expect(find.text('小程序购买'), findsOneWidget);
        expect(find.bySemanticsLabel('Show bot keyboard'), findsOneWidget);
        expect(find.text('购买套餐'), findsNothing);

        await tester.tap(find.bySemanticsLabel('Show bot keyboard'));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('Hide bot keyboard'), findsOneWidget);
        expect(find.text('购买套餐'), findsOneWidget);

        await tester.longPress(find.text('小程序购买'));
        await tester.pumpAndSettle();
        expect(find.text('/start'), findsOneWidget);
        expect(find.byIcon(HeroAppIcons.code.data), findsOneWidget);
      },
    );

    testWidgets('only shows the bot keyboard toggle for an empty draft', (
      tester,
    ) async {
      final vm =
          ChatViewModel(chatId: 1, title: 'Test bot', markReadOnOpen: false)
            ..draft = 'already typing'
            ..messages = [
              ChatMessage(
                id: 1,
                isOutgoing: false,
                text: '',
                date: 1,
                buttonRows: const [
                  [
                    MessageButton(
                      text: '购买套餐',
                      type: 'keyboardButtonTypeText',
                      isReplyKeyboard: true,
                    ),
                  ],
                ],
              ),
            ];
      addTearDown(vm.dispose);

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: ChatInputBar(
                vm: vm,
                onStartCall: (_) {},
                onMessageSent: () {},
              ),
            ),
          ),
        ),
      );

      expect(find.bySemanticsLabel('Show bot keyboard'), findsNothing);
      expect(find.bySemanticsLabel('Hide bot keyboard'), findsNothing);
    });
  });

  group('MessageBubble delivery status', () {
    testWidgets('copying a code block shows copied feedback', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      final message = ChatMessage(
        id: 5,
        isOutgoing: false,
        text: 'final x = 1;',
        date: 1,
        textEntities: const [
          MessageTextEntity(
            offset: 0,
            length: 12,
            type: 'textEntityTypePreCode',
            language: 'dart',
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Test',
                isGroup: false,
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('message-code-block')));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Copied'), findsOneWidget);
    });

    testWidgets('renders a rich map block with its caption', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      final message = ChatMessage(
        id: 4,
        isOutgoing: false,
        text: '',
        date: 1,
        contentType: 'messageRichMessage',
        richBlocks: [
          RichMessageBlock.map(
            mapLocation: MessageLocation(
              latitude: 35.681236,
              longitude: 139.767125,
            ),
            mapZoom: 17,
            mapWidth: 640,
            mapHeight: 360,
            caption: 'Tokyo',
          ),
        ],
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Test',
                isGroup: false,
              ),
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('rich-message-map')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('rich-message-map-caption')),
        findsOneWidget,
      );
    });

    testWidgets('does not render the GIF preview label as a caption', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      final gifPreview = TDParse.messageText({
        '@type': 'messageAnimation',
        'caption': {'@type': 'formattedText', 'text': ''},
      });
      final message = ChatMessage(
        id: 8,
        isOutgoing: true,
        text: gifPreview,
        date: 1,
        contentType: 'messageAnimation',
        video: TdFileRef(id: 81),
        videoDuration: 25,
        imageWidth: 320,
        imageHeight: 240,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            locale: const Locale('en'),
            localizationsDelegates: const [AppLocalizations.delegate],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Test',
                isGroup: false,
              ),
            ),
          ),
        ),
      );

      expect(gifPreview, '[GIF]');
      expect(find.text(gifPreview), findsNothing);
      expect(find.text('0:25'), findsOneWidget);
    });

    testWidgets('long press reveals retained restricted message content', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      const notice =
          "This message can't be displayed because it violated Telegram's Terms of Service.";
      Finder richTextContaining(String text) => find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == text,
      );
      final message = ChatMessage(
        id: 6,
        isOutgoing: false,
        text: notice,
        date: 1,
        restrictionReason: notice,
        restrictedContentText: 'Retained original text',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Test',
                isGroup: false,
              ),
            ),
          ),
        ),
      );

      expect(richTextContaining(notice), findsOneWidget);
      expect(richTextContaining('Retained original text'), findsNothing);

      await tester.longPress(richTextContaining(notice));
      await tester.pump();

      expect(richTextContaining(notice), findsNothing);
      expect(richTextContaining('Retained original text'), findsOneWidget);
    });

    testWidgets('long press on porn restriction offers 18+ unblock', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      const notice =
          "This message couldn't be displayed on your device because it contains pornographic materials.";
      Finder richTextContaining(String text) => find.byWidgetPredicate(
        (widget) => widget is RichText && widget.text.toPlainText() == text,
      );
      final message = ChatMessage(
        id: 7,
        isOutgoing: false,
        text: notice,
        date: 1,
        restrictionReason: notice,
        restrictedContentText: 'Retained original text',
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Test',
                isGroup: false,
              ),
            ),
          ),
        ),
      );

      expect(richTextContaining(notice), findsOneWidget);
      expect(richTextContaining('Retained original text'), findsNothing);

      await tester.longPress(richTextContaining(notice));
      await tester.pumpAndSettle();

      expect(find.text('Show 18+ content?'), findsOneWidget);
      expect(find.text('Unblock All'), findsOneWidget);
      expect(richTextContaining('Retained original text'), findsNothing);
    });

    testWidgets('always shows one sent dot and two read dots', (tester) async {
      SharedPreferences.setMockInitialValues({
        'showMessageMetaIndicators': false,
      });
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      final message = ChatMessage(
        id: 1,
        isOutgoing: true,
        text: 'sent',
        date: 1,
      );

      Future<void> pumpBubble({required bool isRead}) {
        return tester.pumpWidget(
          ChangeNotifierProvider<ThemeController>.value(
            value: theme,
            child: MaterialApp(
              home: Scaffold(
                body: MessageBubble(
                  message: message,
                  peerTitle: 'Test',
                  isGroup: false,
                  isRead: isRead,
                ),
              ),
            ),
          ),
        );
      }

      await pumpBubble(isRead: false);
      expect(
        find.byKey(const ValueKey('messageDeliveryDot-0')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('messageDeliveryDot-1')), findsNothing);

      await pumpBubble(isRead: true);
      expect(
        find.byKey(const ValueKey('messageDeliveryDot-0')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('messageDeliveryDot-1')),
        findsOneWidget,
      );
    });

    testWidgets('keeps an outgoing photo repeat badge beside its bubble', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      final message = ChatMessage(
        id: 6,
        isOutgoing: true,
        text: '',
        date: 1,
        contentType: 'messagePhoto',
        image: TdFileRef(id: 987, miniThumb: Uint8List(0)),
        imageWidth: 600,
        imageHeight: 400,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: SizedBox(
              width: 420,
              child: Scaffold(
                body: MessageBubble(
                  message: message,
                  peerTitle: 'Test',
                  isGroup: false,
                  showRepeat: true,
                ),
              ),
            ),
          ),
        ),
      );

      final badge = tester.getRect(
        find.byKey(const ValueKey('messageRepeatBadge')),
      );
      final bubble = tester.getRect(
        find.byKey(const ValueKey('messageTapTarget-6')),
      );
      expect((bubble.left - badge.right).abs(), lessThanOrEqualTo(7));

      // Expire the media lookup timeout scheduled by the image placeholder.
      await tester.pump(const Duration(minutes: 3, seconds: 1));
    });

    testWidgets('shows detail time on tap unless always-on is enabled', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      final message = ChatMessage(
        id: 2,
        isOutgoing: false,
        text: 'timestamp',
        date: DateTime(2024, 6, 4, 9, 5, 7).millisecondsSinceEpoch ~/ 1000,
      );

      Future<void> pump() => tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Test',
                isGroup: false,
              ),
            ),
          ),
        ),
      );

      await pump();
      expect(
        find.byKey(const ValueKey('messageTappedTimestamp')),
        findsNothing,
      );
      await tester.tap(find.byKey(const ValueKey('messageTapTarget-2')));
      await tester.pump();
      expect(
        find.byKey(const ValueKey('messageTappedTimestamp')),
        findsOneWidget,
      );

      theme.alwaysShowMessageTime = true;
      addTearDown(theme.dispose);
      await pump();
      expect(
        find.byKey(const ValueKey('messageInlineTimestamp')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('messageTappedTimestamp')),
        findsNothing,
      );
    });

    testWidgets('opens text selection through a double tap', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      final message = ChatMessage(
        id: 3,
        isOutgoing: false,
        text: 'selectable',
        date: 1,
      );
      ChatMessage? selected;

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Test',
                isGroup: false,
                onDoubleTap: (value) => selected = value,
              ),
            ),
          ),
        ),
      );

      final target = find.byKey(const ValueKey('messageTapTarget-3'));
      await tester.tap(target);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.tap(target);
      await tester.pump();

      expect(selected, same(message));
    });
  });

  group('MessageBubble reply quote', () {
    testWidgets('only the up arrow opens the original and media is inline', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      int? openedMessageId;
      final message =
          ChatMessage(
              id: 21,
              isOutgoing: false,
              text: 'reply',
              date: 1,
              replyToMessageId: 9,
              replyToDate: 1,
              replyToImage: TdFileRef(
                id: 999,
                miniThumb: base64Decode(
                  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
                ),
              ),
            )
            ..replyToSender = 'Quoted sender'
            ..replyToPreview = '';

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Test',
                isGroup: false,
                onOpenReply: (id) => openedMessageId = id,
              ),
            ),
          ),
        ),
      );

      expect(
        find.byKey(const ValueKey('messageReplyMediaPreview')),
        findsOneWidget,
      );
      expect(find.text('[图片]'), findsNothing);

      await tester.tap(find.byKey(const ValueKey('messageReplyQuote')));
      expect(openedMessageId, isNull);

      await tester.tap(find.byKey(const ValueKey('messageReplyOpenOriginal')));
      expect(openedMessageId, 9);

      // Expire the mocked TDLib download timeout before test teardown.
      await tester.pump(const Duration(minutes: 3, seconds: 1));
    });
  });

  group('MessageBubble sender roles', () {
    testWidgets('hides plain member badges by default and allows opt-in', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      final message = ChatMessage(
        id: 31,
        isOutgoing: false,
        text: 'hello',
        date: 1,
        senderName: 'Member',
        senderRole: MemberRole.member,
      );

      Future<void> pump() => tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Group',
                isGroup: true,
              ),
            ),
          ),
        ),
      );

      await pump();
      expect(theme.showPlainMemberRoleTags, isFalse);
      expect(find.byType(RoleTag), findsNothing);

      theme.showPlainMemberRoleTags = true;
      await tester.pump();
      expect(find.byType(RoleTag), findsOneWidget);
      expect(prefs.getBool('showPlainMemberRoleTags'), isTrue);
    });

    testWidgets('shows an incoming channel identity with a channel badge', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      final message = ChatMessage(
        id: 32,
        isOutgoing: false,
        senderIsChat: true,
        text: 'channel post',
        date: 1,
        senderName: 'News Channel',
        senderRole: MemberRole.channel,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Group',
                isGroup: true,
              ),
            ),
          ),
        ),
      );

      final tag = tester.widget<RoleTag>(find.byType(RoleTag));
      expect(tag.role, MemberRole.channel);
      expect(find.text('News Channel'), findsOneWidget);
    });

    testWidgets('shows an outgoing channel identity on the right', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      addTearDown(theme.dispose);
      final message = ChatMessage(
        id: 33,
        isOutgoing: true,
        senderIsChat: true,
        text: 'channel post',
        date: 1,
        senderName: 'News Channel',
        senderRole: MemberRole.channel,
      );

      await tester.pumpWidget(
        ChangeNotifierProvider<ThemeController>.value(
          value: theme,
          child: MaterialApp(
            home: Scaffold(
              body: MessageBubble(
                message: message,
                peerTitle: 'Group',
                isGroup: true,
              ),
            ),
          ),
        ),
      );

      final avatar = tester.widget<PhotoAvatar>(find.byType(PhotoAvatar));
      expect(avatar.title, 'News Channel');
      expect(
        tester.getCenter(find.byType(PhotoAvatar)).dx,
        greaterThan(
          tester
              .getCenter(find.byKey(const ValueKey('messageTapTarget-33')))
              .dx,
        ),
      );
    });
  });

  group('JSON helpers', () {
    test('management log resolves modern and legacy actor ids', () {
      expect(
        chatEventActorUserId({
          'member_id': {'@type': 'messageSenderUser', 'user_id': '42'},
        }),
        42,
      );
      expect(chatEventActorUserId({'user_id': 17}), 17);
    });

    test('parses TDLib int64-as-string', () {
      final obj = <String, dynamic>{'order': '123456789012345', 'n': 7};
      expect(obj.int64('order'), 123456789012345);
      expect(obj.integer('n'), 7);
      expect(obj.str('missing'), isNull);
    });
  });

  group('ChatMessage album visual media', () {
    test('parses a TDLib pending outgoing message', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': -7,
        'date': 1,
        'is_outgoing': true,
        'sending_state': {'@type': 'messageSendingStatePending'},
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'Sending'},
        },
      });

      expect(message, isNotNull);
      expect(message!.isSending, isTrue);
    });

    test('keeps messageSenderChat identity through parsing', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 30,
        'date': 1,
        'is_outgoing': true,
        'sender_id': {'@type': 'messageSenderChat', 'chat_id': '-100123'},
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': 'channel post'},
        },
      });

      expect(message, isNotNull);
      expect(message!.senderIsChat, isTrue);
      expect(message.senderId, -100123);
    });

    test(
      'includes photos and videos, excludes thumbnail-only placeholders',
      () {
        ChatMessage message(String type) => ChatMessage(
          id: 1,
          isOutgoing: false,
          text: '',
          date: 1,
          contentType: type,
          image: TdFileRef(id: 10),
        );

        expect(message('messagePhoto').isAlbumVisualMedia, isTrue);
        expect(message('messageVideo').isAlbumVisualMedia, isTrue);
        expect(message('messageSticker').isAlbumVisualMedia, isFalse);
        expect(message('messageAnimation').isAlbumVisualMedia, isFalse);
      },
    );

    test('photo messages keep a downloadable thumbnail before full image', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 42,
        'date': 1,
        'is_outgoing': false,
        'content': {
          '@type': 'messagePhoto',
          'photo': {
            '@type': 'photo',
            'sizes': [
              {
                '@type': 'photoSize',
                'type': 'm',
                'width': 320,
                'height': 180,
                'photo': {'@type': 'file', 'id': 10},
              },
              {
                '@type': 'photoSize',
                'type': 'y',
                'width': 1920,
                'height': 1080,
                'photo': {'@type': 'file', 'id': 20},
              },
            ],
          },
        },
      });

      expect(message, isNotNull);
      expect(message!.image?.id, 20);
      expect(message.image?.thumbnail?.id, 10);
      expect(message.imageWidth, 1920);
      expect(message.imageHeight, 1080);
    });
  });

  group('Chat message merge', () {
    test('does not reinsert a settled temporary outgoing message', () {
      final confirmed = ChatMessage(
        id: 42,
        isOutgoing: true,
        text: 'Hello',
        date: 1,
      );
      final delayedTemporary = ChatMessage(
        id: -7,
        isOutgoing: true,
        text: 'Hello',
        date: 1,
        isSending: true,
      );

      final merged = mergeChatMessages(
        [confirmed],
        [delayedTemporary],
        ignoredMessageIds: const {-7},
      );

      expect(merged, hasLength(1));
      expect(merged.single.id, 42);
    });
  });

  group('SecretChatService', () {
    test('parses TDLib secret chat readiness', () {
      Map<String, dynamic> secretChat(String state) => {
        '@type': 'secretChat',
        'state': {'@type': state},
      };

      expect(
        SecretChatService.readiness(secretChat('secretChatStatePending')),
        SecretChatReadiness.pending,
      );
      expect(
        SecretChatService.readiness(secretChat('secretChatStateReady')),
        SecretChatReadiness.ready,
      );
      expect(
        SecretChatService.readiness(secretChat('secretChatStateClosed')),
        SecretChatReadiness.closed,
      );
      expect(
        SecretChatService.readiness(secretChat('futureSecretChatState')),
        SecretChatReadiness.unknown,
      );
    });

    test('loads a known TDLib secret chat', () async {
      Map<String, dynamic>? request;
      final result = await SecretChatService.get(
        17,
        query: (value) async {
          request = value;
          return {
            '@type': 'secretChat',
            'id': 17,
            'state': {'@type': 'secretChatStateReady'},
          };
        },
      );

      expect(request, {'@type': 'getSecretChat', 'secret_chat_id': 17});
      expect(SecretChatService.readiness(result), SecretChatReadiness.ready);
    });

    test('creates and validates a TDLib secret chat', () async {
      Map<String, dynamic>? request;
      final result = await SecretChatService.create(
        42,
        query: (value) async {
          request = value;
          return {
            '@type': 'chat',
            'id': '-123',
            'title': 'Ada',
            'type': {
              '@type': 'chatTypeSecret',
              'secret_chat_id': 17,
              'user_id': 42,
            },
          };
        },
      );

      expect(request, {'@type': 'createNewSecretChat', 'user_id': 42});
      expect(result.id, -123);
      expect(result.title, 'Ada');
    });

    test('rejects a non-secret TDLib response', () async {
      await expectLater(
        SecretChatService.create(
          42,
          query: (_) async => {
            '@type': 'chat',
            'id': '-123',
            'type': {'@type': 'chatTypePrivate', 'user_id': 42},
          },
        ),
        throwsFormatException,
      );
    });
  });

  group('ChatMessage replies', () {
    ChatMessage message({
      bool hasThread = false,
      int replyCount = 0,
      int? lastReplyId,
    }) => ChatMessage(
      id: 1,
      isOutgoing: false,
      text: 'message',
      date: 1,
      hasCommentThread: hasThread,
      commentCount: replyCount,
      lastCommentMessageId: lastReplyId,
    );

    test('thread metadata without replies does not expose Replies', () {
      expect(message(hasThread: true).hasActualReplies, isFalse);
      expect(
        message(hasThread: true, lastReplyId: 0).hasActualReplies,
        isFalse,
      );
    });

    test('reply count or a real last reply exposes Replies', () {
      expect(message(replyCount: 1).hasActualReplies, isTrue);
      expect(message(lastReplyId: 42).hasActualReplies, isTrue);
    });
  });

  group('MediaAlbumLayout', () {
    test('uses proportional non-overlapping rows for mixed albums', () {
      final layout = buildTelegramMediaAlbumLayout(
        items: const [
          MediaAlbumItem(width: 1600, height: 900),
          MediaAlbumItem(width: 900, height: 1600),
          MediaAlbumItem(width: 1200, height: 1200),
          MediaAlbumItem(width: 1024, height: 768),
          MediaAlbumItem(width: 768, height: 1024),
        ],
        maxWidth: 330,
      );

      expect(layout.tiles, hasLength(5));
      expect(layout.width, 330);
      expect(layout.height, greaterThan(0));
      for (final tile in layout.tiles) {
        expect(tile.left, greaterThanOrEqualTo(0));
        expect(tile.top, greaterThanOrEqualTo(0));
        expect(tile.right, lessThanOrEqualTo(layout.width + 0.01));
        expect(tile.bottom, lessThanOrEqualTo(layout.height + 0.01));
        expect(tile.width, greaterThan(0));
        expect(tile.height, greaterThan(0));
      }

      for (var i = 0; i < layout.tiles.length; i++) {
        for (var j = i + 1; j < layout.tiles.length; j++) {
          expect(layout.tiles[i].overlaps(layout.tiles[j]), isFalse);
        }
      }
    });
  });

  group('ThemeController archived chats', () {
    test('defaults to pull-down and migrates former positions', () async {
      SharedPreferences.setMockInitialValues({});
      var prefs = await SharedPreferences.getInstance();
      expect(
        ThemeController(prefs).archivedChatsDisplayMode,
        ArchivedChatsDisplayMode.pullDown,
      );

      SharedPreferences.setMockInitialValues({
        'archivedChatsDisplayMode': 'always',
      });
      prefs = await SharedPreferences.getInstance();
      expect(
        ThemeController(prefs).archivedChatsDisplayMode,
        ArchivedChatsDisplayMode.firstPosition,
      );

      SharedPreferences.setMockInitialValues({
        'archivedChatsDisplayMode': 'secondScreen',
      });
      prefs = await SharedPreferences.getInstance();
      expect(
        ThemeController(prefs).archivedChatsDisplayMode,
        ArchivedChatsDisplayMode.nextPage,
      );
    });

    test('places inline archive rows at the requested list position', () {
      expect(
        ArchivedChatsDisplayMode.firstPosition.insertionIndex(
          chatCount: 20,
          visibleRows: 6,
        ),
        0,
      );
      expect(
        ArchivedChatsDisplayMode.nextPage.insertionIndex(
          chatCount: 20,
          visibleRows: 6,
        ),
        6,
      );
      expect(
        ArchivedChatsDisplayMode.nextPage.insertionIndex(
          chatCount: 3,
          visibleRows: 6,
        ),
        3,
      );
      expect(
        ArchivedChatsDisplayMode.pullDown.insertionIndex(
          chatCount: 20,
          visibleRows: 6,
        ),
        -1,
      );
    });
  });

  group('ThemeController chat folders', () {
    test('defaults to tabbed folders when no preference exists', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();

      expect(
        ThemeController(prefs).chatFolderDisplayMode,
        ChatFolderDisplayMode.tabs,
      );
    });

    test('migrates the former folder visibility toggle', () async {
      SharedPreferences.setMockInitialValues({'showChatFolderFilter': false});
      var prefs = await SharedPreferences.getInstance();
      expect(
        ThemeController(prefs).chatFolderDisplayMode,
        ChatFolderDisplayMode.hidden,
      );

      SharedPreferences.setMockInitialValues({'showChatFolderFilter': true});
      prefs = await SharedPreferences.getInstance();
      expect(
        ThemeController(prefs).chatFolderDisplayMode,
        ChatFolderDisplayMode.menu,
      );
    });

    test('prefers and persists the explicit display mode', () async {
      SharedPreferences.setMockInitialValues({
        'showChatFolderFilter': false,
        'chatFolderDisplayMode': 'tabs',
      });
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);

      expect(theme.chatFolderDisplayMode, ChatFolderDisplayMode.tabs);
      theme.chatFolderDisplayMode = ChatFolderDisplayMode.menu;
      expect(prefs.getString('chatFolderDisplayMode'), 'menu');
    });

    test('migrates legacy folder swipe preferences', () async {
      SharedPreferences.setMockInitialValues({
        'chatFolderDisplayMode': 'tabs',
        'disableChatListSwipeActions': true,
        'chatListFolderSwipeSwitching': true,
      });
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);

      expect(theme.chatListSwipeBehavior, ChatListSwipeBehavior.switchFolders);
      expect(theme.disableChatListSwipeActions, isTrue);
      expect(theme.chatListFolderSwipeSwitching, isTrue);
      expect(prefs.getString('chatListSwipeBehavior'), 'switchFolders');

      theme.chatFolderDisplayMode = ChatFolderDisplayMode.menu;
      expect(theme.disableChatListSwipeActions, isTrue);
      expect(theme.chatListFolderSwipeSwitching, isTrue);
    });

    test('uses gesture defaults and persists explicit choices', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);

      expect(theme.chatListSwipeBehavior, ChatListSwipeBehavior.chatActions);
      expect(
        theme.threeFingerSwipeBehavior,
        ThreeFingerSwipeBehavior.switchFolders,
      );
      expect(theme.chatListHoldSwipeActions, isFalse);

      theme.chatListSwipeBehavior = ChatListSwipeBehavior.switchFolders;
      theme.chatListHoldSwipeActions = true;
      theme.threeFingerSwipeBehavior = ThreeFingerSwipeBehavior.switchAccounts;

      expect(prefs.getString('chatListSwipeBehavior'), 'switchFolders');
      expect(prefs.getBool('chatListHoldSwipeActions'), isTrue);
      expect(prefs.getString('threeFingerSwipeBehavior'), 'switchAccounts');
    });
  });

  group('ThemeController fonts', () {
    test('hides Google storage prefixes from every font label', () async {
      SharedPreferences.setMockInitialValues({
        'fontChoice': 'custom',
        'customPrimaryFontFamily': 'google:Roboto',
        'cjkFontChoice': 'customCjk',
        'customCjkFontFamily': 'google:Noto Sans SC',
        'fontFallbackChain': [
          'google:Roboto',
          'google:Noto Sans SC',
          'PingFang SC',
        ],
      });
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);

      expect(theme.effectivePrimaryFontLabel, 'Roboto');
      expect(theme.effectiveCjkFontLabel, 'Noto Sans SC');
      expect(theme.effectiveFontChainLabel, 'Roboto / Noto Sans SC / +1');
      expect(theme.effectiveFontChainLabel, isNot(contains('google:')));
    });

    test('applies explicit fallback chain in order', () async {
      SharedPreferences.setMockInitialValues({
        'fontFallbackChain': ['Futura', 'PingFang SC', 'Futura'],
      });
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);

      expect(theme.fontFallbackChain, ['Futura', 'PingFang SC']);
      final style = theme.applyAppTextStyle(const TextStyle());
      expect(style.fontFamily, 'Futura');
      expect(style.fontFamilyFallback, contains('PingFang SC'));
    });

    test('honors system bold text by increasing app text weights', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);

      final regular = theme.applyAppTextStyle(
        const TextStyle(),
        boldText: true,
      );
      final medium = theme.applyAppTextStyle(
        const TextStyle(fontWeight: FontWeight.w500),
        boldText: true,
      );

      expect(regular.fontWeight, FontWeight.w600);
      expect(medium.fontWeight, FontWeight.w700);
    });

    test(
      'keeps explicit text weights unchanged when system bold text is off',
      () {
        expect(
          AppTextWeight.forSystemBoldText(FontWeight.w400, boldText: false),
          FontWeight.w400,
        );
        expect(
          AppTextWeight.forSystemBoldText(FontWeight.w600, boldText: true),
          FontWeight.w800,
        );
      },
    );
  });

  group('BotMenuInfo', () {
    test('uses the bot menu text even when TDLib uses a menu URL', () {
      const menu = BotMenuInfo(
        type: 'botMenuButton',
        text: '小程序购买',
        url: 'menu://https://example.com/webapp',
      );

      expect(menu.isLegacyMenuUrl, isTrue);
      expect(menu.actionTitle, '小程序购买');
    });

    test('falls back to Open when a bot menu has no text', () {
      const menu = BotMenuInfo(
        type: 'botMenuButton',
        url: 'menu://https://webappinternal.telegram.org/botfather',
      );

      expect(menu.actionTitle, 'Open');
    });
  });

  group('SponsoredMessagesCache', () {
    test('caches an account and channel response for five minutes', () async {
      var now = DateTime(2026, 7, 13, 12);
      final cache = SponsoredMessagesCache(now: () => now);
      var calls = 0;
      Future<Map<String, dynamic>> fetch() async {
        calls++;
        return {
          '@type': 'sponsoredMessages',
          'messages': [
            {'@type': 'sponsoredMessage', 'message_id': calls},
          ],
        };
      }

      final first = await cache.retrieve(cacheKey: '0:-1001', fetch: fetch);
      now = now.add(const Duration(minutes: 4, seconds: 59));
      final cached = await cache.retrieve(cacheKey: '0:-1001', fetch: fetch);
      now = now.add(const Duration(seconds: 2));
      final refreshed = await cache.retrieve(cacheKey: '0:-1001', fetch: fetch);

      expect(calls, 2);
      expect(cached, same(first));
      expect(refreshed.response['messages'], [
        {'@type': 'sponsoredMessage', 'message_id': 2},
      ]);
    });

    test('refreshes an open chat even while the result is cached', () async {
      final cache = SponsoredMessagesCache();
      var calls = 0;
      Future<Map<String, dynamic>> fetch() async {
        calls++;
        return {'@type': 'sponsoredMessages', 'messages': const []};
      }

      await cache.retrieve(cacheKey: '0:-1001', fetch: fetch);
      await cache.retrieve(cacheKey: '0:-1001', refresh: true, fetch: fetch);

      expect(calls, 2);
    });

    test('coalesces simultaneous requests for the same channel', () async {
      final gate = Completer<Map<String, dynamic>>();
      final cache = SponsoredMessagesCache();
      var calls = 0;

      Future<Map<String, dynamic>> fetch() {
        calls++;
        return gate.future;
      }

      final first = cache.retrieve(cacheKey: '0:-1001', fetch: fetch);
      final second = cache.retrieve(cacheKey: '0:-1001', fetch: fetch);
      gate.complete({'@type': 'sponsoredMessages', 'messages': const []});

      expect(await first, same(await second));
      expect(calls, 1);
    });
  });

  group('TDParse.messageText', () {
    test('protected-content toggles are non-interactive service messages', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 9,
        'chat_id': -1001,
        'date': 1,
        'content': {
          '@type': 'messageChatHasProtectedContentToggled',
          'new_has_protected_content': true,
        },
      });

      expect(message, isNotNull);
      expect(message!.isService, isTrue);
      expect(message.contentType, 'messageChatHasProtectedContentToggled');
    });

    test('photo with no caption uses localized placeholder', () {
      final content = <String, dynamic>{'@type': 'messagePhoto'};
      expect(
        TDParse.messageText(content),
        AppStrings.t(AppStringKeys.composerImagePreview),
      );
    });

    test('plain text passes through', () {
      final content = <String, dynamic>{
        '@type': 'messageText',
        'text': {'@type': 'formattedText', 'text': 'hello'},
      };
      expect(TDParse.messageText(content), 'hello');
    });

    test('GIF without a caption uses a GIF placeholder', () {
      final content = <String, dynamic>{
        '@type': 'messageAnimation',
        'caption': {'@type': 'formattedText', 'text': ''},
      };

      expect(TDParse.messageText(content), '[GIF]');
    });

    test('redacts only a message carrying restriction info', () {
      const notice =
          "This message can't be displayed because it violated Telegram's Terms of Service.";
      final restricted = TDParse.message({
        'id': 11,
        'date': 1,
        'content': {
          '@type': 'messagePhoto',
          'caption': {'@type': 'formattedText', 'text': 'Original photo'},
        },
        'restriction_info': {
          '@type': 'restrictionInfo',
          'reason': 'terms',
          'restriction_reason': notice,
        },
      });
      final ordinary = TDParse.message({
        'id': 12,
        'date': 2,
        'content': {
          '@type': 'messageText',
          'text': {'@type': 'formattedText', 'text': notice},
        },
      });

      expect(restricted, isNotNull);
      expect(restricted!.text, notice);
      expect(restricted.isContentRestricted, isTrue);
      expect(restricted.restrictionReasonCode, 'terms');
      expect(restricted.restrictedContentText, 'Original photo');
      expect(restricted.hasRestrictedRevealContent, isTrue);
      expect(restricted.isPhoto, isFalse);
      expect(restricted.image, isNull);
      expect(restricted.buttonRows, isEmpty);
      expect(restricted.canRepeat, isFalse);

      expect(ordinary, isNotNull);
      expect(ordinary!.text, notice);
      expect(ordinary.isContentRestricted, isFalse);
    });

    test('classifies porno restrictions separately from ToS restrictions', () {
      const notice =
          "This message couldn't be displayed on your device because it contains pornographic materials.";
      final restrictedObject = <String, dynamic>{
        'restriction_info': {
          '@type': 'restrictionInfo',
          'reason': 'porno',
          'restriction_reason': notice,
          'has_sensitive_content': true,
        },
      };

      expect(TDParse.restrictionReasonFor(restrictedObject), notice);
      expect(TDParse.restrictionReasonCodeFor(restrictedObject), 'porno');
      expect(TDParse.hasSensitiveRestriction(restrictedObject), isTrue);
      expect(TDParse.isBlockingRestriction(restrictedObject), isTrue);
      expect(TDParse.isPornographicRestriction(restrictedObject), isTrue);
      expect(TDParse.isPornographicRestrictionText(notice), isTrue);
      expect(TDParse.isTelegramTermsRestrictionText(notice), isFalse);
      expect(TDParse.isTermsRestriction(restrictedObject), isFalse);

      expect(
        TDParse.isBlockingRestriction({
          'restriction_info': {
            '@type': 'restrictionInfo',
            'restriction_reason':
                'This channel cannot be displayed due to porn-ios.',
            'has_sensitive_content': true,
          },
        }),
        isTrue,
      );
      expect(
        TDParse.isPornographicRestriction({
          'restriction_info': {
            '@type': 'restrictionInfo',
            'reason': 'porn-ios',
            'restriction_reason': 'Sensitive content is unavailable.',
          },
        }),
        isTrue,
      );
      expect(
        TDParse.isTermsRestriction({
          'restriction_info': {
            '@type': 'restrictionInfo',
            'restriction_reason': 'Sensitive content is unavailable.',
            'has_sensitive_content': true,
          },
        }),
        isFalse,
      );
      expect(
        TDParse.isBlockingRestriction({
          'restriction_info': {
            '@type': 'restrictionInfo',
            'restriction_reason': '',
            'has_sensitive_content': true,
          },
        }),
        isFalse,
      );
    });

    test('classifies Telegram ToS restrictions as safety restrictions', () {
      const notice =
          "This message can't be displayed because it violated Telegram's Terms of Service.";
      final restrictedObject = <String, dynamic>{
        'restriction_info': {
          '@type': 'restrictionInfo',
          'reason': 'terms',
          'restriction_reason': notice,
        },
      };

      expect(TDParse.isPornographicRestrictionText(notice), isFalse);
      expect(TDParse.isTelegramTermsRestrictionText(notice), isTrue);
      expect(TDParse.isBlockingRestriction(restrictedObject), isTrue);
      expect(TDParse.isTermsRestriction(restrictedObject), isTrue);
    });

    test('dice keeps emoji preview and parsed value', () {
      final message = TDParse.message({
        'id': 10,
        'date': 1,
        'content': {'@type': 'messageDice', 'emoji': '🎲', 'value': 6},
      });
      expect(message, isNotNull);
      expect(message!.text, '🎲');
      expect(message.diceEmoji, '🎲');
      expect(message.diceValue, 6);
      expect(message.isDice, isTrue);
    });

    test('flattens Telegram core RichText markdown nodes', () {
      final rich = <String, dynamic>{
        '@type': 'textConcat',
        'texts': [
          {'@type': 'textPlain', 'text': 'Hello '},
          {
            '@type': 'textBold',
            'text': {'@type': 'textPlain', 'text': 'bold'},
          },
          {'@type': 'textPlain', 'text': ' '},
          {
            '@type': 'textUrl',
            'text': {'@type': 'textPlain', 'text': 'site'},
            'url': 'https://example.com',
          },
        ],
      };

      expect(TDParse.richTextText(rich), 'Hello bold site');
      final entities = TDParse.richTextEntities(rich);
      expect(entities.map((e) => e.type), [
        'textEntityTypeBold',
        'textEntityTypeTextUrl',
      ]);
      expect(entities[1].url, 'https://example.com');
    });

    test('supports Bot API rich text class names', () {
      Map<String, dynamic> plain(String text) => {
        '@type': 'RichTextPlain',
        'text': text,
      };
      Map<String, dynamic> wrap(String type, String text) => {
        '@type': type,
        'text': plain(text),
      };

      final rich = <String, dynamic>{
        '@type': 'RichText',
        'texts': [
          wrap('RichTextBold', 'bold'),
          plain(' '),
          wrap('RichTextItalic', 'italic'),
          plain(' '),
          wrap('RichTextUnderline', 'underline'),
          plain(' '),
          wrap('RichTextStrikethrough', 'strike'),
          plain(' '),
          wrap('RichTextSpoiler', 'spoiler'),
          plain(' '),
          wrap('RichTextDateTime', 'tomorrow'),
          plain(' '),
          {
            '@type': 'RichTextTextMention',
            'text': plain('Alice'),
            'user': {'@type': 'User', 'id': 42},
          },
          plain(' '),
          wrap('RichTextSubscript', 'sub'),
          plain(' '),
          wrap('RichTextSuperscript', 'super'),
          plain(' '),
          wrap('RichTextMarked', 'marked'),
          plain(' '),
          wrap('RichTextCode', 'code'),
          plain(' '),
          {
            '@type': 'RichTextCustomEmoji',
            'text': '🙂',
            'custom_emoji_id': '123456',
          },
          plain(' '),
          {'@type': 'RichTextMathematicalExpression', 'expression': r'x^2'},
          plain(' '),
          {
            '@type': 'RichTextUrl',
            'text': plain('site'),
            'url': 'https://example.com',
          },
          plain(' '),
          {
            '@type': 'RichTextEmailAddress',
            'text': plain('a@example.com'),
            'email_address': 'a@example.com',
          },
          plain(' '),
          {
            '@type': 'RichTextPhoneNumber',
            'text': plain('+123456789'),
            'phone_number': '+123456789',
          },
          plain(' '),
          {
            '@type': 'RichTextBankCardNumber',
            'text': plain('4242 4242 4242 4242'),
            'bank_card_number': '4242 4242 4242 4242',
          },
          plain(' '),
          {
            '@type': 'RichTextMention',
            'text': plain('@telegram'),
            'username': 'telegram',
          },
          plain(' '),
          {
            '@type': 'RichTextHashtag',
            'text': plain('#topic'),
            'hashtag': 'topic',
          },
          plain(' '),
          {
            '@type': 'RichTextCashtag',
            'text': plain(r'$USD'),
            'cashtag': 'USD',
          },
          plain(' '),
          {
            '@type': 'RichTextBotCommand',
            'text': plain('/start'),
            'bot_command': 'start',
          },
          plain(' '),
          {'@type': 'RichTextAnchor', 'name': 'chapter-1'},
          {
            '@type': 'RichTextAnchorLink',
            'text': plain('chapter'),
            'anchor_name': 'chapter-1',
          },
          plain(' '),
          {
            '@type': 'RichTextReference',
            'name': 'note-1',
            'text': plain('reference'),
          },
          plain(' '),
          {
            '@type': 'RichTextReferenceLink',
            'text': plain('note'),
            'reference_name': 'note-1',
          },
        ],
      };

      expect(
        TDParse.richTextText(rich),
        contains(
          'bold italic underline strike spoiler tomorrow Alice sub super marked '
          'code 🙂 x^2 site a@example.com +123456789 '
          '4242 4242 4242 4242 @telegram #topic \$USD /start chapter reference note',
        ),
      );
      final entities = TDParse.richTextEntities(rich);
      expect(entities.map((e) => e.type), [
        'textEntityTypeBold',
        'textEntityTypeItalic',
        'textEntityTypeUnderline',
        'textEntityTypeStrikethrough',
        'textEntityTypeSpoiler',
        'textEntityTypeDateTime',
        'textEntityTypeMentionName',
        'textEntityTypeSubscript',
        'textEntityTypeSuperscript',
        'textEntityTypeMarked',
        'textEntityTypeCode',
        'textEntityTypeCustomEmoji',
        'textEntityTypeMathematicalExpression',
        'textEntityTypeTextUrl',
        'textEntityTypeEmailAddress',
        'textEntityTypePhoneNumber',
        'textEntityTypeBankCardNumber',
        'textEntityTypeTextUrl',
        'textEntityTypeHashtag',
        'textEntityTypeCashtag',
        'textEntityTypeBotCommand',
        'textEntityTypeTextUrl',
        'textEntityTypeTextUrl',
      ]);
      expect(
        entities
            .firstWhere((e) => e.type == 'textEntityTypeMentionName')
            .userId,
        42,
      );
      expect(
        entities
            .firstWhere((e) => e.type == 'textEntityTypeCustomEmoji')
            .customEmojiId,
        123456,
      );
      expect(entities.where((e) => e.url == '#chapter-1'), hasLength(1));
      expect(entities.where((e) => e.url == '#note-1'), hasLength(1));
    });

    test('parses TDLib messageRichMessage in chat messages', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 100,
        'date': 1,
        'is_outgoing': false,
        'content': {
          '@type': 'messageRichMessage',
          'message': {
            '@type': 'richMessage',
            'is_rtl': false,
            'is_full': true,
            'blocks': [
              {
                '@type': 'pageBlockParagraph',
                'text': {
                  '@type': 'richTexts',
                  'texts': [
                    {'@type': 'richTextPlain', 'text': 'Hello '},
                    {
                      '@type': 'richTextBold',
                      'text': {'@type': 'richTextPlain', 'text': 'bold'},
                    },
                    {'@type': 'richTextPlain', 'text': ' and '},
                    {
                      '@type': 'richTextUrl',
                      'text': {'@type': 'richTextPlain', 'text': 'link'},
                      'url': 'https://example.com',
                      'is_cached': false,
                    },
                  ],
                },
              },
              {
                '@type': 'pageBlockPreformatted',
                'language': 'dart',
                'text': {'@type': 'richTextPlain', 'text': 'final x = 1;'},
              },
              {
                '@type': 'pageBlockMathematicalExpression',
                'expression': r'x^2',
              },
              {
                '@type': 'pageBlockTable',
                'is_bordered': true,
                'is_striped': true,
                'caption': {
                  '@type': 'pageBlockCaption',
                  'text': {'@type': 'richTextPlain', 'text': 'Metrics'},
                },
                'cells': [
                  [
                    {
                      '@type': 'richBlockTableCell',
                      'is_header': true,
                      'align': 'center',
                      'valign': 'middle',
                      'text': {'@type': 'richTextPlain', 'text': 'Name'},
                    },
                    {
                      '@type': 'richBlockTableCell',
                      'is_header': true,
                      'text': {'@type': 'richTextPlain', 'text': 'Value'},
                    },
                  ],
                  [
                    {
                      '@type': 'richBlockTableCell',
                      'text': {'@type': 'richTextPlain', 'text': 'Speed'},
                    },
                    {
                      '@type': 'richBlockTableCell',
                      'text': {
                        '@type': 'richTextBold',
                        'text': {'@type': 'richTextPlain', 'text': '42'},
                      },
                    },
                  ],
                ],
              },
            ],
          },
        },
      });

      expect(message, isNotNull);
      expect(message!.richMessageIsFull, isTrue);
      expect(message.text, isEmpty);
      expect(message.textEntities, isEmpty);
      expect(message.richBlocks, hasLength(4));
      final paragraph = message.richBlocks[0];
      expect(paragraph.kind, RichMessageBlockKind.paragraph);
      expect(paragraph.text, 'Hello bold and link');
      expect(paragraph.textEntities.map((e) => e.type), [
        'textEntityTypeBold',
        'textEntityTypeTextUrl',
      ]);
      expect(paragraph.textEntities[1].url, 'https://example.com');
      final preformatted = message.richBlocks[1];
      expect(preformatted.kind, RichMessageBlockKind.preformatted);
      expect(preformatted.text, 'final x = 1;');
      expect(preformatted.language, 'dart');
      expect(message.richBlocks[2].mathExpression, r'x^2');
      final table = message.richBlocks.last;
      expect(table.caption, 'Metrics');
      expect(table.isBordered, isTrue);
      expect(table.isStriped, isTrue);
      expect(table.tableRows, hasLength(2));
      expect(table.tableRows.first.first.text, 'Name');
      expect(table.tableRows.first.first.isHeader, isTrue);
      expect(table.tableRows.first.first.horizontalAlignment, 'center');
      expect(table.tableRows.first.first.verticalAlignment, 'middle');
      expect(table.tableRows[1][1].text, '42');
      expect(table.tableRows[1][1].entities.single.type, 'textEntityTypeBold');
    });

    test(
      'does not render the generic placeholder for table-only rich messages',
      () {
        final message = TDParse.message({
          '@type': 'message',
          'id': 102,
          'date': 1,
          'is_outgoing': true,
          'content': {
            '@type': 'messageRichMessage',
            'message': {
              '@type': 'richMessage',
              'is_rtl': false,
              'is_full': false,
              'blocks': [
                {
                  '@type': 'pageBlockTable',
                  'cells': [
                    [
                      {
                        '@type': 'pageBlockTableCell',
                        'is_header': true,
                        'text': {'@type': 'richTextPlain', 'text': 'Name'},
                      },
                    ],
                  ],
                },
              ],
            },
          },
        });

        expect(message, isNotNull);
        expect(message!.text, isEmpty);
        expect(message.richBlocks, hasLength(1));
        expect(message.richMessageIsFull, isFalse);
      },
    );

    test('parses rich map blocks and suppresses the generic placeholder', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 103,
        'date': 1,
        'is_outgoing': true,
        'content': {
          '@type': 'messageRichMessage',
          'message': {
            '@type': 'richMessage',
            'is_full': true,
            'blocks': [
              {
                '@type': 'pageBlockMap',
                'location': {
                  '@type': 'location',
                  'latitude': 35.681236,
                  'longitude': 139.767125,
                },
                'zoom': 17,
                'width': 640,
                'height': 360,
                'caption': {
                  '@type': 'pageBlockCaption',
                  'text': {'@type': 'richTextPlain', 'text': 'Tokyo'},
                },
              },
            ],
          },
        },
      });

      expect(message, isNotNull);
      expect(message!.text, isEmpty);
      expect(message.richBlocks, hasLength(1));
      final map = message.richBlocks.single;
      expect(map.isMap, isTrue);
      expect(map.mapLocation?.latitude, 35.681236);
      expect(map.mapLocation?.longitude, 139.767125);
      expect(map.mapZoom, 17);
      expect(map.mapWidth, 640);
      expect(map.mapHeight, 360);
      expect(map.caption, 'Tokyo');
    });

    test('extracts markdown pipe tables into rich table blocks', () {
      final message = TDParse.message({
        '@type': 'message',
        'id': 101,
        'date': 1,
        'is_outgoing': true,
        'content': {
          '@type': 'messageText',
          'text': {
            '@type': 'formattedText',
            'text':
                'Before\n\n| Name | Value |\n| ---- | ----- |\n| Speed | 42 |\n\nAfter',
          },
        },
      });

      expect(message, isNotNull);
      expect(message!.text, 'Before\n\nAfter');
      expect(message.richBlocks, hasLength(1));
      final table = message.richBlocks.single;
      expect(table.tableRows, hasLength(2));
      expect(table.tableRows.first.first.text, 'Name');
      expect(table.tableRows.first.first.isHeader, isTrue);
      expect(table.tableRows[1][1].text, '42');
    });
  });

  group('TDParse.chat', () {
    test('preserves unread mention count for chat-list indicators', () {
      final chat = TDParse.chat({
        '@type': 'chat',
        'id': 42,
        'title': 'Mentioned chat',
        'unread_count': 3,
        'unread_mention_count': 2,
        'type': {'@type': 'chatTypeBasicGroup', 'basic_group_id': 42},
        'positions': <Object>[],
      });

      expect(chat, isNotNull);
      expect(chat!.unreadMentionCount, 2);
    });
  });

  group('TDParse.messageButtonRows', () {
    test('parses inline keyboard url and callback buttons', () {
      final rows = TDParse.messageButtonRows({
        '@type': 'replyMarkupInlineKeyboard',
        'rows': [
          [
            {
              '@type': 'inlineKeyboardButton',
              'text': 'Open',
              'type': {
                '@type': 'inlineKeyboardButtonTypeUrl',
                'url': 'https://example.com',
              },
            },
            {
              '@type': 'inlineKeyboardButton',
              'text': 'Tap',
              'type': {
                '@type': 'inlineKeyboardButtonTypeCallback',
                'data': 'abc',
              },
            },
          ],
        ],
      });

      expect(rows, hasLength(1));
      expect(rows.first, hasLength(2));
      expect(rows.first[0].text, 'Open');
      expect(rows.first[0].url, 'https://example.com');
      expect(rows.first[1].isCallback, isTrue);
      expect(rows.first[1].data, 'abc');
    });

    test('parses reply keyboard text buttons', () {
      final rows = TDParse.messageButtonRows({
        '@type': 'replyMarkupShowKeyboard',
        'rows': [
          [
            {
              '@type': 'keyboardButton',
              'text': 'OK',
              'type': {'@type': 'keyboardButtonTypeText'},
            },
          ],
        ],
      });

      expect(rows.single.single.text, 'OK');
      expect(rows.single.single.type, 'keyboardButtonTypeText');
      expect(rows.single.single.isReplyKeyboard, isTrue);
    });

    test('marks inline and reply keyboard Web App buttons', () {
      final inlineRows = TDParse.messageButtonRows({
        '@type': 'replyMarkupInlineKeyboard',
        'rows': [
          [
            {
              '@type': 'inlineKeyboardButton',
              'text': 'Mini App',
              'type': {
                '@type': 'inlineKeyboardButtonTypeWebApp',
                'url': 'https://example.com/app',
              },
            },
          ],
        ],
      });
      final replyRows = TDParse.messageButtonRows({
        '@type': 'replyMarkupShowKeyboard',
        'rows': [
          [
            {
              '@type': 'keyboardButton',
              'text': 'Launch',
              'type': {
                '@type': 'keyboardButtonTypeWebApp',
                'url': 'https://example.com/reply-app',
              },
            },
          ],
        ],
      });

      expect(inlineRows.single.single.isWebApp, isTrue);
      expect(inlineRows.single.single.url, 'https://example.com/app');
      expect(replyRows.single.single.isWebApp, isTrue);
      expect(replyRows.single.single.isReplyKeyboard, isTrue);
      expect(replyRows.single.single.url, 'https://example.com/reply-app');
    });
  });

  group('TDParse.linkPreview', () {
    test('parses title, full description, and article photo', () {
      final preview = TDParse.linkPreview({
        '@type': 'linkPreview',
        'url': 'https://example.com/rich',
        'display_url': 'example.com/rich',
        'site_name': 'Example',
        'title': 'Rich Message Demo',
        'description': {
          '@type': 'formattedText',
          'text': 'Select a screen\n- Text Formatting\n- Code & Pre',
          'entities': [
            {
              '@type': 'textEntity',
              'offset': 18,
              'length': 15,
              'type': {'@type': 'textEntityTypeBold'},
            },
          ],
        },
        'type': {
          '@type': 'linkPreviewTypeArticle',
          'photo': {
            '@type': 'photo',
            'sizes': [
              {
                '@type': 'photoSize',
                'width': 320,
                'height': 180,
                'photo': {'@type': 'file', 'id': 42},
              },
            ],
          },
        },
        'show_large_media': true,
        'show_media_above_description': true,
        'show_above_text': false,
      });

      expect(preview, isNotNull);
      expect(preview!.title, 'Rich Message Demo');
      expect(preview.description, contains('Text Formatting'));
      expect(preview.descriptionEntities.single.type, 'textEntityTypeBold');
      expect(preview.image?.id, 42);
      expect(preview.imageWidth, 320);
      expect(preview.imageHeight, 180);
      expect(preview.showLargeMedia, isTrue);
    });
  });

  group('KeywordBlocker', () {
    test('matches plain keywords and regex rules', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final blocker = KeywordBlocker.shared;
      blocker.initialize(prefs);
      blocker.replaceAll(['free money', r're:\b\d{5}\b', r'/hello\s+world/i']);

      expect(blocker.matches('Claim FREE MONEY now'), isTrue);
      expect(blocker.matches('code 12345 please'), isTrue);
      expect(blocker.matches('HELLO     WORLD'), isTrue);
      expect(blocker.matches('normal message'), isFalse);
    });
  });

  group('CountryMessageFilter', () {
    test(
      'matches selected countries and applies configured exemptions',
      () async {
        SharedPreferences.setMockInitialValues({
          'countryMessageFilter.selectedCountries': ['JP', 'US'],
        });
        final prefs = await SharedPreferences.getInstance();
        final filter = CountryMessageFilter()..initialize(prefs);

        expect(filter.matchesUser(phoneNumber: '+81 90 1234 5678'), isTrue);
        expect(
          filter.matchesUser(isContact: true, phoneNumber: '+81 90 1234 5678'),
          isTrue,
        );
        expect(filter.matchesUser(phoneNumber: '+44 20 7946 0958'), isFalse);
        expect(filter.matchesUser(), isFalse);
        expect(
          filter.shouldExempt(
            hasCommonPrivateGroup: false,
            commonGroupCount: 0,
            isPlainTextWithoutLinks: true,
            hasNonDefaultAvatar: false,
          ),
          isTrue,
        );
      },
    );
  });

  group('AppFontChoice', () {
    test('applies primary font before CJK and system fallbacks', () {
      final style = AppFontChoice.futura.applyTextStyle(
        const TextStyle(fontSize: 16),
        cjkFallback: AppFontChoice.pingFangTw,
      );

      expect(style.fontFamily, 'Futura');
      expect(style.fontFamilyFallback, isNotNull);
      expect(style.fontFamilyFallback!.first, 'PingFang TC');
      expect(style.fontFamilyFallback!, contains('Helvetica Neue'));
    });

    test('preset fonts ignore stale custom font families', () {
      final style = AppFontChoice.futura.applyTextStyle(
        const TextStyle(fontSize: 16),
        cjkFallback: AppFontChoice.pingFangTw,
        customPrimaryFamily: 'My Latin',
        customCjkFamily: 'My CJK',
      );

      expect(style.fontFamily, 'Futura');
      expect(style.fontFamilyFallback, isNotNull);
      expect(style.fontFamilyFallback!.first, 'PingFang TC');
      expect(style.fontFamilyFallback!.length, greaterThan(1));
    });

    test('custom font choices use explicit custom font families', () {
      final style = AppFontChoice.custom.applyTextStyle(
        const TextStyle(fontSize: 16),
        cjkFallback: AppFontChoice.customCjk,
        customPrimaryFamily: 'My Latin',
        customCjkFamily: 'My CJK',
      );

      expect(style.fontFamily, 'My Latin');
      expect(style.fontFamilyFallback, isNotNull);
      expect(style.fontFamilyFallback!.first, 'My CJK');
      expect(style.fontFamilyFallback!.length, greaterThan(1));
    });

    test('monospace font choices render code with selected family', () {
      final style = AppMonospaceFontChoice.custom.applyTextStyle(
        const TextStyle(fontSize: 13),
        customFamily: 'My Mono',
      );

      expect(style.fontFamily, 'My Mono');
      expect(style.fontFamilyFallback, isNot(contains('My Mono')));
      expect(style.fontFamilyFallback!.length, greaterThan(1));
    });

    test(
      'code font fallback prioritizes mono, emoji, then normal text',
      () async {
        SharedPreferences.setMockInitialValues({
          'monospaceFontChoice': 'custom',
          'customMonospaceFontFamily': 'My Mono',
          'fontFallbackChain': ['My Normal', 'Normal Fallback'],
        });
        final prefs = await SharedPreferences.getInstance();
        final theme = ThemeController(prefs);
        addTearDown(theme.dispose);

        final style = theme.codeTextStyle(
          const TextStyle(fontFamilyFallback: ['Wrong Normal']),
        );
        final fallbacks = style.fontFamilyFallback!;
        final emojiIndex = fallbacks.indexOf(
          theme.emojiFontChoice.fontFamilies.first,
        );
        final normalIndex = fallbacks.indexOf('My Normal');

        expect(style.fontFamily, 'My Mono');
        expect(emojiIndex, greaterThanOrEqualTo(0));
        expect(normalIndex, greaterThan(emojiIndex));
        expect(fallbacks, isNot(contains('Wrong Normal')));
      },
    );
  });

  group('EmojiFontChoice', () {
    test('uses platform fallback until a runtime font is loaded', () {
      expect(EmojiFontChoice.system.fontFamilies, isNotEmpty);
      const choice = EmojiFontChoice(
        key: 'twemoji',
        label: 'Twemoji',
        fontFamily: 'MithkaEmoji_twemoji',
      );
      expect(choice.fontFamilies.first, 'MithkaEmoji_twemoji');
    });

    test('parses release manifest entries and chooses a downloadable format', () {
      final entry = EmojiFontManifestEntry.fromJson({
        'key': 'twemoji',
        'label': 'Twemoji',
        'license': 'CC-BY-4.0',
        'kind': 'color',
        'coverage_pct': 99,
        'emoji_version': '15.0',
        'updated': '2026-06-16',
        'formats': {
          'sbix':
              'https://github.com/iebb/emojifonts/releases/download/latest/twemoji.ttf',
        },
      });

      expect(entry.key, 'twemoji');
      expect(entry.runtimeFamily, 'MithkaEmoji_twemoji');
      expect(entry.format, 'sbix');
      expect(entry.emojiVersion, '15.0');
      expect(entry.extension, 'ttf');
    });
  });

  group('TranslationController', () {
    test('defaults off and persists target/provider preferences', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = TranslationController(prefs);

      expect(controller.enabled, isFalse);
      expect(controller.provider, TranslationProvider.tdlib);
      expect(controller.targetLanguageCode, 'zh-Hans');
      expect(
        controller.lingvaEndpoint,
        TranslationController.defaultLingvaEndpoint,
      );
      expect(controller.libreTranslateEndpoint, isEmpty);
      expect(controller.libreTranslateApiKey, isEmpty);

      controller.enabled = true;
      controller.provider = TranslationProvider.lingva;
      controller.targetLanguageCode = 'ja';
      controller.lingvaEndpoint = 'https://lingva.example.com/';
      controller.libreTranslateEndpoint = ' https://libre.example.com// ';
      controller.libreTranslateApiKey = ' secret-key ';

      final reloaded = TranslationController(prefs);
      expect(reloaded.enabled, isTrue);
      expect(reloaded.provider, TranslationProvider.lingva);
      expect(reloaded.targetLanguageCode, 'ja');
      expect(reloaded.lingvaEndpoint, 'https://lingva.example.com');
      expect(reloaded.libreTranslateEndpoint, 'https://libre.example.com');
      expect(reloaded.libreTranslateApiKey, 'secret-key');
    });

    test(
      'loads stored provider and falls back to Telegram for unavailable values',
      () async {
        SharedPreferences.setMockInitialValues({
          'translation.provider': 'tdlib',
        });
        final prefs = await SharedPreferences.getInstance();
        final controller = TranslationController(prefs);

        expect(controller.provider, TranslationProvider.tdlib);
        controller.provider = TranslationProvider.myMemory;
        expect(controller.provider, TranslationProvider.myMemory);

        SharedPreferences.setMockInitialValues({
          'translation.provider': 'not_a_provider',
        });
        final fallbackPrefs = await SharedPreferences.getInstance();
        final fallback = TranslationController(fallbackPrefs);
        expect(fallback.provider, TranslationProvider.tdlib);

        SharedPreferences.setMockInitialValues({
          'translation.provider': 'native_on_device',
        });
        final nativePrefs = await SharedPreferences.getInstance();
        final nativeFallback = TranslationController(nativePrefs);
        expect(nativeFallback.provider, TranslationProvider.tdlib);
      },
    );
  });

  group('AppLocaleController', () {
    tearDown(() {
      Intl.defaultLocale = null;
    });

    test('AppStrings follows script and regional locale tags', () {
      Intl.defaultLocale = 'zh_Hans';
      expect(AppStrings.t(AppStringKeys.apiCredentialsTitle), '自定义 API 凭据');

      Intl.defaultLocale = 'zh-Hant';
      expect(
        AppLocalizations.localeKeyFor(
          AppLocalizations.resolve(
            AppLocalizations.localeFromTag(Intl.getCurrentLocale())!,
          ),
        ),
        'zhHant',
      );

      Intl.defaultLocale = 'zh_HK';
      expect(
        AppLocalizations.localeKeyFor(
          AppLocalizations.resolve(
            AppLocalizations.localeFromTag(Intl.getCurrentLocale())!,
          ),
        ),
        'zhHant',
      );

      Intl.defaultLocale = 'en_US';
      expect(
        AppLocalizations.localeKeyFor(
          AppLocalizations.resolve(
            AppLocalizations.localeFromTag(Intl.getCurrentLocale())!,
          ),
        ),
        'en',
      );
    });

    test('non-Chinese locales do not surface Chinese fallback strings', () {
      final source = File('lib/l10n/app_localizations.dart').readAsStringSync();
      final keys = RegExp(
        r"static const [A-Za-z0-9_]+ = '([^']+)';",
      ).allMatches(source).map((match) => match.group(1)!).toSet();
      final zhValues = <String, String>{};
      final zhBlock = File('lib/l10n/messages/zh_hans.dart').readAsStringSync();
      for (final match in RegExp(
        r''' '([^']+)':\s*"((?:\\.|[^"])*)" '''.trim(),
        dotAll: true,
      ).allMatches(zhBlock)) {
        zhValues[match.group(1)!] = match.group(2)!;
      }
      final intentionalHan = RegExp(r'^(appLocale|country|markdown|theme)');
      final han = RegExp(r'[\u3400-\u9fff]');
      final failures = <String>[];
      for (final localeKey in ['en', 'ko', 'fr', 'es', 'de']) {
        for (final key in keys) {
          if (intentionalHan.hasMatch(key)) continue;
          final value = AppStrings.tForLocale(localeKey, key);
          if (han.hasMatch(value)) failures.add('$localeKey.$key=$value');
        }
      }
      final jaSameAsChinese = <String>[];
      for (final key in keys) {
        if (intentionalHan.hasMatch(key)) continue;
        final value = AppStrings.tForLocale('ja', key);
        final zhValue = zhValues[key];
        if (zhValue != null && value == zhValue && han.hasMatch(value)) {
          jaSameAsChinese.add('ja.$key=$value');
        }
      }
      if (jaSameAsChinese.length > 80) {
        failures.add(
          'ja appears to be using Chinese fallback for '
          '${jaSameAsChinese.length} keys: ${jaSameAsChinese.take(5).join(', ')}',
        );
      }
      expect(failures, isEmpty);
    });

    test('country names resolve from the split country map', () {
      expect(AppStrings.tForLocale('en', AppStringKeys.countryJP), 'Japan');
      expect(AppStrings.tForLocale('ja', AppStringKeys.countryJP), '日本');
      expect(AppStrings.tForLocale('ko', AppStringKeys.countryKR), '대한민국');
      expect(AppStrings.tForLocale('zhHant', AppStringKeys.countryTW), '中國台灣');
    });

    test('defaults to system and persists explicit locale choices', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppLocaleController(prefs);

      expect(controller.followsSystem, isTrue);
      expect(controller.locale, isNull);

      controller.locale = const Locale('ja');
      expect(controller.followsSystem, isFalse);
      expect(controller.locale, const Locale('ja'));

      final reloaded = AppLocaleController(prefs);
      expect(reloaded.locale, const Locale('ja'));

      reloaded.locale = null;
      expect(reloaded.followsSystem, isTrue);

      final systemAgain = AppLocaleController(prefs);
      expect(systemAgain.locale, isNull);
    });

    testWidgets('rebuilds localized text when language changes', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final controller = AppLocaleController(prefs)
        ..locale = const Locale.fromSubtags(
          languageCode: 'zh',
          scriptCode: 'Hans',
        );

      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: controller,
          child: Consumer<AppLocaleController>(
            builder: (context, locale, _) {
              return MaterialApp(
                locale: locale.locale,
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                ],
                home: Builder(
                  builder: (context) => Text(
                    AppStringKeys.tabMessages.l10n(context),
                    textDirection: ui.TextDirection.ltr,
                  ),
                ),
              );
            },
          ),
        ),
      );
      expect(find.text('消息'), findsOneWidget);

      controller.locale = const Locale('en');
      await tester.pumpAndSettle();
      expect(find.text('Messages'), findsOneWidget);
      expect(find.text('消息'), findsNothing);
    });
  });
}
