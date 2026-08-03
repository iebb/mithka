import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  testWidgets(
    'selected chat has a branded wash, leading rail, and selected semantics',
    (tester) async {
      final previousBrand = AppTheme.brand;
      const customBrand = Color(0xFF8D4CE8);
      AppTheme.applyBrand(customBrand);
      addTearDown(() => AppTheme.applyBrand(previousBrand));
      var taps = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            brightness: Brightness.dark,
            extensions: [AppColors.dark],
          ),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                height: 58,
                child: ChatListSelectionHighlight(
                  selected: true,
                  child: GestureDetector(
                    key: const ValueKey('chat-row-hit-target'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => taps++,
                    child: const ColoredBox(color: Color(0xFF242628)),
                  ),
                ),
              ),
            ),
          ),
        ),
      );

      final tint = tester.widget<ColoredBox>(
        find.byKey(ChatListSelectionHighlight.tintKey),
      );
      expect(tint.color, customBrand.withValues(alpha: 0.13));

      final rail = tester.widget<Container>(
        find.byKey(ChatListSelectionHighlight.railKey),
      );
      expect(rail.decoration, isA<BoxDecoration>());
      expect((rail.decoration! as BoxDecoration).color, customBrand);
      expect(
        tester.getSize(find.byKey(ChatListSelectionHighlight.railKey)),
        const Size(3, 46),
      );
      expect(
        tester.getTopLeft(find.byKey(ChatListSelectionHighlight.railKey)).dx,
        tester.getTopLeft(find.byKey(const ValueKey('chat-row-hit-target'))).dx,
      );

      final semantics = tester.widget<Semantics>(
        find.byKey(ChatListSelectionHighlight.semanticsKey),
      );
      expect(semantics.properties.selected, isTrue);

      await tester.tap(find.byKey(const ValueKey('chat-row-hit-target')));
      expect(taps, 1, reason: 'selection decoration must not absorb row taps');
    },
  );

  testWidgets('unselected chat leaves the row undecorated', (tester) async {
    const childKey = ValueKey('unselected-chat-row');

    await tester.pumpWidget(
      const MaterialApp(
        home: SizedBox(
          width: 320,
          height: 58,
          child: ChatListSelectionHighlight(
            selected: false,
            child: ColoredBox(key: childKey, color: Color(0xFFFAFAFA)),
          ),
        ),
      ),
    );

    expect(find.byKey(childKey), findsOneWidget);
    expect(find.byKey(ChatListSelectionHighlight.tintKey), findsNothing);
    expect(find.byKey(ChatListSelectionHighlight.railKey), findsNothing);
    expect(find.byKey(ChatListSelectionHighlight.semanticsKey), findsNothing);
  });
}
