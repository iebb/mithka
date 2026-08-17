import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:heroicons_flutter/heroicons_flutter.dart';
import 'package:mithka/chat/message_action_menu.dart';
import 'package:mithka/chat/message_reaction_availability.dart';
import 'package:mithka/chat/quick_reaction_choice.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/translation_controller.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('message action rows stay balanced', () {
    expect(MessageActionMenu.rowCountsForActionCount(6), (first: 3, second: 3));
    expect(MessageActionMenu.rowCountsForActionCount(7), (first: 4, second: 3));
    expect(MessageActionMenu.rowCountsForActionCount(8), (first: 4, second: 4));
    expect(MessageActionMenu.rowCountsForActionCount(9), (first: 5, second: 4));

    for (var count = 6; count <= 24; count++) {
      final rows = MessageActionMenu.rowCountsForActionCount(count);
      expect(rows.first - rows.second, inInclusiveRange(0, 1));
    }
  });

  test('mobile action menu uses content width through a two-by-five grid', () {
    expect(MessageActionMenu.widthForAvailable(400), 332);
    expect(MessageActionMenu.widthForAvailable(300), 300);
    expect(MessageActionMenu.mobileWidthForActionCount(4, 400), 244);
    expect(MessageActionMenu.mobileWidthForActionCount(3, 400), 186);
    expect(MessageActionMenu.mobileWidthForActionCount(5, 400), 302);
    expect(MessageActionMenu.mobileWidthForActionCount(6, 400), 186);
    expect(MessageActionMenu.mobileWidthForActionCount(8, 400), 244);
    expect(MessageActionMenu.mobileWidthForActionCount(9, 400), 302);
    expect(MessageActionMenu.mobileWidthForActionCount(10, 400), 302);
    expect(MessageActionMenu.mobileWidthForActionCount(11, 400), 332);
    expect(MessageActionMenu.mobileWidthForActionCount(10, 280), 280);
  });

  test('grid labels stay within eight characters in every locale', () async {
    for (final locale in AppLocalizations.supportedLocales) {
      await AppStrings.ensureLoaded(locale);
      final localeKey = AppLocalizations.localeKeyFor(locale);
      for (final action in MessageAction.values) {
        final fullLabel = AppStrings.tForLocale(localeKey, action.label);
        final gridLabel = MessageActionMenu.gridLabel(fullLabel);
        expect(
          gridLabel.runes.length,
          lessThanOrEqualTo(MessageActionMenu.maxGridLabelCharacters),
          reason: '${locale.toLanguageTag()} ${action.name}: $gridLabel',
        );
      }
    }
    expect(MessageActionMenu.gridLabel('Select multiple'), 'Select…');
  });

  test('forward has a dedicated curved-right glyph', () {
    expect(MessageAction.forward.glyph, same(HeroAppIcons.forward));
    expect(HeroAppIcons.forward.data, HeroiconsOutline.arrowUturnRight);
    expect(HeroAppIcons.forward.data, isNot(HeroAppIcons.share.data));
  });

  test('desktop context menu starts at pointer and stays on screen', () {
    expect(
      MessageActionMenu.desktopOriginForPointer(
        pointer: const Offset(180, 120),
        viewport: const Size(640, 420),
        menuSize: const Size(220, 240),
        topSafe: 8,
        bottomSafe: 412,
      ),
      const Offset(180, 120),
    );
    expect(
      MessageActionMenu.desktopOriginForPointer(
        pointer: const Offset(630, 410),
        viewport: const Size(640, 420),
        menuSize: const Size(220, 240),
        topSafe: 8,
        bottomSafe: 412,
      ),
      const Offset(410, 172),
    );
  });

  test('desktop context menu converts a global pointer to its overlay', () {
    final localRect = MessageActionMenu.rectInOverlay(
      const Rect.fromLTWH(460, 180, 0, 0),
      globalToLocal: (point) => point - const Offset(320, 40),
    );

    expect(localRect, const Rect.fromLTWH(140, 140, 0, 0));
    expect(
      MessageActionMenu.desktopOriginForPointer(
        pointer: localRect.topLeft,
        viewport: const Size(720, 520),
        menuSize: const Size(220, 240),
        topSafe: 8,
        bottomSafe: 512,
      ),
      const Offset(140, 140),
    );
  });

  test('mobile dropdown replaces message bounds with the press position', () {
    const target = Rect.fromLTWH(20, 40, 180, 64);
    const pointer = Offset(140, 186);

    expect(
      MessageActionMenu.anchorRectForPresentation(
        targetRect: target,
        pointer: pointer,
        usePointer: true,
      ),
      const Rect.fromLTWH(140, 186, 0, 0),
    );
    expect(
      MessageActionMenu.anchorRectForPresentation(
        targetRect: target,
        pointer: pointer,
        usePointer: false,
      ),
      target,
    );
  });

  testWidgets('ten or fewer reaction controls fit without overflow', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: QuickReactionBar(
            reactions: defaultQuickReactions,
            onReaction: (_) {},
            onExpand: () {},
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(
      tester.getSize(find.byKey(const ValueKey('quick-reaction-bar'))).width,
      MessageActionMenu.preferredWidth,
    );
    expect(find.byKey(const ValueKey('quick-reaction-expand')), findsOneWidget);
  });

  testWidgets('quick bar renders only reactions allowed for the message', (
    tester,
  ) async {
    final availability = MessageReactionAvailability.fromTd({
      '@type': 'availableReactions',
      'top_reactions': [
        {
          '@type': 'availableReaction',
          'type': {'@type': 'reactionTypeEmoji', 'emoji': '👍'},
          'needs_premium': false,
        },
      ],
      'recent_reactions': <Map<String, dynamic>>[],
      'popular_reactions': <Map<String, dynamic>>[],
      'allow_custom_emoji': false,
      'are_tags': false,
      'unavailability_reason': null,
    }, isPremium: false);

    await tester.pumpWidget(
      MaterialApp(
        home: QuickReactionBar(
          reactions: availability.quickChoices(defaultQuickReactions),
          onReaction: (_) {},
          onExpand: () {},
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('quick-reaction-emoji:👍')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('quick-reaction-emoji:❤️')), findsNothing);
    expect(find.byKey(const ValueKey('quick-reaction-expand')), findsOneWidget);
  });

  test(
    'quick reactions persist order, custom emoji, and the nine-item cap',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      const custom = QuickReactionChoice.custom(123456789);
      theme.setQuickReactions([
        custom,
        ...availableStandardReactions.map(QuickReactionChoice.emoji),
      ]);

      final restored = ThemeController(prefs).quickReactions;
      expect(restored, hasLength(9));
      expect(restored.first, custom);
      expect(restored[1], const QuickReactionChoice.emoji('👍'));
    },
  );

  test(
    'mobile message action menu style defaults to grid and persists',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      expect(
        theme.mobileMessageActionMenuStyle,
        MobileMessageActionMenuStyle.grid,
      );

      theme.mobileMessageActionMenuStyle =
          MobileMessageActionMenuStyle.dropdown;
      expect(
        ThemeController(prefs).mobileMessageActionMenuStyle,
        MobileMessageActionMenuStyle.dropdown,
      );
    },
  );

  test('custom quick reactions are available only to Premium accounts', () {
    const custom = QuickReactionChoice.custom(987654321);
    const standard = QuickReactionChoice.emoji('👍');

    expect(
      effectiveQuickReactions(const [custom, standard], allowCustomEmoji: true),
      const [custom, standard],
    );
    expect(
      effectiveQuickReactions(const [
        custom,
        standard,
      ], allowCustomEmoji: false),
      const [standard],
    );
    expect(
      effectiveQuickReactions(const [custom], allowCustomEmoji: false),
      defaultQuickReactions,
    );
  });

  test('+1 preserves sender by default and persists the override', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    expect(theme.preserveSenderWhenRepeating, isTrue);

    theme.preserveSenderWhenRepeating = false;
    expect(ThemeController(prefs).preserveSenderWhenRepeating, isFalse);
  });

  test('quick replies default on and persist the global opt-out', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    expect(theme.quickRepliesEnabled, isTrue);

    theme.quickRepliesEnabled = false;
    expect(ThemeController(prefs).quickRepliesEnabled, isFalse);
  });

  testWidgets('message menu renders +1 at its action content width', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs);
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: translation,
        child: MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: MessageActionMenu(
                message: ChatMessage(
                  id: 1,
                  isOutgoing: false,
                  text: 'message',
                  date: 1,
                  contentType: 'messageText',
                ),
                isPinned: false,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.text('+1'), findsOneWidget);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('message-action-menu-surface')))
          .width,
      244,
    );
  });

  testWidgets('desktop message actions render as a compact vertical list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs);
    await tester.binding.setSurfaceSize(const Size(500, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: translation,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.macOS),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: MessageActionMenu(
                message: ChatMessage(
                  id: 18,
                  isOutgoing: false,
                  text: 'desktop menu',
                  date: 1,
                  contentType: 'messageText',
                ),
                isPinned: false,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    final surface = find.byKey(const ValueKey('message-action-menu-surface'));
    expect(
      tester.getSize(surface).width,
      MessageActionMenu.desktopPreferredWidth,
    );
    final copy = tester.getTopLeft(
      find.byKey(const ValueKey('message-action-copy')),
    );
    final reply = tester.getTopLeft(
      find.byKey(const ValueKey('message-action-reply')),
    );
    final forward = tester.getTopLeft(
      find.byKey(const ValueKey('message-action-forward')),
    );
    expect(reply.dx, copy.dx);
    expect(forward.dx, copy.dx);
    expect(reply.dy, greaterThan(copy.dy));
    expect(forward.dy, greaterThan(reply.dy));
  });

  testWidgets('mobile dropdown reuses the compact vertical action list', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs);
    await tester.binding.setSurfaceSize(const Size(400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: translation,
        child: MaterialApp(
          theme: ThemeData(platform: TargetPlatform.iOS),
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: MessageActionMenu(
                message: ChatMessage(
                  id: 19,
                  isOutgoing: false,
                  text: 'mobile dropdown',
                  date: 1,
                  contentType: 'messageText',
                  commentCount: 2,
                ),
                isPinned: false,
                layout: MessageActionMenuLayout.vertical,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('message-action-menu-vertical-list')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('message-action-menu-surface')))
          .width,
      MessageActionMenu.desktopPreferredWidth,
    );
    expect(find.text('View replies'), findsOneWidget);
  });

  testWidgets('captionless outgoing media still exposes edit', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: translation,
        child: MaterialApp(
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageActionMenu(
              message: ChatMessage(
                id: 2,
                isOutgoing: true,
                text: '',
                date: 1,
                contentType: 'messagePhoto',
              ),
              isPinned: false,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Edit'), findsOneWidget);
  });

  testWidgets('message menu names reply actions and omits info', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: translation,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageActionMenu(
              message: ChatMessage(
                id: 4,
                isOutgoing: false,
                text: 'message with replies',
                date: 1,
                contentType: 'messageText',
                commentCount: 2,
              ),
              isPinned: false,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.text('Reply'), findsOneWidget);
    expect(
      find.text(MessageActionMenu.gridLabel('View replies')),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('View replies'), findsOneWidget);
    expect(find.byKey(const ValueKey('message-action-info')), findsNothing);
  });

  testWidgets('protected chats omit every forwarding-based action', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: translation,
        child: MaterialApp(
          home: Scaffold(
            body: MessageActionMenu(
              message: ChatMessage(
                id: 3,
                isOutgoing: false,
                text: 'protected track',
                date: 1,
                contentType: 'messageAudio',
                music: MessageMusic(
                  title: 'Track',
                  duration: 10,
                  file: TdFileRef(id: 7),
                ),
              ),
              isPinned: false,
              allowForwarding: false,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('message-action-forward')), findsNothing);
    expect(find.byKey(const ValueKey('message-action-repeat')), findsNothing);
    expect(find.byKey(const ValueKey('message-action-save')), findsNothing);
    expect(
      find.byKey(const ValueKey('message-action-addToPlaylist')),
      findsNothing,
    );
  });

  testWidgets('translated-only messages expose the original toggle', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs)
      ..displayStyle = TranslationDisplayStyle.translatedOnly;
    MessageAction? selected;
    final message = ChatMessage(
      id: 5,
      isOutgoing: false,
      text: 'Original',
      date: 1,
      contentType: 'messageText',
      translationText: 'Translated',
      translationLanguageCode: 'en',
    );

    Future<void> pump({required bool showingOriginal}) => tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: translation,
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: MessageActionMenu(
              message: message,
              isPinned: false,
              showingOriginalTranslation: showingOriginal,
              onSelect: (action) => selected = action,
            ),
          ),
        ),
      ),
    );

    await pump(showingOriginal: false);
    expect(find.bySemanticsLabel('Display original'), findsOneWidget);
    await tester.tap(
      find.byKey(const ValueKey('message-action-displayOriginal')),
    );
    expect(selected, MessageAction.displayOriginal);

    await pump(showingOriginal: true);
    expect(find.bySemanticsLabel('Display translation'), findsOneWidget);
    expect(find.bySemanticsLabel('Display original'), findsNothing);
  });

  testWidgets('translation action can be hidden when no provider is usable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'translation.enabled': true});
    final prefs = await SharedPreferences.getInstance();
    final translation = TranslationController(prefs);
    addTearDown(translation.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: translation,
        child: MaterialApp(
          home: Scaffold(
            body: MessageActionMenu(
              message: ChatMessage(
                id: 9,
                isOutgoing: false,
                text: 'Bot message',
                date: 1,
                contentType: 'messageText',
              ),
              isPinned: false,
              allowTranslation: false,
              onSelect: (_) {},
            ),
          ),
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('message-action-translate')),
      findsNothing,
    );
  });
}
