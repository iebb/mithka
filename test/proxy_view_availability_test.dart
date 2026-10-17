//
//  proxy_view_availability_test.dart
//
//  The 代理 page's availability half: 测试全部 probes every saved proxy through
//  `testProxy`, each row lands on its own verdict (available with its measured
//  latency, unavailable with the failure TDLib named), and 删除不可用的代理
//  removes exactly the proxies a probe failed — never one the live link could
//  not reach. The login screen's shortcut paints the same shared status and
//  never reads a client that has not reported a link state as a failure.
//
//  Every test drives the real widgets against a fake TDLib transport, which is
//  configured exactly once for the whole process (configureProxy throws on a
//  second call), so per-test behavior is programmed through the mutable
//  answers below.
//

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/profile/profile_proxy_button.dart';
import 'package:mithka/settings/proxy_status.dart';
import 'package:mithka/settings/proxy_view.dart';
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
  String type = 'proxyTypeSocks5',
  Map<String, dynamic> credentials = const {
    'username': 'socks-user',
    'password': 'socks-secret',
  },
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
    'type': {'@type': type, ...credentials},
  },
};

void main() {
  L10nFixtures.load().install();

  final updates = StreamController<Map<String, dynamic>>.broadcast();
  var proxies = <Map<String, dynamic>>[];
  var connectionStateAnswer = <String, dynamic>{
    '@type': 'connectionStateReady',
  };

  /// False while the slot has not reported a link at all — the fresh
  /// add-account client behind the login screen before it connected.
  var answerConnectionState = true;

  /// Every `testProxy` the page sent, in order.
  final testProxyCalls = <Map<String, dynamic>>[];

  /// Every `removeProxy` the page sent, in order.
  final removeProxyIds = <int>[];

  /// Gates `testProxy` answers by port, so a test can keep probes in flight.
  final heldProbes = <int, Completer<Map<String, dynamic>>>{};
  var holdProbes = false;

  /// Ports whose probe fails the way the pinned TDLib reports a dead proxy:
  /// a 400 whose message names the reason.
  final failingPorts = <int>{};

  setUpAll(() {
    TdClient.shared.configureProxy(
      TdClientProxyTransport(
        accountSlot: 0,
        query: (request) async {
          switch (request['@type']) {
            case 'getProxies':
              return {
                '@type': 'proxies',
                'total_count': proxies.length,
                'proxies': proxies,
              };
            case 'getConnectionState':
              if (!answerConnectionState) {
                // TDLib queues a pre-parameters read with no reply at all.
                throw StateError('no reply yet');
              }
              return connectionStateAnswer;
            case 'testProxy':
              testProxyCalls.add(Map<String, dynamic>.of(request));
              final details =
                  request['proxy'] as Map<String, dynamic>? ?? const {};
              final port = details['port'] as int? ?? 0;
              if (holdProbes) {
                final completer = Completer<Map<String, dynamic>>();
                heldProbes[port] = completer;
                await completer.future;
              }
              if (failingPorts.contains(port)) {
                return {
                  '@type': 'error',
                  'code': 400,
                  'message': 'Timeout expired',
                };
              }
              return {'@type': 'ok'};
            case 'removeProxy':
              final id = request['proxy_id'] as int? ?? 0;
              removeProxyIds.add(id);
              // The list really shrinks, so the re-read after a removal
              // answers what the page would see from TDLib.
              proxies = [
                for (final proxy in proxies)
                  if ((proxy['id'] as int? ?? 0) != id) proxy,
              ];
              return {'@type': 'ok'};
            default:
              return {'@type': 'ok'};
          }
        },
        send: (_) async {},
        updates: updates.stream,
      ),
    );
  });

  tearDownAll(() async {
    await TdClient.shared.closeProxy();
    await updates.close();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    proxies = <Map<String, dynamic>>[];
    connectionStateAnswer = {'@type': 'connectionStateReady'};
    answerConnectionState = true;
    testProxyCalls.clear();
    removeProxyIds.clear();
    heldProbes.clear();
    holdProbes = false;
    failingPorts.clear();
    // The singleton outlives a test; the next one drives its own answers.
    ProxyStatusController.shared.debugReset();
  });

  /// Lets every fake answer and the setState that follows it land. Explicit
  /// pumps, not pumpAndSettle: every in-flight state paints a repeating
  /// spinner, which never settles.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> pumpView(WidgetTester tester) async {
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
          home: const ProxyView(),
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets(
    'a saved list renders before any probe, and nothing is called a failure',
    (tester) async {
      proxies = [
        _savedProxy(id: 11, server: 'untested.invalid', port: 1080),
        _savedProxy(
          id: 12,
          server: 'enabled.invalid',
          port: 443,
          enabled: true,
          type: 'proxyTypeMtproto',
          credentials: const {'secret': 'mtproto-secret'},
        ),
      ];
      // The slot behind the login screen has no link state to report yet.
      answerConnectionState = false;
      ProxyStatusController.shared.ensureTracking();
      await ProxyStatusController.shared.refresh();
      await pumpView(tester);

      // The page reads the slot's own list: what is saved is on screen.
      expect(find.text('untested.invalid:1080'), findsOneWidget);
      expect(find.text('enabled.invalid:443'), findsOneWidget);
      // The unprobed row claims nothing; the enabled one follows the link,
      // which has no verdict yet either.
      expect(find.byKey(const ValueKey('proxy-check-unknown')), findsOneWidget);
      expect(find.byKey(const ValueKey('proxy-check-testing')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('proxy-check-unavailable')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('proxy-delete-unavailable')),
        findsNothing,
      );
      expect(testProxyCalls, isEmpty);
      expect(find.byKey(const ValueKey('proxy-test-all')), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'test-all probes every saved proxy once and each row lands on its verdict',
    (tester) async {
      proxies = [
        _savedProxy(id: 21, server: 'good-a.invalid', port: 1081),
        _savedProxy(id: 22, server: 'dead.invalid', port: 1082),
        _savedProxy(
          id: 23,
          server: 'good-b.invalid',
          port: 1083,
          type: 'proxyTypeHttp',
          credentials: const {'username': 'http-user', 'password': 'http-pass'},
        ),
      ];
      failingPorts.add(1082);
      holdProbes = true;
      await pumpView(tester);

      await tester.tap(find.byKey(const ValueKey('proxy-test-all')));
      await settle(tester);

      // One testProxy per configured proxy, carrying that proxy's own type and
      // the page's own probe timeout.
      expect(testProxyCalls, hasLength(3));
      expect(
        testProxyCalls
            .map((call) => (call['proxy'] as Map<String, dynamic>)['server'])
            .toSet(),
        {'good-a.invalid', 'dead.invalid', 'good-b.invalid'},
      );
      for (final call in testProxyCalls) {
        expect(call['dc_id'], kProxyTestDcId);
        expect(call['timeout'], 5.0);
      }
      final http = testProxyCalls.firstWhere(
        (call) =>
            (call['proxy'] as Map<String, dynamic>)['server'] ==
            'good-b.invalid',
      );
      expect((http['proxy'] as Map<String, dynamic>)['type'], {
        '@type': 'proxyTypeHttp',
        'username': 'http-user',
        'password': 'http-pass',
      });
      expect(
        find.byKey(const ValueKey('proxy-check-testing')),
        findsNWidgets(3),
      );

      // Answers land in whatever order TDLib gives them; each row paints its
      // own.
      heldProbes[1082]!.complete({'@type': 'ok'});
      heldProbes[1081]!.complete({'@type': 'ok'});
      heldProbes[1083]!.complete({'@type': 'ok'});
      await settle(tester);

      expect(find.byKey(const ValueKey('proxy-check-testing')), findsNothing);
      expect(
        find.byKey(const ValueKey('proxy-check-available')),
        findsNWidgets(2),
      );
      expect(
        find.byKey(const ValueKey('proxy-check-unavailable')),
        findsOneWidget,
      );
      // Available rows report the measured round trip.
      expect(find.textContaining(' ms'), findsNWidgets(2));
      // The failed row says what TDLib said.
      expect(find.textContaining('Timeout expired'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a second test-all while probes are in flight issues no second testProxy',
    (tester) async {
      proxies = [
        _savedProxy(id: 26, server: 'one.invalid', port: 1091),
        _savedProxy(id: 27, server: 'two.invalid', port: 1092),
      ];
      holdProbes = true;
      await pumpView(tester);

      await tester.tap(find.byKey(const ValueKey('proxy-test-all')));
      await settle(tester);
      expect(testProxyCalls, hasLength(2));

      // The header action is a spinner while probes are in flight, so a second
      // press cannot stack on the first.
      await tester.tap(find.byKey(const ValueKey('proxy-test-all')));
      await settle(tester);
      expect(testProxyCalls, hasLength(2));

      heldProbes[1091]!.complete({'@type': 'ok'});
      heldProbes[1092]!.complete({'@type': 'ok'});
      await settle(tester);

      // Once every verdict landed the action is free to probe again.
      await tester.tap(find.byKey(const ValueKey('proxy-test-all')));
      await settle(tester);
      expect(testProxyCalls, hasLength(4));

      heldProbes[1091]!.complete({'@type': 'ok'});
      heldProbes[1092]!.complete({'@type': 'ok'});
      await settle(tester);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'delete-unavailable removes exactly the proxies whose probe failed',
    (tester) async {
      proxies = [
        _savedProxy(id: 31, server: 'good.invalid', port: 1101),
        _savedProxy(id: 32, server: 'dead.invalid', port: 1102),
        _savedProxy(id: 33, server: 'also-good.invalid', port: 1103),
      ];
      failingPorts.add(1102);
      await pumpView(tester);

      // Nothing failed yet, so the destructive action is not on screen.
      expect(
        find.byKey(const ValueKey('proxy-delete-unavailable')),
        findsNothing,
      );

      await tester.tap(find.byKey(const ValueKey('proxy-test-all')));
      await settle(tester);
      expect(
        find.byKey(const ValueKey('proxy-check-unavailable')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('proxy-delete-unavailable')));
      await settle(tester);
      // Destructive, so it confirms first.
      expect(find.byType(CupertinoAlertDialog), findsOneWidget);
      expect(
        find.text(AppStrings.t(AppStringKeys.proxyDeleteUnavailableMessage)),
        findsOneWidget,
      );
      await tester.tap(find.text(AppStrings.t(AppStringKeys.chatDelete)));
      await settle(tester);

      expect(removeProxyIds, [32]);
      expect(find.text('dead.invalid:1102'), findsNothing);
      expect(find.text('good.invalid:1101'), findsOneWidget);
      expect(find.text('also-good.invalid:1103'), findsOneWidget);
      // Nothing is left to delete, so the action is gone again.
      expect(
        find.byKey(const ValueKey('proxy-delete-unavailable')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'a link-level no-network reading never conjures the bulk delete',
    (tester) async {
      proxies = [
        _savedProxy(
          id: 41,
          server: 'offline.invalid',
          port: 1121,
          enabled: true,
        ),
      ];
      connectionStateAnswer = {'@type': 'connectionStateWaitingForNetwork'};
      ProxyStatusController.shared.ensureTracking();
      await ProxyStatusController.shared.refresh();
      await pumpView(tester);

      // The chip follows the live link...
      expect(
        find.byKey(const ValueKey('proxy-check-unavailable')),
        findsOneWidget,
      );
      // ...but only a probe's own verdict arms the destructive action.
      expect(
        find.byKey(const ValueKey('proxy-delete-unavailable')),
        findsNothing,
      );
      expect(testProxyCalls, isEmpty);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets(
    'the shortcut shares the sidebar status and never fails without a reading',
    (tester) async {
      proxies = [
        _savedProxy(id: 51, server: 'login.invalid', port: 1131, enabled: true),
      ];
      // The slot has saved proxies but has not reported a link state.
      answerConnectionState = false;
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
            home: Scaffold(
              body: Center(child: ProfileProxyButton(onTap: () {})),
            ),
          ),
        ),
      );
      await ProxyStatusController.shared.refresh();
      await settle(tester);

      // The same controller as the sidebar: a not-yet-connected client reads as
      // still being reached, not as a dead proxy.
      expect(
        find.byKey(const ValueKey('profile-proxy-badge-connecting')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('profile-proxy-badge-unreachable')),
        findsNothing,
      );
      expect(
        find.byTooltip(
          '${AppStrings.t(AppStringKeys.proxyTitle)} · '
          '${AppStrings.t(AppStringKeys.proxyStatusConnecting)}',
        ),
        findsOneWidget,
      );

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
