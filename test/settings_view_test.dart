import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/pro/mithka_pro_service.dart';
import 'package:mithka/settings/chat_folder_management_view.dart';
import 'package:mithka/settings/developer_mode_controller.dart';
import 'package:mithka/settings/settings_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uses one task-oriented list with direct settings destinations', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSettings(tester);

    expect(
      find.byKey(const PageStorageKey<String>('settings-list')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-section-telegram')),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('settings-section-mithka')), findsNothing);

    const expectedOrder = [
      'edit-profile',
      'telegram-business',
      'mithka-pro',
      'notifications',
      'telegram-privacy',
      'telegram-blocked-users',
      'mithka-content-filters',
      'mithka-app-lock',
      'mithka-account-backup',
      'mithka-appearance',
      'telegram-chat-folders',
      'mithka-chat-behavior',
      'mithka-data-storage',
      'mithka-language',
      'telegram-language',
      'mithka-translation',
      'mithka-features',
      'mithka-ai',
      'mithka-proxy',
      'mithka-advanced',
      'mithka-about',
    ];
    var previousTop = double.negativeInfinity;
    for (final id in expectedOrder) {
      final destination = find.byKey(ValueKey('settings-destination-$id'));
      expect(
        destination,
        findsOneWidget,
        reason: '$id should have one direct route',
      );
      final top = tester.getTopLeft(destination).dy;
      expect(
        top,
        greaterThan(previousTop),
        reason: '$id should follow the task-oriented settings order',
      );
      previousTop = top;
    }

    expect(
      tester.getTopLeft(find.byKey(const ValueKey('settings-log-out'))).dy,
      greaterThan(previousTop),
      reason: 'Log Out should be the final action, not a false page ending',
    );
    expect(find.text('Telegram Account'), findsNothing);
    expect(find.text('Mithka'), findsNothing);
    expect(find.text('General'), findsNothing);
    expect(find.text('Blocking'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings-destination-notifications')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings-destination-telegram-notifications')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings-destination-mithka-notifications')),
      findsNothing,
    );

    await tester.tap(
      find.byKey(const ValueKey('settings-destination-telegram-chat-folders')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChatFolderManagementView), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets('search reaches leaf settings and identifies their owner', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(402, 874);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSettings(tester, focusSearch: true);

    final editable = tester.widget<EditableText>(find.byType(EditableText));
    expect(editable.focusNode.hasFocus, isTrue);

    await tester.enterText(
      find.byKey(const ValueKey('settings-search-field')),
      'cache',
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey('settings-destination-mithka-data-storage')),
      findsOneWidget,
    );
    expect(
      find.byKey(const PageStorageKey<String>('settings-search-results')),
      findsOneWidget,
    );
    expect(find.text('Mithka'), findsOneWidget);
    expect(
      find.byKey(const PageStorageKey<String>('settings-list')),
      findsNothing,
    );

    await tester.enterText(
      find.byKey(const ValueKey('settings-search-field')),
      '2fa',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('settings-destination-telegram-privacy')),
      findsOneWidget,
    );
    expect(find.text('Telegram Account'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('settings-search-field')),
      'lock screen',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('settings-destination-notifications')),
      findsOneWidget,
    );
    expect(find.text('Telegram Account'), findsNothing);
    expect(find.text('Mithka'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('settings-search-field')),
      'disable message bubbles',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('settings-destination-mithka-appearance')),
      findsOneWidget,
    );
    expect(find.text('Mithka'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('settings-search-field')),
      'not a real setting',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('settings-search-empty')), findsOneWidget);
    expect(find.text('No matching settings'), findsOneWidget);
  });

  testWidgets('developer destination remains conditional', (tester) async {
    tester.view.physicalSize = const Size(402, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSettings(tester);
    expect(
      find.byKey(const ValueKey('settings-destination-mithka-developer')),
      findsNothing,
    );

    await _pumpSettings(tester, developerUnlocked: true);
    expect(
      find.byKey(const ValueKey('settings-destination-mithka-developer')),
      findsOneWidget,
    );
  });

  testWidgets('single settings list remains usable with narrow large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSettings(tester, textScaler: const TextScaler.linear(2));

    expect(tester.takeException(), isNull);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('settings-search-container')))
          .height,
      greaterThan(40),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  bool focusSearch = false,
  bool developerUnlocked = false,
  TextScaler? textScaler,
}) async {
  SharedPreferences.setMockInitialValues({
    if (developerUnlocked) 'developer_mode.unlocked': true,
  });
  final preferences = await SharedPreferences.getInstance();
  final theme = ThemeController(preferences);
  final developer = DeveloperModeController(preferences);
  final pro = MithkaProService();
  addTearDown(theme.dispose);
  addTearDown(developer.dispose);
  addTearDown(pro.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<DeveloperModeController>.value(value: developer),
        ChangeNotifierProvider<MithkaProService>.value(value: pro),
      ],
      child: MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: textScaler == null
            ? SettingsView(focusSearch: focusSearch)
            : MediaQuery(
                data: MediaQueryData(
                  size: tester.view.physicalSize,
                  textScaler: textScaler,
                ),
                child: SettingsView(focusSearch: focusSearch),
              ),
      ),
    ),
  );
  await tester.pump();
}
