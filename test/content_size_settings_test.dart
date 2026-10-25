import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/settings/content_size_preview.dart';
import 'package:mithka/settings/content_size_settings_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/content_size.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'six stops and custom values retain precise labels and adjacent steps',
    () {
      expect(contentSizePresets, [.9, 1, 1.1, 1.2, 1.35, 1.6]);
      for (var i = 0; i < 6; i++) {
        expect(contentSizePresetIndex(contentSizePresets[i]), i);
        expect(
          contentSizeSemanticValue(contentSizePresets[i]),
          contains('step ${i + 1} of 6'),
        );
      }
      expect(contentSizeValue(1.2345), 'Custom · 123.45%');
      expect(contentSizeSemanticValue(1.2345), isNot(contains('step')));
      expect(adjacentContentSize(1.2345, increase: true), 1.35);
      expect(adjacentContentSize(1.2345, increase: false), 1.2);
      expect(adjacentContentSize(1.8, increase: true), isNull);
      expect(adjacentContentSize(1.8, increase: false), 1.6);
      // Custom values sit between their neighbouring stops; outliers rest on
      // the nearest end of the track.
      expect(contentSizeStopFraction(.9), 0);
      expect(contentSizeStopFraction(1), closeTo(.2, 1e-9));
      expect(contentSizeStopFraction(1.6), 1);
      expect(contentSizeStopFraction(.8), 0);
      expect(contentSizeStopFraction(2), 1);
      expect(
        contentSizeStopFraction(1.2345),
        closeTo((3 + .0345 / .15) / 5, 1e-9),
      );
    },
  );

  testWidgets('slider ends stay fixed-size; each A steps one stop', (
    tester,
  ) async {
    try {
      for (final scale in [1.0, 2.0]) {
        for (final direction in [TextDirection.ltr, TextDirection.rtl]) {
          final writes = <double>[];
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(extensions: [AppColors.light]),
              home: MediaQuery(
                data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                child: Directionality(
                  textDirection: direction,
                  child: Center(
                    child: SizedBox(
                      width: 280,
                      child: ContentSizeSlider(value: 1, onChanged: writes.add),
                    ),
                  ),
                ),
              ),
            ),
          );
          final down = find.byKey(const ValueKey('content-size-step-down'));
          final up = find.byKey(const ValueKey('content-size-step-up'));
          expect(tester.getSize(down), const Size(44, 44));
          expect(tester.getSize(up), const Size(44, 44));
          // The glyphs ignore the OS text size: 15 and 25 point at any scale.
          final small = tester.getSize(
            find.descendant(of: down, matching: find.text('A')),
          );
          final large = tester.getSize(
            find.descendant(of: up, matching: find.text('A')),
          );
          expect(small.height, closeTo(15, .01));
          expect(large.height, closeTo(25, .01));
          // The small A leads: left in LTR, right in RTL.
          final downIsLeft =
              tester.getCenter(down).dx < tester.getCenter(up).dx;
          expect(downIsLeft, direction == TextDirection.ltr);
          // Stops run from the small A toward the large A.
          final first = tester.getCenter(
            find.byKey(const ValueKey('content-size-stop-0')),
          );
          final last = tester.getCenter(
            find.byKey(const ValueKey('content-size-stop-5')),
          );
          expect(first.dx < last.dx, direction == TextDirection.ltr);
          await tester.tap(down);
          await tester.tap(up);
          expect(writes, [.9, 1.1]);
          expect(tester.takeException(), isNull);
        }
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('every stop change plays one selection haptic', (tester) async {
    final haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    var value = 1.0;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: Center(
            child: SizedBox(
              width: 344,
              child: StatefulBuilder(
                builder: (context, setState) => ContentSizeSlider(
                  value: value,
                  onChanged: (next) => setState(() => value = next),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(const ValueKey('content-size-step-up')));
      await tester.pump();
      expect(haptics, ['HapticFeedbackType.selectionClick']);
      // A same-value tap retries the save without another click.
      await tester.tap(find.byKey(const ValueKey('content-size-stop-2')));
      await tester.pump();
      expect(haptics, hasLength(1));
      await tester.tap(find.byKey(const ValueKey('content-size-stop-5')));
      await tester.pumpAndSettle();
      expect(haptics, hasLength(2));
      expect(value, 1.6);
      // The thumb settles on the chosen stop.
      expect(
        tester.getCenter(find.byKey(const ValueKey('content-size-thumb'))).dx,
        closeTo(
          tester
              .getCenter(find.byKey(const ValueKey('content-size-stop-5')))
              .dx,
          .01,
        ),
      );
    } finally {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      );
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets('drag writes only crossed stops; same-value taps can retry', (
    tester,
  ) async {
    final writes = <double>[];
    var value = .9;
    try {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          home: Center(
            child: SizedBox(
              width: 344,
              child: StatefulBuilder(
                builder: (context, setState) => ContentSizeSlider(
                  value: value,
                  onChanged: (next) {
                    writes.add(next);
                    setState(() => value = next);
                  },
                ),
              ),
            ),
          ),
        ),
      );
      final start = tester.getCenter(
        find.byKey(const ValueKey('content-size-stop-0')),
      );
      final pitch =
          tester
              .getCenter(find.byKey(const ValueKey('content-size-stop-1')))
              .dx -
          start.dx;
      final gesture = await tester.startGesture(start);
      // Many small pointer updates cross exactly three stops.
      for (var dx = 4.0; dx <= pitch * 3; dx += 4) {
        await gesture.moveTo(start + Offset(dx, 0));
        await tester.pump();
      }
      await gesture.up();
      await tester.pump();
      expect(writes, [1.0, 1.1, 1.2]);
      final selected = find.byKey(const ValueKey('content-size-stop-3'));
      await tester.tap(selected);
      await tester.pump();
      expect(writes, [1.0, 1.1, 1.2, 1.2]);
      // Cancellation clears the gesture-local deduplication state as well.
      final canceled = await tester.startGesture(tester.getCenter(selected));
      // Past the touch slop but still nearest the same stop.
      await canceled.moveBy(const Offset(20, 0));
      await tester.pump();
      await canceled.cancel();
      await tester.tap(selected);
      await tester.pump();
      expect(writes, [1.0, 1.1, 1.2, 1.2, 1.2]);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  testWidgets(
    'custom remains unchanged on opening; stops persist immediately',
    (tester) async {
      SharedPreferences.setMockInitialValues({'fontScale': 1.2345});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);
      try {
        await tester.pumpWidget(_app(theme));
        expect(theme.fontScale, 1.2345);
        expect(prefs.getDouble('fontScale'), 1.2345);
        final label = tester.widget<Text>(
          find.byKey(const ValueKey('content-size-value')),
        );
        expect(label.textSpan!.toPlainText(), contains('Custom'));
        expect(label.textSpan!.toPlainText(), contains('123.45%'));
        double x(String key) => tester.getCenter(find.byKey(ValueKey(key))).dx;
        expect(x('content-size-thumb'), greaterThan(x('content-size-stop-3')));
        expect(x('content-size-thumb'), lessThan(x('content-size-stop-4')));
        for (var i = 0; i < 6; i++) {
          final stop = find.byKey(ValueKey('content-size-stop-$i'));
          await tester.ensureVisible(stop);
          await tester.tap(stop);
          await tester.pump(const Duration(milliseconds: 250));
          expect(theme.fontScale, contentSizePresets[i]);
          expect(prefs.getDouble('fontScale'), contentSizePresets[i]);
          expect(find.byType(ContentSizePreview), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        theme.dispose();
      }
    },
  );

  testWidgets(
    'save failure keeps the choice visible and shows localized feedback',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final theme = _DeferredSaveTheme(await SharedPreferences.getInstance());
      try {
        await tester.pumpWidget(_app(theme));
        tester
            .widget<ContentSizeSlider>(find.byType(ContentSizeSlider))
            .onChanged(1.2);
        theme.saves.single.completeError(StateError('storage unavailable'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        expect(theme.fontScale, 1.2);
        final label = tester
            .widget<Text>(find.byKey(const ValueKey('content-size-value')))
            .textSpan!
            .toPlainText();
        expect(label, startsWith('Extra large'));
        expect(label, endsWith('120%'));
        expect(
          find.text('Couldn’t save text size. Try again.'),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 2));
        await tester.pumpAndSettle();
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        theme.dispose();
      }
    },
  );

  testWidgets(
    'superseded and unmounted saves do not show stale failure feedback',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final theme = _DeferredSaveTheme(await SharedPreferences.getInstance());
      try {
        await tester.pumpWidget(_app(theme));
        final slider = tester.widget<ContentSizeSlider>(
          find.byType(ContentSizeSlider),
        );
        slider.onChanged(1.1);
        slider.onChanged(1.35);
        theme.saves[0].completeError(StateError('old failure'));
        theme.saves[1].complete();
        await tester.pump();
        expect(theme.fontScale, 1.35);
        expect(find.text('Couldn’t save text size. Try again.'), findsNothing);
        slider.onChanged(1.6);
        await tester.pumpWidget(const SizedBox.shrink());
        theme.saves[2].completeError(StateError('closed page'));
        await tester.pump();
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        theme.dispose();
      }
    },
  );

  testWidgets('one adjustable node; RTL large OS controls remain reachable', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'fontScale': 1.8});
    final theme = ThemeController(await SharedPreferences.getInstance());
    final semantics = tester.ensureSemantics();
    try {
      await tester.binding.setSurfaceSize(const Size(390, 600));
      await tester.pumpWidget(_app(theme, rtl: true, osScale: 2));
      // At large OS text the controls scroll inside their panel; the preview
      // keeps at least half of the page.
      final panel = tester.getSize(
        find.byKey(const ValueKey('content-size-panel')),
      );
      final pages = tester.getSize(
        find.byKey(const ValueKey('content-size-preview-pages')),
      );
      expect(pages.height, greaterThanOrEqualTo(panel.height - .01));
      final slider = find.byType(ContentSizeSlider);
      await tester.ensureVisible(slider);
      final nodes = find.bySemanticsLabel('Text size');
      expect(nodes, findsWidgets);
      final adjustable = tester.widget<Semantics>(
        find.descendant(of: slider, matching: find.byType(Semantics)).first,
      );
      expect(adjustable.properties.onIncrease, isNull);
      expect(adjustable.properties.onDecrease, isNotNull);
      adjustable.properties.onDecrease!();
      await tester.pump(const Duration(milliseconds: 250));
      expect(theme.fontScale, 1.6);
      // In RTL the next preview page sits to the left, so it is revealed by
      // dragging the content toward the right.
      await tester.drag(
        find.byKey(const ValueKey('content-size-preview-pages')),
        const Offset(300, 0),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('font-size-chat-list-preview')),
        findsOneWidget,
      );
      // Tapping the side of the dots toward page one (the right in RTL) goes
      // back one page.
      // At this text size the panel scrolls, so bring the dots back first.
      final dots = find.byKey(const ValueKey('content-size-page-dots'));
      await tester.ensureVisible(dots);
      await tester.pumpAndSettle();
      await tester.tapAt(tester.getRect(dots).centerRight - const Offset(6, 0));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('font-size-chat-preview')),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      semantics.dispose();
      theme.dispose();
    }
  });

  testWidgets('previews form a two-page carousel with page dots', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final theme = ThemeController(await SharedPreferences.getInstance());
    final semantics = tester.ensureSemantics();
    Color dotColor(int i) =>
        (tester
                    .widget<AnimatedContainer>(
                      find.byKey(ValueKey('content-size-page-dot-$i')),
                    )
                    .decoration!
                as BoxDecoration)
            .color!;
    try {
      await tester.binding.setSurfaceSize(const Size(390, 760));
      await tester.pumpWidget(_app(theme));
      final chat = find.byKey(const ValueKey('font-size-chat-preview'));
      final list = find.byKey(const ValueKey('font-size-chat-list-preview'));
      expect(chat, findsOneWidget);
      expect(list, findsNothing);
      expect(find.text('Conversation'), findsNothing);
      expect(find.text('Chat list'), findsNothing);
      final active = dotColor(0);
      expect(dotColor(1), isNot(active));

      await tester.drag(
        find.byKey(const ValueKey('content-size-preview-pages')),
        const Offset(-300, 0),
      );
      await tester.pumpAndSettle();
      expect(list, findsOneWidget);
      expect(chat, findsNothing);
      expect(dotColor(1), active);

      // Sample chats show clock times or "Yesterday", never full dates.
      expect(find.textContaining(RegExp(r'\d{4}[/.-]')), findsNothing);

      final dots = find.byKey(const ValueKey('content-size-page-dots'));
      // A full-width, 32-point row: each half shows its own page.
      expect(tester.getSize(dots).height, 32);
      expect(tester.getSize(dots).width, greaterThan(300));
      await tester.tapAt(tester.getRect(dots).center - const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(chat, findsOneWidget);
      expect(dotColor(0), active);
      await tester.tapAt(tester.getRect(dots).center + const Offset(40, 0));
      await tester.pumpAndSettle();
      expect(list, findsOneWidget);
      await tester.tapAt(tester.getRect(dots).centerLeft + const Offset(6, 0));
      await tester.pumpAndSettle();
      expect(chat, findsOneWidget);

      final node = tester.getSemantics(dots);
      expect(node.label, 'Preview');
      expect(node.value, 'Conversation, 1 of 2');
      expect(
        node.getSemanticsData().hasAction(SemanticsAction.increase),
        isTrue,
      );
      tester
          .widget<Semantics>(
            find.ancestor(of: dots, matching: find.byType(Semantics)).first,
          )
          .properties
          .onIncrease!();
      await tester.pumpAndSettle();
      expect(list, findsOneWidget);
      expect(tester.getSemantics(dots).value, 'Chat list, 2 of 2');

      // Size changes keep the visible page and apply to it immediately.
      tester
          .widget<ContentSizeSlider>(find.byType(ContentSizeSlider))
          .onChanged(1.6);
      await tester.pumpAndSettle();
      expect(list, findsOneWidget);
      expect(theme.fontScale, 1.6);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
      semantics.dispose();
      theme.dispose();
    }
  });
}

Widget _app(ThemeController theme, {bool rtl = false, double osScale = 1}) =>
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(osScale)),
          child: ContentSizeRoot(
            appScale: theme.fontScale,
            child: Directionality(
              textDirection: rtl ? TextDirection.rtl : TextDirection.ltr,
              child: child!,
            ),
          ),
        ),
        home: const ContentSizeSettingsView(),
      ),
    );

/// Exercises the UI's awaitable persistence contract without replacing a
/// process-global platform singleton. Actual preferences failure is owned by
/// the ThemeController tests.
class _DeferredSaveTheme extends ThemeController {
  _DeferredSaveTheme(super.prefs);

  double _scale = 1;
  final saves = <Completer<void>>[];

  @override
  double get fontScale => _scale;

  @override
  Future<void> setFontScale(double value) {
    _scale = value;
    notifyListeners();
    final completion = Completer<void>();
    saves.add(completion);
    return completion.future;
  }
}
