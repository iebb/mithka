//
//  proxy_view_owner_test.dart
//
//  The 代理 page's destructive boundary across accounts. Proxy ids are
//  account-scoped, so the same id can name a different row in another account:
//  a confirmation that outlives an account switch must not remove the new
//  foreground account's row, and deleting an old account's enabled row must
//  not disable the new foreground account's proxy state.
//
//  Every test runs the page against a real `TdClient` registry built from
//  synthetic bindings (`addSlot` / `setActive` / `queryTo`), not a hand-written
//  model of account routing, and scripts TDLib through `queryOverride`.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/settings/proxy_config.dart';
import 'package:mithka/settings/proxy_status.dart';
import 'package:mithka/settings/proxy_view.dart';
import 'package:mithka/tdlib/td_bindings.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/l10n_fixtures.dart';

/// One saved proxy, the shape `getProxies` answers with.
Map<String, dynamic> _savedProxy({
  required int id,
  required String server,
  required int port,
  bool enabled = false,
}) => {
  '@type': 'addedProxy',
  'id': id,
  'last_used_date': 0,
  'is_enabled': enabled,
  'comment': '',
  'proxy': {
    '@type': 'proxy',
    'server': server,
    'port': port,
    'type': {
      '@type': 'proxyTypeSocks5',
      'username': 'socks-user',
      'password': 'socks-secret',
    },
  },
};

/// Stands in for tdjson: allocates the exact client ids the scenario names and
/// answers the close handshake so slot cleanup never waits on the real timeout.
class _FakeBindings implements TdBindings {
  _FakeBindings(this._client, this._clientIds);

  final TdClient _client;
  final List<int> _clientIds;

  @override
  int createClientId() => _clientIds.removeAt(0);

  @override
  void send(int clientId, String request) {
    final decoded = jsonDecode(request) as Map<String, dynamic>;
    if (decoded['@type'] == 'close') {
      _client.debugCompleteClientClosed(clientId);
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The two accounts behind one private registry, plus the scripted TDLib side.
final class _Harness {
  _Harness(this.client, this.prefs, this.proxies);

  final TdClient client;
  final SharedPreferences prefs;

  /// Saved proxies per concrete client id.
  final Map<int, List<Map<String, dynamic>>> proxies;

  /// Every request the page sent, with the client that really served it.
  final List<(int, Map<String, dynamic>)> requests = [];

  /// Ports whose `testProxy` fails the way TDLib reports a dead proxy.
  final Set<int> failingPorts = {};

  /// `removeProxy` ids whose answer the test holds open.
  final Map<int, Completer<void>> heldRemovals = {};

  late int betaSlot; // slot 0, client 100
  late int alphaSlot; // slot 1, client 1

  List<Map<String, dynamic>> listFor(int clientId) =>
      proxies[clientId] ?? const [];

  List<Map<String, dynamic>> requestsTo(int clientId, String type) => [
    for (final (id, request) in requests)
      if (id == clientId && request['@type'] == type) request,
  ];

  List<(int, int)> get removeCalls => [
    for (final (id, request) in requests)
      if (request['@type'] == 'removeProxy') (id, request['proxy_id'] as int),
  ];

  Future<Map<String, dynamic>> respond(
    Map<String, dynamic> request,
    int clientId,
  ) async {
    requests.add((clientId, Map<String, dynamic>.of(request)));
    switch (request['@type']) {
      case 'getProxies':
        final list = listFor(clientId);
        return {
          '@type': 'proxies',
          'total_count': list.length,
          'proxies': list,
        };
      case 'testProxy':
        final details = request['proxy'] as Map<String, dynamic>? ?? const {};
        final port = details['port'] as int? ?? 0;
        if (failingPorts.contains(port)) {
          return {'@type': 'error', 'code': 400, 'message': 'Timeout expired'};
        }
        return {'@type': 'ok'};
      case 'removeProxy':
        final id = request['proxy_id'] as int? ?? 0;
        final held = heldRemovals.remove(id);
        if (held != null) await held.future;
        proxies[clientId] = [
          for (final proxy in listFor(clientId))
            if ((proxy['id'] as int? ?? 0) != id) proxy,
        ];
        return {'@type': 'ok'};
      default:
        return {'@type': 'ok'};
    }
  }
}

/// A private real registry: slot 0 is client 100 (beta), slot 1 is client 1
/// (alpha), and alpha is the foreground account the page opens on.
Future<_Harness> _prepare() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final dir = Directory.systemTemp.createTempSync('mithka_proxy_owner');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final proxies = <int, List<Map<String, dynamic>>>{100: [], 1: []};
  final client = TdClient.forTesting();
  final harness = _Harness(client, prefs, proxies);
  client.prepareForTesting(
    prefs: prefs,
    supportDir: dir.path,
    bindings: _FakeBindings(client, [100, 1, 101, 102]),
    queryOverride: harness.respond,
  );
  harness.betaSlot = client.addSlot();
  harness.alphaSlot = client.addSlot();
  client.setActive(harness.alphaSlot);
  return harness;
}

void main() {
  L10nFixtures.load().install();

  final secureValues = <String, String>{};

  setUp(() {
    ProxyStatusController.shared.debugReset();
    secureValues.clear();
    ProxyConfig.debugSecureRead = (key) async => secureValues[key];
    ProxyConfig.debugSecureWrite = (key, value) async {
      if (value == null) {
        secureValues.remove(key);
      } else {
        secureValues[key] = value;
      }
    };
  });

  tearDown(() {
    ProxyConfig.debugSecureRead = null;
    ProxyConfig.debugSecureWrite = null;
  });

  /// Lets every fake answer and the setState that follows it land. Explicit
  /// pumps, not pumpAndSettle: every in-flight state paints a repeating
  /// spinner, which never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> pumpView(WidgetTester tester, TdClient client) async {
    final theme = ThemeController(await SharedPreferences.getInstance());
    addTearDown(theme.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
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
          home: ProxyView(accounts: TdProxyViewAccounts(client)),
        ),
      ),
    );
    await settle(tester);
  }

  /// Fills the two accounts: alpha (foreground, client 1) and beta (client
  /// 100) both own a proxy id 42, with different servers.
  void seedCollidingRows(_Harness harness) {
    harness.proxies[1] = [
      _savedProxy(id: 42, server: 'alpha.invalid', port: 1141, enabled: true),
      _savedProxy(id: 43, server: 'good.invalid', port: 1142),
    ];
    harness.proxies[100] = [
      _savedProxy(id: 42, server: 'beta.invalid', port: 2141),
    ];
  }

  Future<void> failAlphaAndOpenBulkConfirm(
    WidgetTester tester,
    _Harness harness, {
    int failedCount = 1,
  }) async {
    harness.failingPorts.add(1141);
    await tester.tap(find.byKey(const ValueKey('proxy-test-all')));
    await settle(tester);
    expect(
      find.byKey(const ValueKey('proxy-check-unavailable')),
      findsNWidgets(failedCount),
    );
    await tester.tap(find.byKey(const ValueKey('proxy-delete-unavailable')));
    await settle(tester);
    expect(find.byKey(const ValueKey('app-confirm-dialog')), findsOneWidget);
    expect(find.byType(CupertinoAlertDialog), findsNothing);
  }

  Future<void> confirmDelete(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.t(AppStringKeys.chatDelete)));
    await settle(tester);
  }

  testWidgets(
    'switching accounts while the bulk confirmation is open drops the batch',
    (tester) async {
      final harness = await _prepare();
      seedCollidingRows(harness);
      await pumpView(tester, harness.client);
      await failAlphaAndOpenBulkConfirm(tester, harness);

      // The other account takes the foreground while the dialog is open. Its
      // own proxy id 42 is a different row.
      harness.client.setActive(harness.betaSlot);
      await settle(tester);
      await confirmDelete(tester);

      expect(harness.removeCalls, isEmpty);
      expect(harness.requestsTo(1, 'removeProxy'), isEmpty);
      expect(harness.requestsTo(100, 'removeProxy'), isEmpty);
      expect(harness.proxies[100]!.single['id'], 42);
      expect(harness.proxies[100]!.single['proxy']['server'], 'beta.invalid');
      expect(harness.proxies[1]!.map((proxy) => proxy['id']), [42, 43]);
      // No saved-config cleanup ran for either account.
      expect(harness.prefs.getBool('mithka.proxy.enabled'), isNull);
      expect(harness.requestsTo(1, 'disableProxy'), isEmpty);
      expect(harness.requestsTo(100, 'disableProxy'), isEmpty);
      // The page now reads the foreground account's list.
      expect(find.text('beta.invalid:2141'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'switching accounts during bulk removal drops the remaining batch',
    (tester) async {
      final harness = await _prepare();
      seedCollidingRows(harness);
      harness.failingPorts.add(1142);
      await pumpView(tester, harness.client);
      await failAlphaAndOpenBulkConfirm(tester, harness, failedCount: 2);

      final held = Completer<void>();
      harness.heldRemovals[42] = held;
      await confirmDelete(tester);

      // The first removal of the batch is still in flight when the user
      // switches. The rest of the batch belongs to the old account.
      expect(harness.removeCalls, [(1, 42)]);
      harness.client.setActive(harness.betaSlot);
      await settle(tester);
      held.complete();
      await settle(tester);

      expect(harness.removeCalls, [(1, 42)]);
      expect(harness.requestsTo(100, 'removeProxy'), isEmpty);
      expect(harness.proxies[1]!.map((proxy) => proxy['id']), [43]);
      expect(harness.proxies[100]!.single['id'], 42);
      // Deleting an enabled row must not disable the new foreground account.
      expect(harness.prefs.getBool('mithka.proxy.enabled'), isNull);
      expect(harness.requestsTo(1, 'disableProxy'), isEmpty);
      expect(harness.requestsTo(100, 'disableProxy'), isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
