import 'dart:async';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/chat_folder_management_view.dart';
import 'package:mithka/settings/chat_folder_service.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<Widget> testApp(Widget child) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final theme = ThemeController(preferences);
    addTearDown(theme.dispose);
    return ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        locale: const Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [AppLocalizations.delegate],
        theme: ThemeData(extensions: [AppColors.light]),
        home: child,
      ),
    );
  }

  Future<void> pumpView(WidgetTester tester, _FolderTagHarness harness) async {
    addTearDown(harness.dispose);
    await tester.pumpWidget(
      await testApp(
        ChatFolderManagementView(
          service: ChatFolderService(query: harness.query),
          updates: harness.updates.stream,
          onLockedFolderTagsActivated: harness.activateLocked,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('Premium-unavailable accounts do not see folder tags', (
    tester,
  ) async {
    final harness = _FolderTagHarness(
      isPremium: false,
      isPremiumAvailable: false,
    );
    await pumpView(tester, harness);

    expect(find.byKey(const ValueKey('tags-title')), findsNothing);
    expect(find.byKey(const ValueKey('folder-tags')), findsNothing);
    expect(find.byType(SettingsSwitchRow), findsNothing);
  });

  testWidgets('failed entitlement probe fails closed and hides folder tags', (
    tester,
  ) async {
    final harness = _FolderTagHarness(
      isPremium: false,
      isPremiumAvailable: true,
    )..optionResponse = (_) async => throw StateError('option unavailable');
    await pumpView(tester, harness);

    expect(find.byKey(const ValueKey('tags-title')), findsNothing);
    expect(find.byType(SettingsSwitchRow), findsNothing);
  });

  testWidgets(
    'non-Premium row is one actionable semantics and keyboard surface',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final harness = _FolderTagHarness(
        isPremium: false,
        isPremiumAvailable: true,
      );
      await pumpView(tester, harness);

      final lock = find.byKey(const ValueKey('folder-tags-premium-lock'));
      expect(lock, findsOneWidget);
      expect(
        tester
            .widget<SettingsSwitchRow>(find.byType(SettingsSwitchRow))
            .enabled,
        isFalse,
      );
      final semanticsData = tester.getSemantics(lock).getSemanticsData();
      expect(
        semanticsData.label,
        contains(AppStrings.t(AppStringKeys.profileToolsPremiumRequired)),
      );
      expect(semanticsData.hasAction(SemanticsAction.tap), isTrue);
      expect(
        find.bySemanticsLabel(
          RegExp(AppStrings.t(AppStringKeys.profileToolsPremiumRequired)),
        ),
        findsOneWidget,
      );

      await tester.tap(lock);
      await tester.pump();
      final surface = tester.widget<AppInteractiveSurface>(lock);
      surface.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);

      expect(harness.lockedActivations, 3);
      expect(harness.toggleRequests, isEmpty);
      semantics.dispose();
    },
  );

  testWidgets('Premium accounts retain the working folder-tag toggle', (
    tester,
  ) async {
    final harness = _FolderTagHarness(
      isPremium: true,
      isPremiumAvailable: true,
    );
    await pumpView(tester, harness);

    expect(
      find.byKey(const ValueKey('folder-tags-premium-lock')),
      findsNothing,
    );
    final row = find.byType(SettingsSwitchRow);
    expect(tester.widget<SettingsSwitchRow>(row).enabled, isTrue);

    await tester.tap(row);
    await tester.pump();

    expect(harness.toggleRequests, hasLength(1));
    expect(harness.toggleRequests.single['are_tags_enabled'], isTrue);
  });

  testWidgets('current Premium remains enabled when upgrades are unavailable', (
    tester,
  ) async {
    final harness = _FolderTagHarness(
      isPremium: true,
      isPremiumAvailable: false,
    );
    await pumpView(tester, harness);

    final row = find.byType(SettingsSwitchRow);
    expect(tester.widget<SettingsSwitchRow>(row).enabled, isTrue);

    final optionRequestCount = harness.optionRequests.length;
    harness.optionResponse = (_) async => throw StateError('probe failed');
    harness.updates.add(_optionUpdate('is_premium_available', false));
    await tester.pumpAndSettle();

    expect(tester.widget<SettingsSwitchRow>(row).enabled, isTrue);
    expect(harness.optionRequests, hasLength(optionRequestCount));
    expect(
      find.byKey(const ValueKey('folder-tags-premium-lock')),
      findsNothing,
    );
  });

  testWidgets('Premium folder-tag toggle still rolls back on TDLib failure', (
    tester,
  ) async {
    final harness = _FolderTagHarness(isPremium: true, isPremiumAvailable: true)
      ..toggleResponse = () async => throw StateError('toggle failed');
    await pumpView(tester, harness);

    final row = find.byType(SettingsSwitchRow);
    expect(tester.widget<SettingsSwitchRow>(row).value, isFalse);

    await tester.tap(row);
    await tester.pump();

    expect(tester.widget<SettingsSwitchRow>(row).value, isFalse);
    expect(harness.toggleRequests, hasLength(1));
  });

  testWidgets('live Premium downgrade blocks a toggle before probe returns', (
    tester,
  ) async {
    final harness = _FolderTagHarness(
      isPremium: true,
      isPremiumAvailable: true,
    );
    await pumpView(tester, harness);
    final pending = _PendingOptions();
    harness.optionResponse = pending.call;

    harness.updates.add(_optionUpdate('is_premium', false));
    await tester.pump();

    expect(find.byKey(const ValueKey('tags-title')), findsNothing);
    expect(harness.toggleRequests, isEmpty);

    pending.complete(isPremium: false, isPremiumAvailable: true);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('folder-tags-premium-lock')),
      findsOneWidget,
    );
  });

  testWidgets('live Premium upgrade enables folder tags', (tester) async {
    final harness = _FolderTagHarness(
      isPremium: false,
      isPremiumAvailable: true,
    );
    await pumpView(tester, harness);

    final optionRequestCount = harness.optionRequests.length;
    harness.optionResponse = (_) async => throw StateError('probe failed');
    harness.updates.add(_optionUpdate('is_premium', true));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('folder-tags-premium-lock')),
      findsNothing,
    );
    expect(
      tester.widget<SettingsSwitchRow>(find.byType(SettingsSwitchRow)).enabled,
      isTrue,
    );
    expect(harness.optionRequests, hasLength(optionRequestCount));
  });

  testWidgets('live Premium availability shows and immediately hides tags', (
    tester,
  ) async {
    final harness = _FolderTagHarness(
      isPremium: false,
      isPremiumAvailable: false,
    );
    await pumpView(tester, harness);

    harness.isPremiumAvailable = true;
    harness.updates.add(_optionUpdate('is_premium_available', true));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('folder-tags-premium-lock')),
      findsOneWidget,
    );

    final pending = _PendingOptions();
    harness.optionResponse = pending.call;
    harness.updates.add(_optionUpdate('is_premium_available', false));
    await tester.pump();
    expect(find.byKey(const ValueKey('tags-title')), findsNothing);
    expect(harness.toggleRequests, isEmpty);

    pending.complete(isPremium: false, isPremiumAvailable: false);
    await tester.pumpAndSettle();
  });
}

class _FolderTagHarness {
  _FolderTagHarness({
    required this.isPremium,
    required this.isPremiumAvailable,
  });

  bool isPremium;
  bool isPremiumAvailable;
  final updates = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final requests = <Map<String, dynamic>>[];
  Future<Map<String, dynamic>> Function(String name)? optionResponse;
  Future<Map<String, dynamic>> Function()? toggleResponse;
  int lockedActivations = 0;

  Iterable<Map<String, dynamic>> get toggleRequests =>
      requests.where((request) => request['@type'] == 'toggleChatFolderTags');

  List<Map<String, dynamic>> get optionRequests =>
      requests.where((request) => request['@type'] == 'getOption').toList();

  void activateLocked() => lockedActivations++;

  Future<Map<String, dynamic>> query(Map<String, dynamic> request) async {
    requests.add(request);
    return switch (request['@type']) {
      'getRecommendedChatFolders' => {
        '@type': 'recommendedChatFolders',
        'chat_folders': <Object>[],
      },
      'getOption' =>
        optionResponse != null
            ? await optionResponse!(request['name'] as String)
            : {
                '@type': 'optionValueBoolean',
                'value': request['name'] == 'is_premium'
                    ? isPremium
                    : isPremiumAvailable,
              },
      'toggleChatFolderTags' =>
        toggleResponse == null ? {'@type': 'ok'} : await toggleResponse!(),
      _ => {'@type': 'ok'},
    };
  }

  Future<void> dispose() => updates.close();
}

class _PendingOptions {
  final premium = Completer<Map<String, dynamic>>();
  final availability = Completer<Map<String, dynamic>>();

  Future<Map<String, dynamic>> call(String name) =>
      name == 'is_premium' ? premium.future : availability.future;

  void complete({required bool isPremium, required bool isPremiumAvailable}) {
    premium.complete({'@type': 'optionValueBoolean', 'value': isPremium});
    availability.complete({
      '@type': 'optionValueBoolean',
      'value': isPremiumAvailable,
    });
  }
}

Map<String, dynamic> _optionUpdate(String name, bool value) => {
  '@type': 'updateOption',
  'name': name,
  'value': {'@type': 'optionValueBoolean', 'value': value},
};
