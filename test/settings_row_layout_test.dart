import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/ui_components.dart';

void main() {
  testWidgets('colored settings tiles always use white project icons', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Center(
          child: SettingsIconTile(
            icon: HeroAppIcons.solidBell,
            backgroundColor: Color(0xFFFFD44A),
          ),
        ),
      ),
    );

    final icon = tester.widget<Icon>(find.byIcon(HeroAppIcons.solidBell.data));
    expect(icon.color, const Color(0xFFFFFFFF));
  });

  testWidgets('settings rows pin their trailing controls on narrow screens', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SettingsRow(
              key: ValueKey('full-width-settings-row'),
              title: 'A very long appearance setting label',
              value: '100%',
            ),
            SettingsSwitchRow(
              title: 'A very long switch setting label',
              value: true,
              onChanged: (_) {},
            ),
            const Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: 220,
                child: SettingsRow(
                  key: ValueKey('constrained-settings-row'),
                  title: 'A long label inside a narrow settings panel',
                  value: 'A long selected font family name',
                  leading: SizedBox(width: 22, height: 22),
                ),
              ),
            ),
          ],
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    final valueRect = tester.getRect(find.text('100%'));
    final chevronRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('full-width-settings-row')),
        matching: find.byIcon(HeroAppIcons.chevronRight.data),
      ),
    );
    final switchRect = tester.getRect(find.byType(AppSwitch));
    final constrainedValueRect = tester.getRect(
      find.text('A long selected font family name'),
    );
    final constrainedChevronRect = tester.getRect(
      find.descendant(
        of: find.byKey(const ValueKey('constrained-settings-row')),
        matching: find.byIcon(HeroAppIcons.chevronRight.data),
      ),
    );

    expect(valueRect.right, lessThanOrEqualTo(chevronRect.left));
    expect(chevronRect.right, greaterThan(290));
    expect(switchRect.right, greaterThan(290));
    expect(
      constrainedValueRect.right,
      lessThanOrEqualTo(constrainedChevronRect.left),
    );
  });
}
