import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/pro/mithka_pro_service.dart';
import 'package:mithka/settings/about_view.dart';
import 'package:mithka/settings/auto_download_media_controller.dart';
import 'package:mithka/settings/chat_folder_management_view.dart';
import 'package:mithka/settings/desktop_hotkey_settings_view.dart';
import 'package:mithka/settings/developer_mode_controller.dart';
import 'package:mithka/settings/general_settings_view.dart';
import 'package:mithka/settings/settings_view.dart';
import 'package:mithka/settings/storage_usage_view.dart';
import 'package:mithka/settings/video_playback_settings_view.dart';
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
      // edit-profile and telegram-business are top-level entries now, and
      // mithka-pro is hidden wherever no store can open its paywall.
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
      find.byKey(const ValueKey('settings-destination-mithka-language')),
      findsNothing,
    );
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

  testWidgets('desktop settings use a nested category sidebar', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSettings(
      tester,
      showBackButton: false,
      allowSessionLifecycleActions: false,
    );

    expect(find.byKey(const ValueKey('settings-split-layout')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-compact-layout')), findsNothing);
    expect(
      tester
          .getSize(find.byKey(const ValueKey('settings-category-sidebar')))
          .width,
      312,
    );
    expect(find.byKey(const ValueKey('settings-root-back')), findsNothing);
    expect(find.byKey(const ValueKey('settings-log-out')), findsNothing);

    // General is absent here: it holds only Mithka Pro, which hides itself
    // where no store can open its paywall. The first category is Notifications,
    // a single-screen category that is its own row rather than a parent.
    expect(
      find.byKey(const ValueKey('settings-category-general')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings-category-notifications')),
      findsOneWidget,
      reason: 'a single-screen category is its own row in the sidebar',
    );

    // A collapsed category hides its children until it is opened.
    expect(
      find.byKey(const ValueKey('settings-child-mithka-chat-behavior')),
      findsNothing,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-category-appearance')),
    );
    // Bounded pumps: the default pane is now Notifications, whose loading
    // indicator spins forever without a TDLib connection, so nothing settles.
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(
      find.byKey(const ValueKey('settings-category-appearance')),
    );
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      find.byKey(const ValueKey('settings-child-mithka-chat-behavior')),
      findsOneWidget,
    );

    // Choosing a child shows it in the detail pane, with no intermediate list.
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-child-mithka-chat-behavior')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-child-mithka-chat-behavior')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(ChatBehaviorSettingsView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-category-sidebar')),
      findsOneWidget,
      reason: 'the sidebar stays put while the detail pane changes',
    );

    final backChevron = find.byWidgetPredicate(
      (widget) => widget is AppIcon && widget.icon == HeroAppIcons.chevronLeft,
    );
    expect(backChevron, findsNothing);
    await tester.tap(find.widgetWithText(SettingsRow, 'Video playback'));
    await tester.pumpAndSettle();
    expect(find.byType(VideoPlaybackSettingsView), findsOneWidget);
    expect(backChevron, findsOneWidget);
    await tester.tap(backChevron);
    await tester.pumpAndSettle();
    expect(find.byType(ChatBehaviorSettingsView), findsOneWidget);
    expect(backChevron, findsNothing);

    // Tapping the header again collapses it without changing the detail pane.
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-category-appearance')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-category-appearance')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('settings-child-mithka-chat-behavior')),
      findsNothing,
    );
    expect(find.byType(ChatBehaviorSettingsView), findsOneWidget);

    // A single-screen category is a leaf: no children, no disclosure step.
    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-category-data-storage')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('settings-category-data-storage')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(StorageUsageView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-child-mithka-data-storage')),
      findsNothing,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey('settings-category-about')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('settings-category-about')));
    await tester.pumpAndSettle();
    expect(find.byType(AboutView), findsOneWidget);

    // Nothing in the split layout pushes a route, so no back affordance.
    expect(backChevron, findsNothing);

    // Search replaces the tree with flat matches.
    await tester.enterText(
      find.byKey(const ValueKey('settings-search-field')),
      'backup',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('settings-category-general')),
      findsNothing,
      reason: 'the tree gives way to matches while searching',
    );
    expect(
      find.byKey(const ValueKey('settings-match-mithka-account-backup')),
      findsNothing,
      reason: 'session actions are off in this configuration',
    );

    await tester.enterText(
      find.byKey(const ValueKey('settings-search-field')),
      'appearance',
    );
    await tester.pump();
    expect(
      find.byKey(const ValueKey('settings-match-mithka-appearance')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('settings-search-field')),
      '',
    );
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('signing out lives under the sidebar tree', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Reset inside the body: addTearDown runs after Flutter asserts that debug
    // variables were left unset, which would mask a real failure here.
    try {
      await _pumpSettings(tester);

      final logOut = find.byKey(const ValueKey('settings-log-out'));
      expect(logOut, findsOneWidget);
      expect(
        tester.getCenter(logOut).dx,
        lessThan(312),
        reason:
            'it belongs to the account, not to a section, so it sits in '
            'the sidebar rather than inside one category',
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop shortcut can select Appearance initially', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    try {
      await _pumpSettings(tester, initialCategoryId: 'appearance');

      expect(
        find.byKey(const ValueKey('settings-split-layout')),
        findsOneWidget,
      );
      // The shortcut opens the category, so its screens are listed and
      // General's are not.
      expect(
        find.byKey(const ValueKey('settings-child-mithka-appearance')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('settings-child-notifications')),
        findsNothing,
      );
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop split exposes a direct keyboard shortcuts category', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpSettings(tester, initialCategoryId: 'hotkeys');
    await tester.pump();

    expect(
      find.byKey(const ValueKey('settings-category-hotkeys')),
      findsOneWidget,
    );
    expect(find.byType(DesktopHotkeySettingsView), findsOneWidget);
    expect(
      find.byKey(const ValueKey('desktop-hotkey-screenshot')),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
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
  bool showBackButton = true,
  bool allowSessionLifecycleActions = true,
  String? initialCategoryId,
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
  final autoDownload = AutoDownloadMediaController.shared
    ..initialize(preferences);
  addTearDown(theme.dispose);
  addTearDown(developer.dispose);
  addTearDown(pro.dispose);

  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<ThemeController>.value(value: theme),
        ChangeNotifierProvider<DeveloperModeController>.value(value: developer),
        ChangeNotifierProvider<MithkaProService>.value(value: pro),
        ChangeNotifierProvider<AutoDownloadMediaController>.value(
          value: autoDownload,
        ),
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
            ? SettingsView(
                focusSearch: focusSearch,
                showBackButton: showBackButton,
                allowSessionLifecycleActions: allowSessionLifecycleActions,
                initialCategoryId: initialCategoryId,
              )
            : MediaQuery(
                data: MediaQueryData(
                  size: tester.view.physicalSize,
                  textScaler: textScaler,
                ),
                child: SettingsView(
                  focusSearch: focusSearch,
                  showBackButton: showBackButton,
                  allowSessionLifecycleActions: allowSessionLifecycleActions,
                  initialCategoryId: initialCategoryId,
                ),
              ),
      ),
    ),
  );
  await tester.pump();
}
