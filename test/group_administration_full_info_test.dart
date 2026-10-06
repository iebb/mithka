import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/group_administration_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/edit_field_view.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // The injected transport answers full-info (and only full-info) on demand:
  // the test decides when a flood-limited response lands, without leaving the
  // shared client's default 30s timer pending at teardown.
  var fullInfoDelay = Duration.zero;
  Object? fullInfoError;

  Future<Map<String, dynamic>> transport(Map<String, dynamic> request) async {
    switch (request['@type']) {
      case 'getChat':
        return {
          '@type': 'chat',
          'id': -100123,
          'title': 'News Channel',
          'type': {
            '@type': 'chatTypeSupergroup',
            'supergroup_id': 123,
            'is_channel': true,
          },
        };
      case 'getSupergroup':
        return {'@type': 'supergroup', 'id': 123, 'is_channel': true};
      case 'getSupergroupFullInfo':
        if (fullInfoDelay > Duration.zero) {
          await Future<void>.delayed(fullInfoDelay);
        }
        if (fullInfoError != null) throw fullInfoError!;
        return {
          '@type': 'supergroupFullInfo',
          'description': 'Existing description',
          'slow_mode_delay': 60,
          'linked_chat_id': 0,
          'photo': null,
        };
      default:
        return {'@type': 'ok'};
    }
  }

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async => {'@type': 'ok'},
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });

  tearDownAll(TdClient.shared.closeProxy);

  setUp(() {
    fullInfoDelay = Duration.zero;
    fullInfoError = null;
  });

  Future<void> pumpView(WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider<ThemeController>.value(
        value: theme,
        child: MaterialApp(
          theme: ThemeData(extensions: [AppColors.light]),
          locale: const Locale('en'),
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: GroupAdvancedAdministrationView(
            chatId: -100123,
            supergroupId: 123,
            query: transport,
          ),
        ),
      ),
    );
  }

  testWidgets('description editor stays closed while full-info is pending', (
    tester,
  ) async {
    fullInfoDelay = const Duration(seconds: 10);
    await pumpView(tester);
    // The page paints from local data; only the full-info-backed rows wait.
    await tester.pump(const Duration(milliseconds: 250));

    await tester.tap(find.text('Description'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(EditFieldView), findsNothing);
    expect(find.text('Loading…'), findsWidgets);

    // After the delayed response lands, the row unlocks with the real value.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    expect(find.text('Existing description'), findsOneWidget);
    await tester.tap(find.text('Description'));
    await tester.pumpAndSettle();
    expect(find.byType(EditFieldView), findsOneWidget);
  });

  testWidgets('description editor opens with the full-info value', (
    tester,
  ) async {
    await pumpView(tester);
    await tester.pumpAndSettle();

    expect(find.text('Existing description'), findsOneWidget);
    await tester.tap(find.text('Description'));
    await tester.pumpAndSettle();
    expect(find.byType(EditFieldView), findsOneWidget);
  });

  testWidgets('failed full-info shows a retry card and recovers', (
    tester,
  ) async {
    fullInfoError = TimeoutException('flood');
    await pumpView(tester);
    await tester.pump(const Duration(milliseconds: 250));

    final retry = find.byKey(const ValueKey('group-admin-fullinfo-retry'));
    expect(retry, findsOneWidget);
    await tester.tap(find.text('Description'));
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.byType(EditFieldView), findsNothing);

    fullInfoError = null;
    await tester.scrollUntilVisible(
      retry,
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(retry);
    await tester.pumpAndSettle();
    expect(retry, findsNothing);
    expect(find.text('Existing description'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Description'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Description'));
    await tester.pumpAndSettle();
    expect(find.byType(EditFieldView), findsOneWidget);
  });
}
