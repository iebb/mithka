import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/chat_administrator_edit_view.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final savedStatuses = <Map<String, dynamic>>[];
  Map<String, dynamic>? existingRights;

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'setChatMemberStatus':
              savedStatuses.add(request['status'] as Map<String, dynamic>);
              return {'@type': 'ok'};
            default:
              return {'@type': 'ok'};
          }
        },
        send: (_) async {},
        updates: const Stream<Map<String, dynamic>>.empty(),
      ),
    );
  });

  tearDownAll(TdClient.shared.closeProxy);

  Future<void> pumpEditor(
    WidgetTester tester, {
    Map<String, dynamic>? status,
  }) async {
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
          home: ChatAdministratorEditView(
            chatId: 10,
            userId: 42,
            name: 'Admin',
            status: status,
            canEdit: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('saving preserves an existing welcome-messages right', (
    tester,
  ) async {
    existingRights = {
      '@type': 'chatAdministratorRights',
      'can_manage_chat': true,
      'can_send_welcome_messages': true,
    };
    savedStatuses.clear();
    await pumpEditor(
      tester,
      status: {
        '@type': 'chatMemberStatusAdministrator',
        'custom_title': '',
        'rights': existingRights,
      },
    );

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedStatuses, hasLength(1));
    final rights = savedStatuses.single['rights'] as Map<String, dynamic>;
    expect(rights['can_send_welcome_messages'], isTrue);
  });

  testWidgets('saving a fresh admin includes the welcome-messages switch', (
    tester,
  ) async {
    savedStatuses.clear();
    await pumpEditor(tester, status: {'@type': 'chatMemberStatusMember'});

    expect(find.text('Send Welcome Messages'), findsOneWidget);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(savedStatuses, hasLength(1));
    final rights = savedStatuses.single['rights'] as Map<String, dynamic>;
    expect(rights.containsKey('can_send_welcome_messages'), isTrue);
    expect(rights['can_send_welcome_messages'], isFalse);
  });
}
