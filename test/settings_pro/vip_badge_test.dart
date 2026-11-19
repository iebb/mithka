import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/vip_badge.dart';

void main() {
  testWidgets('the VIP badge is a small labelled penguin, not a text pill', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: VipBadge()),
      ),
    );

    expect(tester.getSize(find.byType(VipBadge)), const Size.square(18));
    expect(
      find.descendant(of: find.byType(VipBadge), matching: find.byType(Text)),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(VipBadge),
        matching: find.byType(CustomPaint),
      ),
      findsOneWidget,
    );
    expect(find.bySemanticsLabel('VIP'), findsOneWidget);
    semantics.dispose();
  });
}
