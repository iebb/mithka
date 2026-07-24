import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_appearance_preview.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('sender name readability defaults to shadow and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final controller = ThemeController(preferences);

    expect(
      controller.senderNameReadabilityMode,
      SenderNameReadabilityMode.shadow,
    );

    controller.senderNameReadabilityMode = SenderNameReadabilityMode.background;
    expect(preferences.getString('senderNameReadabilityMode.v1'), 'background');

    final restored = ThemeController(preferences);
    expect(
      restored.senderNameReadabilityMode,
      SenderNameReadabilityMode.background,
    );
  });

  test('legacy sender name background preference migrates', () async {
    SharedPreferences.setMockInitialValues({
      'showSenderNameReadabilityPlate': false,
    });
    var preferences = await SharedPreferences.getInstance();
    expect(
      ThemeController(preferences).senderNameReadabilityMode,
      SenderNameReadabilityMode.none,
    );

    SharedPreferences.setMockInitialValues({
      'showSenderNameReadabilityPlate': true,
    });
    preferences = await SharedPreferences.getInstance();
    expect(
      ThemeController(preferences).senderNameReadabilityMode,
      SenderNameReadabilityMode.background,
    );
  });

  testWidgets('sender name plate only decorates its child when enabled', (
    tester,
  ) async {
    Future<void> pump(SenderNameReadabilityMode mode) => tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: SenderNameReadabilityPlate(
          mode: mode,
          bubbleColor: const Color(0xFF223344),
          child: const Text('Bob Harris'),
        ),
      ),
    );

    await pump(SenderNameReadabilityMode.none);
    expect(
      find.byKey(const ValueKey('senderNameReadabilityPlate')),
      findsNothing,
    );

    await pump(SenderNameReadabilityMode.background);
    expect(
      find.byKey(const ValueKey('senderNameReadabilityPlate')),
      findsOneWidget,
    );
    final decoration = senderNameReadabilityDecoration(const Color(0xFF223344));
    expect(decoration.color, const Color(0xFF223344));
    expect(decoration.borderRadius, isNotNull);
    expect(decoration.boxShadow, isNotEmpty);
  });

  testWidgets('shadow mode uses the bubble color behind the sender name', (
    tester,
  ) async {
    const bubbleColor = Color(0xFF223344);
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SenderNameReadabilityPlate(
          mode: SenderNameReadabilityMode.shadow,
          bubbleColor: bubbleColor,
          child: Text('Bob Harris'),
        ),
      ),
    );

    final defaultText = tester.widget<DefaultTextStyle>(
      find.byKey(const ValueKey('senderNameReadabilityShadow')),
    );
    expect(defaultText.style.shadows, isNotEmpty);
    expect(defaultText.style.shadows!.single.color, bubbleColor);
  });

  testWidgets('sender role and name become connected equal-size pills', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: SenderIdentityPills(
            readabilityMode: SenderNameReadabilityMode.background,
            bubbleColor: Color(0xFF223344),
            name: 'Bob Harris',
            nameStyle: TextStyle(fontSize: 12, color: Color(0xFFB4C4E2)),
            role: MemberRole.admin,
            roleTitle: 'Moderator',
          ),
        ),
      ),
    );

    final roleTag = tester.widget<RoleTag>(find.byType(RoleTag));
    expect(roleTag.connectedToTrailing, isTrue);
    expect(roleTag.fontSize, 12);
    expect(
      find.byKey(const ValueKey('connectedSenderIdentityPills')),
      findsOneWidget,
    );

    final rolePill = find.byKey(const ValueKey('connectedSenderRoleTag'));
    final namePill = find.byKey(const ValueKey('senderNameReadabilityPlate'));
    expect(tester.getTopRight(rolePill).dx, tester.getTopLeft(namePill).dx);

    final roleContainer = tester.widget<Container>(rolePill);
    expect(
      roleContainer.padding,
      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    );
    final namePadding = tester.widget<Padding>(
      find.descendant(of: namePill, matching: find.byType(Padding)).first,
    );
    expect(
      namePadding.padding,
      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    );

    final roleText = tester.widget<Text>(find.text('Moderator'));
    final nameText = tester.widget<Text>(find.text('Bob Harris'));
    expect(roleText.style?.fontSize, nameText.style?.fontSize);

    final nameDecoration =
        tester.widget<DecoratedBox>(namePill).decoration as BoxDecoration;
    final roleDecoration = roleContainer.decoration! as BoxDecoration;
    expect(nameDecoration.color, const Color(0xFF223344));
    expect(nameDecoration.boxShadow, isNotEmpty);
    expect(roleDecoration.boxShadow, isNotEmpty);
    expect(
      nameDecoration.borderRadius,
      const BorderRadiusDirectional.only(
        topEnd: Radius.circular(8),
        bottomEnd: Radius.circular(8),
      ),
    );
  });
}
