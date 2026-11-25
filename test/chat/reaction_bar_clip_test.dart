//
//  reaction_bar_clip_test.dart
//
//  The reaction strips draw emoji with the app's inherited text style, so the
//  glyph's line box follows the UI font: a CJK font runs ~1.35–1.45em, taller
//  than the ~1.18em the emoji itself needs. A slot sized on a fixed constant
//  (34 for a 28pt emoji, 30 for a 22pt one) therefore clipped the glyph top and
//  bottom — `Text` clips to the paragraph's own box (`TextOverflow.clip`).
//  These cases pin the strips to the emoji's REAL line box: the glyph box must
//  never be shorter than the text it carries, whatever line height it inherits,
//  and must keep its designed size for the fonts that already fit.
//

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/messages/message_action_menu.dart';
import 'package:mithka/chat/messages/quick_reaction_choice.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  const emoji = ['😀', '❤️', '👍', '🎉', '🔥'];

  List<QuickReactionChoice> choices() => [
    for (final e in emoji) QuickReactionChoice.emoji(e),
  ];

  /// Pumps [child] under a default text style whose line box is [lineHeight]
  /// times the font size — 1.5 stands in for the CJK UI fonts (1.35–1.45em)
  /// that clipped the glyphs on device.
  Future<void> pumpHosted(
    WidgetTester tester,
    Widget child, {
    double? lineHeight,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: DefaultTextStyle(
            style: TextStyle(fontSize: 17, height: lineHeight),
            child: Center(child: child),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The line box the emoji gets from the style it actually inherits — the
  /// measurement the strip has to leave room for.
  double glyphLineHeight(WidgetTester tester, Finder glyph, double fontSize) {
    final text = tester.widget<Text>(glyph);
    final style = DefaultTextStyle.of(
      tester.element(glyph),
    ).style.merge(TextStyle(fontSize: fontSize));
    final painter = TextPainter(
      text: TextSpan(text: text.data, style: style),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
      maxLines: 1,
    )..layout();
    final height = painter.height;
    painter.dispose();
    return height;
  }

  testWidgets('the quick reaction pill keeps a tall inherited line box whole', (
    tester,
  ) async {
    await pumpHosted(
      tester,
      QuickReactionBar(
        reactions: choices(),
        onReaction: (_) {},
        onExpand: () {},
      ),
      lineHeight: 1.5,
    );

    for (final glyph in emoji) {
      final finder = find.text(glyph);
      final lineHeight = glyphLineHeight(tester, finder, 28);
      final box = tester.getSize(finder);
      expect(
        box.height,
        greaterThanOrEqualTo(lineHeight - 0.01),
        reason:
            'the 28pt reaction glyph "$glyph" is clipped: it is laid out at '
            '${box.height} inside a ${lineHeight}pt line box',
      );
    }

    // The pill must contain that taller slot plus its own padding.
    final pillFinder = find.byKey(const ValueKey('quick-reaction-bar'));
    final pill = tester.getSize(pillFinder);
    expect(pill.height, QuickReactionBar.heightFor(tester.element(pillFinder)));
  });

  testWidgets('the quick reaction pill keeps its size for ordinary fonts', (
    tester,
  ) async {
    await pumpHosted(
      tester,
      QuickReactionBar(
        reactions: choices(),
        onReaction: (_) {},
        onExpand: () {},
      ),
    );

    final pill = tester.getSize(
      find.byKey(const ValueKey('quick-reaction-bar')),
    );
    expect(pill.height, 46);
  });

  testWidgets('the desktop reaction strip keeps a tall line box whole', (
    tester,
  ) async {
    await pumpHosted(
      tester,
      SizedBox(
        width: 220,
        child: MenuReactionBar(
          reactions: choices(),
          onReaction: (_) {},
          onExpand: () {},
        ),
      ),
      lineHeight: 1.5,
    );

    for (final glyph in emoji) {
      final finder = find.text(glyph);
      final lineHeight = glyphLineHeight(tester, finder, 22);
      final box = tester.getSize(finder);
      expect(
        box.height,
        greaterThanOrEqualTo(lineHeight - 0.01),
        reason:
            'the 22pt reaction glyph "$glyph" is clipped: it is laid out at '
            '${box.height} inside a ${lineHeight}pt line box',
      );
    }

    final stripFinder = find.byKey(const ValueKey('menu-reaction-bar'));
    expect(
      tester.getSize(stripFinder).height,
      MenuReactionBar.heightFor(tester.element(stripFinder)),
    );
  });

  testWidgets('the desktop reaction strip keeps its size for ordinary fonts', (
    tester,
  ) async {
    await pumpHosted(
      tester,
      SizedBox(
        width: 220,
        child: MenuReactionBar(
          reactions: choices(),
          onReaction: (_) {},
          onExpand: () {},
        ),
      ),
    );

    final strip = tester.getSize(
      find.byKey(const ValueKey('menu-reaction-bar')),
    );
    expect(strip.height, 40);
  });

  testWidgets('the emoji slot itself carries the measured line box', (
    tester,
  ) async {
    await pumpHosted(
      tester,
      QuickReactionBar(
        reactions: choices(),
        onReaction: (_) {},
        onExpand: () {},
      ),
      lineHeight: 1.5,
    );

    final slot = tester.renderObject<RenderBox>(
      find.byKey(ValueKey('quick-reaction-${choices().first.storageValue}')),
    );
    expect(slot.size.height, greaterThanOrEqualTo(28 * 1.5));
  });
}
