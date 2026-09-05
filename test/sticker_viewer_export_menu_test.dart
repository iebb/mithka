import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/sticker_viewer.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ellipsis opens sticker export menu and table dummy is gone', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final themeController = ThemeController(
      await SharedPreferences.getInstance(),
    );
    final message = ChatMessage(
      id: 55,
      isOutgoing: false,
      text: '',
      date: 1,
      stickerFileId: 55,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeController,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: StickerViewer(message: message),
        ),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is AppIcon &&
            widget.icon.data == HeroAppIcons.tableCells.data,
      ),
      findsNothing,
    );

    await tester.tap(find.byKey(const ValueKey('sticker-export-menu-button')));
    await tester.pump();

    expect(find.byKey(const ValueKey('sticker-export-menu')), findsOneWidget);
    final menuRect = tester.getRect(
      find.byKey(const ValueKey('sticker-export-menu')),
    );
    expect(menuRect.left, greaterThanOrEqualTo(0));
    expect(menuRect.top, greaterThanOrEqualTo(0));
    expect(menuRect.right, lessThanOrEqualTo(390));
    expect(menuRect.bottom, lessThanOrEqualTo(844));
    for (final destination in ['photos', 'files']) {
      expect(
        find.byKey(ValueKey('sticker-export-$destination-png')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey('sticker-export-$destination-gif')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey('sticker-export-$destination-mov')),
        findsNothing,
      );
    }
    debugDefaultTargetPlatformOverride = null;
  });
  testWidgets('desktop export menu drops the album destination', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final themeController = ThemeController(
      await SharedPreferences.getInstance(),
    );
    final message = ChatMessage(
      id: 56,
      isOutgoing: false,
      text: '',
      date: 1,
      stickerFileId: 56,
    );

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: themeController,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          localizationsDelegates: const [AppLocalizations.delegate],
          supportedLocales: AppLocalizations.supportedLocales,
          home: StickerViewer(message: message),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('sticker-export-menu-button')));
    await tester.pump();

    expect(find.byKey(const ValueKey('sticker-export-menu')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('sticker-export-photos-png')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('sticker-export-files-png')),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });
}
