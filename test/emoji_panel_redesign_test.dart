//
//  emoji_panel_redesign_test.dart
//
//  Covers the iOS-style standard emoji pane: recents persistence + ordering +
//  cap, custom-emoji recents gated on Premium, the scroll-following category
//  strip (tap to jump, scroll to highlight), adaptive column count, and the
//  long-press preview.
//

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_input_bar.dart';
import 'package:mithka/chat/chat_view_model.dart';
import 'package:mithka/chat/emoji_catalog.dart';
import 'package:mithka/chat/emoji_panel.dart';
import 'package:mithka/chat/emoji_panel_layout.dart';
import 'package:mithka/chat/emoji_recents_store.dart';
import 'package:mithka/chat/emoji_store.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> _pumpPane(
  WidgetTester tester, {
  List<String> inserted = const [],
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
      home: Scaffold(
        body: SizedBox(
          height: 320,
          child: StandardEmojiPane(
            insertText: inserted.add,
            insertCustomEmoji: (_, _) {},
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// The strip section whose button is marked selected, or -1 if none is.
int _selectedStripSection(WidgetTester tester) {
  for (var section = 0; section <= EmojiCatalog.categories.length; section++) {
    final button = find.byKey(ValueKey('emojiCategoryStrip-$section'));
    if (button.evaluate().isEmpty) continue;
    final semantics = tester.widget<Semantics>(
      find.ancestor(of: button, matching: find.byType(Semantics)).first,
    );
    if (semantics.properties.selected == true) return section;
  }
  return -1;
}

void main() {
  // The catalogue loads through rootBundle, real async I/O that would never
  // complete inside testWidgets' fake clock; load it once here instead.
  setUpAll(() async {
    await AppStrings.ensureLoaded(const Locale('en'));
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    EmojiRecentsStore.shared.resetForTesting();
    EmojiStore.shared.reset();
  });
  tearDown(() {
    EmojiRecentsStore.shared.resetForTesting();
    EmojiStore.shared.reset();
  });

  group('EmojiRecentsStore', () {
    test('records standard emoji most-recent-first', () {
      final store = EmojiRecentsStore.shared;
      store.record('😀');
      store.record('😎');
      store.record('🍕');
      expect(store.entries.map((e) => e.emoji).toList(), ['🍕', '😎', '😀']);
    });

    test('frequency weighting outranks pure recency', () {
      final store = EmojiRecentsStore.shared;
      // 😀 picked three times, then one burst of two others.
      store.record('😀');
      store.record('😀');
      store.record('😀');
      store.record('🍕');
      store.record('😎');
      final ranked = store.entries;
      expect(ranked.first.emoji, '😀');
      expect(ranked.first.count, 3);
      // 🍕 and 😎 have equal count (1) so recency breaks the tie.
      expect(ranked[1].emoji, '😎');
      expect(ranked[2].emoji, '🍕');
    });

    test('re-inserting an existing emoji does not duplicate it', () {
      final store = EmojiRecentsStore.shared;
      store.record('😀');
      store.record('😎');
      store.record('😀');
      expect(store.entries.length, 2);
      expect(store.entries.where((e) => e.emoji == '😀').length, 1);
      expect(store.entries.first.emoji, '😀');
      expect(store.entries.first.count, 2);
    });

    test('caps the list at maxEntries and drops the lowest-ranked', () {
      final store = EmojiRecentsStore.shared;
      for (var i = 0; i < EmojiRecentsStore.maxEntries + 20; i++) {
        store.record('E$i');
      }
      expect(store.entries.length, EmojiRecentsStore.maxEntries);
      // The most recent insert survives; the oldest falls off.
      expect(
        store.entries.first.emoji,
        'E${EmojiRecentsStore.maxEntries + 19}',
      );
      expect(store.entries.any((e) => e.emoji == 'E0'), isFalse);
    });

    test('records custom emoji only for Premium accounts', () {
      final store = EmojiRecentsStore.shared;
      EmojiStore.shared.isPremium = false;
      store.recordCustom(123, '😀');
      expect(store.entries, isEmpty);

      EmojiStore.shared.isPremium = true;
      store.recordCustom(123, '😀');
      expect(store.entries.length, 1);
      expect(store.entries.single.customEmojiId, 123);
      expect(store.entries.single.isCustom, isTrue);
    });

    test('non-Premium renderable list hides custom emoji', () {
      final store = EmojiRecentsStore.shared;
      EmojiStore.shared.isPremium = true;
      store.recordCustom(7, '😀');
      store.record('😎');
      expect(store.entries.length, 2);
      EmojiStore.shared.isPremium = false;
      expect(store.renderableEntries.length, 1);
      expect(store.renderableEntries.single.emoji, '😎');
    });

    test('persists across reloads and round-trips through JSON', () async {
      EmojiRecentsStore.shared.record('😀');
      EmojiRecentsStore.shared.record('😎');
      // The store persists asynchronously; let the write land.
      await Future<void>.delayed(Duration.zero);

      EmojiRecentsStore.shared.resetForTesting();
      expect(EmojiRecentsStore.shared.entries, isEmpty);
      await EmojiRecentsStore.shared.loadIfNeeded();
      expect(EmojiRecentsStore.shared.entries.map((e) => e.emoji).toList(), [
        '😎',
        '😀',
      ]);
    });

    test('decodeEntries ignores malformed and duplicate records', () {
      final encoded = encodeEntries([
        const EmojiRecentEntry(emoji: '😀', count: 2, lastUsed: 5),
        const EmojiRecentEntry(emoji: '😀', lastUsed: 9),
        const EmojiRecentEntry(emoji: '😎', lastUsed: 1),
      ]);
      final decoded = decodeEntries(encoded);
      expect(decoded.length, 2);
      expect(decoded.first.emoji, '😀');
      expect(decodeEntries('not json'), isEmpty);
      expect(decodeEntries(null), isEmpty);
      expect(decodeEntries(''), isEmpty);
    });

    test('clear empties the list', () {
      final store = EmojiRecentsStore.shared;
      store.record('😀');
      expect(store.entries, isNotEmpty);
      store.clear();
      expect(store.entries, isEmpty);
    });
  });

  group('emojiPanelColumnCount', () {
    test(
      'phones stay at eight columns, wide surfaces add columns not stretch',
      () {
        expect(emojiPanelColumnCount(360), 8); // 360 / 44 = 8.18 → 8
        expect(emojiPanelColumnCount(390), 8);
        expect(emojiPanelColumnCount(300), 6); // clamps to the minimum
        expect(emojiPanelColumnCount(0), emojiPanelMinColumns);
        expect(emojiPanelColumnCount(-5), emojiPanelMinColumns);
        expect(
          emojiPanelColumnCount(1200),
          emojiPanelMaxColumns,
        ); // clamps to the maximum
      },
    );
  });

  group('StandardEmojiPane', () {
    testWidgets('shows no recents section when empty', (tester) async {
      await _pumpPane(tester);
      expect(find.text('Recently Used'), findsNothing);
      expect(find.byKey(const ValueKey('emojiCategoryStrip')), findsOneWidget);
      // Every catalog category header still renders its first row.
      expect(
        find.text(
          EmojiCatalog.categories.first.name.l10n(
            tester.element(find.byType(StandardEmojiPane)),
          ),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('inserting an emoji surfaces a recents section', (
      tester,
    ) async {
      final inserted = <String>[];
      await _pumpPane(tester, inserted: inserted);
      expect(find.text('Recently Used'), findsNothing);

      // Tap the first smiley in the catalog grid.
      final firstEmoji = EmojiCatalog.categories.first.emojis.first;
      await tester.tap(find.text(firstEmoji).first);
      await tester.pumpAndSettle();

      expect(inserted, [firstEmoji]);
      expect(find.text('Recently Used'), findsOneWidget);
      // The recents section renders the emoji it just recorded.
      expect(find.byKey(ValueKey('emojiRecent-$firstEmoji')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('recents persist across a widget rebuild', (tester) async {
      EmojiRecentsStore.shared.record('😀');
      EmojiRecentsStore.shared.record('😎');

      final inserted = <String>[];
      await _pumpPane(tester, inserted: inserted);
      expect(find.byKey(const ValueKey('emojiRecent-😎')), findsOneWidget);

      // Rebuild the whole widget; the store keeps the recents.
      await _pumpPane(tester, inserted: inserted);
      expect(find.byKey(const ValueKey('emojiRecent-😎')), findsOneWidget);
      expect(find.byKey(const ValueKey('emojiRecent-😀')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('category strip has one button per section plus recents', (
      tester,
    ) async {
      EmojiRecentsStore.shared.record('😀');
      await _pumpPane(tester);
      final expected = EmojiCatalog.categories.length + 1; // + recents
      for (var section = 0; section < expected; section++) {
        expect(
          find.byKey(ValueKey('emojiCategoryStrip-$section')),
          findsOneWidget,
          reason: 'section $section button missing',
        );
      }
      expect(
        find.byKey(ValueKey('emojiCategoryStrip-$expected')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('tapping a category scrolls the grid to that section', (
      tester,
    ) async {
      await _pumpPane(tester);
      final grid = find.byKey(const ValueKey('emojiStandardGrid'));
      final scrollable = find.descendant(
        of: grid,
        matching: find.byType(Scrollable),
      );
      final state = tester.state<ScrollableState>(scrollable);
      expect(state.position.pixels, 0);

      // Tap the last category's strip button and settle the animation.
      final lastSection = EmojiCatalog.categories.length - 1;
      await tester.tap(find.byKey(ValueKey('emojiCategoryStrip-$lastSection')));
      await tester.pumpAndSettle();

      expect(
        state.position.pixels,
        greaterThan(0),
        reason: 'the grid should have scrolled to the tapped section',
      );
      // The tapped section's header box now sits at the top of the viewport.
      final headerTop = tester
          .getTopLeft(find.byKey(ValueKey('emojiSectionHeader-$lastSection')))
          .dy;
      final viewportTop = tester.getTopLeft(grid).dy;
      expect((headerTop - viewportTop).abs(), lessThan(1));
      expect(tester.takeException(), isNull);
    });

    testWidgets('scrolling the grid moves the highlighted category', (
      tester,
    ) async {
      await _pumpPane(tester);
      final grid = find.byKey(const ValueKey('emojiStandardGrid'));
      final state = tester.state<ScrollableState>(
        find.descendant(of: grid, matching: find.byType(Scrollable)),
      );
      expect(state.position.pixels, 0);

      // Drag the grid itself (no strip tap) well past the first categories;
      // the strip must follow the scroll position, not a user action.
      await tester.drag(grid, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(state.position.pixels, greaterThan(600));

      // Some later category is now highlighted rather than the first section.
      expect(_selectedStripSection(tester), greaterThan(0));
      expect(tester.takeException(), isNull);
    });

    testWidgets('long-press raises a preview and inserts on release', (
      tester,
    ) async {
      final inserted = <String>[];
      await _pumpPane(tester, inserted: inserted);
      final firstEmoji = EmojiCatalog.categories.first.emojis.first;
      final target = find.text(firstEmoji).first;

      final gesture = await tester.startGesture(tester.getCenter(target));
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        find.byKey(const ValueKey('emojiLongPressPreview')),
        findsOneWidget,
      );
      // The preview shows the enlarged glyph.
      expect(find.text(firstEmoji), findsWidgets);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emojiLongPressPreview')), findsNothing);
      // Releasing a long-press inserts exactly once, like iOS.
      expect(inserted, [firstEmoji]);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a plain tap inserts without raising a preview', (
      tester,
    ) async {
      final inserted = <String>[];
      await _pumpPane(tester, inserted: inserted);
      final firstEmoji = EmojiCatalog.categories.first.emojis.first;
      await tester.tap(find.text(firstEmoji).first);
      await tester.pumpAndSettle();
      expect(inserted, [firstEmoji]);
      expect(find.byKey(const ValueKey('emojiLongPressPreview')), findsNothing);
      expect(tester.takeException(), isNull);
    });

    testWidgets('custom recents render for a Premium account', (tester) async {
      EmojiStore.shared.isPremium = true;
      EmojiRecentsStore.shared.recordCustom(42, '😀');
      await _pumpPane(tester);
      expect(
        find.byKey(const ValueKey('emojiRecentCustom-42')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('ChatInputBar integration', () {
    testWidgets('opening the emoji panel and tapping records a recent', (
      tester,
    ) async {
      final vm = _IntegrationViewModel();
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

      // Open the emoji panel via the composer's smiley icon.
      await tester.tap(find.byIcon(HeroAppIcons.solidFaceSmile.data).first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('emojiPanelTabs')), findsOneWidget);
      // The redesigned pane renders its category strip.
      expect(find.byKey(const ValueKey('emojiCategoryStrip')), findsOneWidget);

      // Tap a catalog emoji; it lands in the composer and becomes a recent.
      final firstEmoji = EmojiCatalog.categories.first.emojis.first;
      await tester.tap(find.text(firstEmoji).first);
      await tester.pumpAndSettle();
      expect(
        EmojiRecentsStore.shared.entries.map((e) => e.emoji),
        contains(firstEmoji),
      );
      // The panel stays open after inserting (preserved composer behavior).
      expect(find.byKey(const ValueKey('emojiPanelTabs')), findsOneWidget);
      // Drain the view model's 750ms draft-save debounce started by the
      // insert so no timer is pending at teardown.
      await tester.pump(const Duration(milliseconds: 800));
      expect(tester.takeException(), isNull);
    });
  });
}

/// Minimal composer view model: no TDLib, no drafts, just a text sink.
class _IntegrationViewModel extends ChatViewModel {
  _IntegrationViewModel()
    : super(chatId: 1, title: 'Test', markReadOnOpen: false);

  @override
  void sendTyping() {}

  @override
  Future<bool> currentUserIsPremium() async => false;

  @override
  Future<void> persistComposerDraft() async {}
}
