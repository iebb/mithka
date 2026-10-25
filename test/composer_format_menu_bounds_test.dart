import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/emoji_text_controller.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/content_size.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FormatMenuViewModel extends ChatViewModel {
  _FormatMenuViewModel()
    : super(chatId: 1, title: 'Format menu', markReadOnOpen: false);

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
  for (final scenario in [
    (
      name: 'short portrait with keyboard',
      size: const Size(320, 568),
      keyboard: 260.0,
      padding: const EdgeInsets.only(top: 24),
      scrolls: true,
    ),
    (
      name: 'landscape with keyboard and side safe areas',
      size: const Size(740, 360),
      keyboard: 150.0,
      padding: const EdgeInsets.symmetric(horizontal: 44),
      scrolls: true,
    ),
    (
      name: 'narrow usable viewport',
      size: const Size(320, 568),
      keyboard: 260.0,
      padding: const EdgeInsets.fromLTRB(44, 24, 44, 0),
      scrolls: true,
    ),
    (
      name: 'normal viewport',
      size: const Size(420, 900),
      keyboard: 0.0,
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 34),
      scrolls: false,
    ),
  ]) {
    testWidgets('format menu fits ${scenario.name} and applies last action', (
      tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = scenario.size;
      addTearDown(tester.view.resetDevicePixelRatio);
      addTearDown(tester.view.resetPhysicalSize);
      final vm = _FormatMenuViewModel();
      addTearDown(vm.dispose);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final themeController = ThemeController(prefs);
      addTearDown(themeController.dispose);
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => ChangeNotifierProvider.value(
            value: themeController,
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(
                padding: scenario.padding,
                viewInsets: EdgeInsets.only(bottom: scenario.keyboard),
              ),
              child: child!,
            ),
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
      final fieldFinder = find.byType(TextField).first;
      await tester.enterText(fieldFinder, 'hello world');
      final field = tester.widget<TextField>(fieldFinder);
      final controller = field.controller! as EmojiTextEditingController;
      const selection = TextSelection(baseOffset: 0, extentOffset: 5);
      controller.selection = selection;
      await tester.pump();

      // Invoke the real selection toolbar's Format action, not the separate
      // docked formatting panel. This avoids platform toolbar overflow buttons
      // while exercising the production route and captured-selection callback.
      final editable = tester.state<EditableTextState>(
        find.byType(EditableText).first,
      );
      final toolbarScope =
          field.contextMenuBuilder!(tester.element(fieldFinder), editable)
              as MediaQuery;
      expect(
        toolbarScope.data.textScaler,
        ContentSizeScope.of(tester.element(fieldFinder)).systemTextScaler,
      );
      final toolbar = toolbarScope.child as AdaptiveTextSelectionToolbar;
      toolbar.buttonItems!
          .singleWhere(
            (item) => item.label == AppStrings.t(AppStringKeys.composerFormat),
          )
          .onPressed!();
      await tester.pumpAndSettle();

      final lastAction = find.text(
        AppStrings.t(AppStringKeys.composerFormatCodeBlock),
      );
      final scrollView = find.ancestor(
        of: lastAction,
        matching: find.byType(SingleChildScrollView),
      );
      expect(scrollView, findsOneWidget);
      final bounds = tester.getRect(scrollView);
      expect(bounds.left, greaterThanOrEqualTo(scenario.padding.left + 12));
      expect(
        bounds.right,
        lessThanOrEqualTo(scenario.size.width - scenario.padding.right - 12),
      );
      expect(bounds.top, greaterThanOrEqualTo(scenario.padding.top + 8));
      final bottomObstruction = scenario.keyboard > scenario.padding.bottom
          ? scenario.keyboard
          : scenario.padding.bottom;
      expect(
        bounds.bottom,
        lessThanOrEqualTo(scenario.size.height - bottomObstruction - 8),
      );
      expect(bounds.width, lessThanOrEqualTo(232));
      final scrollable = find.descendant(
        of: scrollView,
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(
        position.maxScrollExtent,
        scenario.scrolls ? greaterThan(0) : equals(0),
      );
      if (scenario.scrolls) {
        await tester.dragUntilVisible(
          lastAction,
          scrollView,
          const Offset(0, -80),
        );
        await tester.pumpAndSettle();
      }
      expect(lastAction.hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(lastAction);
      await tester.pumpAndSettle();

      expect(lastAction, findsNothing);
      expect(controller.selection, selection);
      final (text, entities) = controller.toFormatted();
      expect(text, 'hello world');
      expect(entities, [
        {
          '@type': 'textEntity',
          'offset': 0,
          'length': 5,
          'type': {'@type': 'textEntityTypePre'},
        },
      ]);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
