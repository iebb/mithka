import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/contacts/contacts_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  for (final width in <double>[300, 320]) {
    testWidgets(
      'desktop Contacts toolbar and icon tabs fit a ${width.toInt()}px sidebar',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
        await _setSurfaceSize(tester, const Size(800, 700));
        await _pumpContacts(tester, width: width, desktopSidebar: true);

        expect(
          find.byKey(const ValueKey('contacts-root-header')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey('contacts-desktop-toolbar')),
          findsOneWidget,
        );

        final searchRect = tester.getRect(
          find.byKey(const ValueKey('contacts-search-field')),
        );
        final addRect = tester.getRect(
          find.byKey(const ValueKey('contacts-desktop-add-action')),
        );
        expect(searchRect.height, 36);
        expect(addRect.size, const Size(36, 36));
        expect(addRect.left - searchRect.right, 8);
        expect(addRect.center.dy, searchRect.center.dy);

        final tabsRect = tester.getRect(
          find.byKey(const ValueKey('contacts-tabs')),
        );
        const labels = ['Friends', 'Group chat', 'Channels', 'Bots'];
        expect(tabsRect.width, width);
        for (var index = 0; index < 4; index++) {
          final tabRect = tester.getRect(
            find.byKey(ValueKey('contacts-tab-$index')),
          );
          final iconHitRect = tester.getRect(
            find.byKey(ValueKey('contacts-tab-icon-hit-$index')),
          );
          final indicatorRect = tester.getRect(
            find.byKey(ValueKey('contacts-tab-indicator-$index')),
          );

          expect(tabRect.width, closeTo(width / 4, 0.001));
          expect(tabRect.height, 50);
          expect(iconHitRect.size, const Size(36, 36));
          expect(iconHitRect.center.dx, closeTo(tabRect.center.dx, 0.001));
          expect(iconHitRect.bottom, lessThanOrEqualTo(indicatorRect.top));
          expect(indicatorRect.width, index == 0 ? 32 : 0);
          expect(indicatorRect.bottom, closeTo(tabRect.bottom, 0.001));
          expect(
            find.byKey(ValueKey('contacts-tab-icon-$index')),
            findsOneWidget,
          );
          expect(
            find.byKey(ValueKey('contacts-tab-label-$index')),
            findsNothing,
          );
          expect(find.byTooltip(labels[index]), findsOneWidget);
          expect(
            tester
                .getSemantics(find.byKey(ValueKey('contacts-tab-$index')))
                .label,
            labels[index],
          );
        }

        expect(tester.takeException(), isNull);
        await _disposeContacts(tester);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('default Contacts view preserves its mobile root header', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await _setSurfaceSize(tester, const Size(390, 844));
    await _pumpContacts(tester, width: 390);

    final header = find.byKey(const ValueKey('contacts-root-header'));
    final search = find.byKey(const ValueKey('contacts-search-field'));
    expect(header, findsOneWidget);
    expect(
      find.byKey(const ValueKey('contacts-desktop-toolbar')),
      findsNothing,
    );
    expect(
      find.descendant(of: header, matching: find.byType(PhotoAvatar)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: header, matching: find.text('Contacts')),
      findsOneWidget,
    );
    for (var index = 0; index < 4; index++) {
      expect(find.byKey(ValueKey('contacts-tab-label-$index')), findsOneWidget);
      expect(find.byKey(ValueKey('contacts-tab-icon-$index')), findsNothing);
    }
    expect(tester.getRect(search).top, tester.getRect(header).bottom + 10);
    expect(tester.takeException(), isNull);
    await _disposeContacts(tester);
    debugDefaultTargetPlatformOverride = null;
  });
}

Future<void> _pumpContacts(
  WidgetTester tester, {
  required double width,
  bool desktopSidebar = false,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      theme: ThemeData(
        brightness: Brightness.light,
        extensions: [AppColors.light],
      ),
      home: Material(
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            height: 700,
            child: ContactsView(desktopSidebar: desktopSidebar),
          ),
        ),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _disposeContacts(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

Future<void> _setSurfaceSize(WidgetTester tester, Size size) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
}
