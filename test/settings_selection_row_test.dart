import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/settings_selection_row.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_motion.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('desktop selector opens beside its row without a modal surface', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(
      _shell(
        TargetPlatform.macOS,
        const _SelectionHarness(dismissOnSelect: true),
      ),
    );

    final row = find.byType(SettingsRow);
    final rowRect = tester.getRect(row);
    await tester.tap(find.text('Mode'));
    await tester.pumpAndSettle();

    final menu = find.byKey(const ValueKey('test-selection-menu'));
    expect(menu, findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.byKey(appCenteredModalFrameKey), findsNothing);
    final menuRect = tester.getRect(menu);
    expect(menuRect.top, greaterThanOrEqualTo(rowRect.bottom));
    expect(menuRect.right, closeTo(rowRect.right, 0.01));
    expect(
      tester
          .widgetList<ModalBarrier>(find.byType(ModalBarrier))
          .every(
            (barrier) =>
                barrier.color == null || barrier.color == Colors.transparent,
          ),
      isTrue,
    );

    await tester.tap(find.byKey(const ValueKey('test-option-b')));
    await tester.pumpAndSettle();
    expect(find.text('Selected: b'), findsOneWidget);
    expect(menu, findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop multi-select stays open and Escape dismisses it', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await tester.pumpWidget(
      _shell(
        TargetPlatform.macOS,
        const _SelectionHarness(dismissOnSelect: false),
      ),
    );

    await tester.tap(find.text('Mode'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('test-option-b')));
    await tester.pump();

    expect(find.byKey(const ValueKey('test-selection-menu')), findsOneWidget);
    expect(find.text('Selected: a,b'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('test-selection-menu')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('touch selector keeps the bottom-sheet presentation', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(
      _shell(
        TargetPlatform.android,
        const _SelectionHarness(dismissOnSelect: true),
      ),
    );

    await tester.tap(find.text('Mode'));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-settings-selection-menu')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('test-option-c')));
    await tester.pumpAndSettle();
    expect(find.text('Selected: c'), findsOneWidget);
    expect(find.byType(BottomSheet), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}

class _SelectionHarness extends StatefulWidget {
  const _SelectionHarness({required this.dismissOnSelect});

  final bool dismissOnSelect;

  @override
  State<_SelectionHarness> createState() => _SelectionHarnessState();
}

class _SelectionHarnessState extends State<_SelectionHarness> {
  final Set<String> _selected = {'a'};

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SettingsSelectionRow<String>(
          title: 'Mode',
          value: _selected.join(','),
          menuKey: const ValueKey('test-selection-menu'),
          dismissOnSelect: widget.dismissOnSelect,
          leading: const SettingsLeadingIcon(icon: HeroAppIcons.gear),
          options: const [
            SettingsSelectionOption(
              id: 'test-option-a',
              value: 'a',
              label: 'Option A',
              icon: HeroAppIcons.gear,
            ),
            SettingsSelectionOption(
              id: 'test-option-b',
              value: 'b',
              label: 'Option B',
              icon: HeroAppIcons.gear,
            ),
            SettingsSelectionOption(
              id: 'test-option-c',
              value: 'c',
              label: 'Option C',
              icon: HeroAppIcons.gear,
            ),
          ],
          isSelected: _selected.contains,
          onSelected: (value) => setState(() {
            if (widget.dismissOnSelect) {
              _selected
                ..clear()
                ..add(value);
            } else if (!_selected.remove(value)) {
              _selected.add(value);
            }
          }),
        ),
        Text('Selected: ${_selected.join(',')}'),
      ],
    );
  }
}

Widget _shell(TargetPlatform platform, Widget child) => MaterialApp(
  locale: const Locale('en'),
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  supportedLocales: AppLocalizations.supportedLocales,
  theme: ThemeData(platform: platform, extensions: [AppColors.light]),
  home: Scaffold(
    body: Align(
      alignment: Alignment.topLeft,
      child: SizedBox(width: 520, child: child),
    ),
  ),
);
