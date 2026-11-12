import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/pro/mithka_pro_service.dart';
import 'package:mithka/pro/mithka_pro_view.dart';
import 'package:mithka/settings/app_icon_controller.dart';
import 'package:mithka/settings/appearance_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const iconChannel = MethodChannel('mithka/app_icon');
  final nativeChanges = <String>[];
  String currentIcon = 'default';
  bool failNative = false;
  Completer<void>? nativeWait;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    nativeChanges.clear();
    currentIcon = 'default';
    failNative = false;
    nativeWait = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(iconChannel, (call) async {
          switch (call.method) {
            case 'isSupported':
              return true;
            case 'currentIcon':
              return currentIcon;
            case 'setIcon':
              final key = (call.arguments as Map)['name'] as String;
              nativeChanges.add(key);
              await nativeWait?.future;
              if (failNative) throw PlatformException(code: 'app_icon_failed');
              currentIcon = key;
              return null;
          }
          throw MissingPluginException();
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(iconChannel, null);
  });

  // A fixed clock keeps the daily penguin away from the icons used below.
  Future<_Fixture> fixture({
    _Gateway? gateway,
    TargetPlatform platform = TargetPlatform.iOS,
    DateTime Function()? now,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final store = gateway ?? _Gateway();
    final service = MithkaProService(gateway: store, platform: platform);
    final controller = AppIconController(
      prefs,
      proService: service,
      platform: platform,
      now: now ?? () => _guitarDay,
    );
    addTearDown(controller.dispose);
    addTearDown(service.dispose);
    await service.initialize();
    await controller.initialize();
    return _Fixture(prefs, store, service, controller);
  }

  test(
    'central controller denies paid icons even without the picker UI',
    () async {
      final f = await fixture();
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      expect(nativeChanges, isEmpty);
      expect(f.controller.variant, AppIconVariant.defaultIcon);
      expect(f.prefs.getString('selected_app_icon'), isNull);
    },
  );

  test(
    'a cached active flag cannot authorize a refunded or expired selection',
    () async {
      final f = await fixture(gateway: _Gateway(pro: true));
      expect(f.service.isPro, isTrue);
      f.gateway.pro = false; // Refunded since the last screen refresh.
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      f.gateway.pro = true;
      f.gateway.expiration = DateTime.now().subtract(
        const Duration(seconds: 1),
      );
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      expect(nativeChanges, isEmpty);
      expect(f.service.isPro, isFalse);
    },
  );

  test(
    'state errors fail closed even after a previous active entitlement',
    () async {
      final f = await fixture(gateway: _Gateway(pro: true));
      f.gateway.failState = true;
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      expect(f.service.isPro, isFalse);
      expect(nativeChanges, isEmpty);
    },
  );

  test(
    'native entitlement event invalidates immediately and rejects an older query',
    () async {
      final f = await fixture(gateway: _Gateway(pro: true));
      final old = Completer<Map<Object?, Object?>>();
      f.gateway.stateQuery = () => old.future;
      final selecting = f.controller.setVariant(AppIconVariant.pilot);
      f.gateway.stateQuery = null;
      f.gateway.pro = false;
      f.gateway.entitlementChanged!();
      expect(f.service.isPro, isFalse);
      await Future<void>.delayed(Duration.zero);
      old.complete(_state(pro: true));
      expect(await selecting, isFalse);
      expect(f.service.isPro, isFalse);
      expect(nativeChanges, isEmpty);
    },
  );

  test(
    'double taps cannot race entitlement checks or report a skipped change as success',
    () async {
      final f = await fixture(gateway: _Gateway(pro: true));
      nativeWait = Completer<void>();
      final first = f.controller.setVariant(AppIconVariant.pilot);
      await Future<void>.delayed(Duration.zero);
      expect(await f.controller.setVariant(AppIconVariant.heart), isFalse);
      nativeWait!.complete();
      expect(await first, isTrue);
      expect(nativeChanges, ['pilot']);
      expect(f.controller.variant, AppIconVariant.pilot);
    },
  );

  test(
    'desktop cannot select paid icons even with an active native flag',
    () async {
      final f = await fixture(
        gateway: _Gateway(pro: true),
        platform: TargetPlatform.macOS,
      );
      expect(f.controller.availableVariants, AppIconVariant.visibleFree);
      expect(f.service.storeAvailable, isFalse);
      expect(f.service.isPro, isFalse);
      expect(await f.controller.setVariant(AppIconVariant.pilot), isFalse);
      expect(await f.controller.setVariant(AppIconVariant.blue), isTrue);
      expect(f.gateway.stateQueries, 0);
      expect(nativeChanges, ['blue']);
    },
  );

  testWidgets(
    'verified purchase returns to picker and applies exactly the tapped icon once',
    (tester) async {
      final f = await fixture(gateway: _Gateway(purchaseGrants: true));
      await _pump(tester, f);
      await _tap(tester, find.byKey(const ValueKey('app-icon-heart')));
      expect(find.byType(MithkaProView), findsOneWidget);
      expect(nativeChanges, isEmpty);
      await _tap(tester, find.text('Subscribe'));
      expect(find.byType(MithkaProView), findsNothing);
      expect(nativeChanges, ['heart']);
      expect(f.controller.variant, AppIconVariant.heart);
    },
  );

  testWidgets(
    'pending purchase never unlocks until a verified native update arrives',
    (tester) async {
      final gateway = _Gateway(purchaseError: 'pro_purchase_pending');
      final f = await fixture(gateway: gateway);
      await _pump(tester, f);
      await _tap(tester, find.byKey(const ValueKey('app-icon-pilot')));
      await _tap(tester, find.text('Subscribe'));
      expect(
        find.text(
          'Your purchase is pending. Supporter will unlock once it’s confirmed.',
        ),
        findsOneWidget,
      );
      expect(nativeChanges, isEmpty);
      expect(f.service.isPro, isFalse);
      gateway.pro = true;
      gateway.entitlementChanged!();
      await tester.pumpAndSettle();
      expect(find.byType(MithkaProView), findsNothing);
      expect(nativeChanges, ['pilot']);
    },
  );

  testWidgets(
    'unavailable catalog has retry and never advertises invented USD prices',
    (tester) async {
      final gateway = _Gateway(productsAvailable: false);
      final f = await fixture(gateway: gateway);
      await _pump(tester, f, home: MithkaProView(service: f.service));
      expect(
        find.text('Plans aren’t available right now. Try again later.'),
        findsOneWidget,
      );
      expect(find.text(r'$0.69 / month'), findsNothing);
      expect(find.text(r'$3.99 / year'), findsNothing);
      gateway.productsAvailable = true;
      await _tap(tester, find.text('Try again'));
      expect(find.text(r'$0.69 / month'), findsOneWidget);
      expect(find.text(r'$3.99 / year'), findsOneWidget);
      expect(find.textContaining('next yearly renewal'), findsNothing);
    },
  );
}

// 2026-10-29 is UTC day 20755, index 19 (guitar): clear of the penguins the
// purchase tests use.
final _guitarDay = DateTime.utc(2026, 10, 29, 12);

class _Fixture {
  _Fixture(this.prefs, this.gateway, this.service, this.controller);
  final SharedPreferences prefs;
  final _Gateway gateway;
  final MithkaProService service;
  final AppIconController controller;
}

Future<void> _pump(
  WidgetTester tester,
  _Fixture fixture, {
  Widget? home,
  bool dark = false,
  NavigatorObserver? observer,
}) async {
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController(fixture.prefs)),
        ChangeNotifierProvider.value(value: fixture.controller),
        ChangeNotifierProvider.value(value: fixture.service),
      ],
      child: MaterialApp(
        navigatorObservers: [?observer],
        theme: ThemeData(
          platform: TargetPlatform.iOS,
          brightness: dark ? Brightness.dark : Brightness.light,
          extensions: [dark ? AppColors.dark : AppColors.light],
        ),
        home: MediaQuery(
          data: MediaQueryData(
            size: const Size(800, 600),
            platformBrightness: dark ? Brightness.dark : Brightness.light,
          ),
          child: home ?? const AppIconSettingsView(),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

// The penguins sit below the standard icons and today's free penguin, past
// the list's build range in an 800x600 test view: scroll them in first.
Future<void> _reveal(WidgetTester tester, Finder target) async {
  final list = find.byKey(const ValueKey('app-icon-scroll'));
  if (target.evaluate().isEmpty && list.evaluate().isNotEmpty) {
    await tester.scrollUntilVisible(
      target,
      200,
      scrollable: find
          .descendant(of: list, matching: find.byType(Scrollable))
          .first,
    );
  }
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
}

Future<void> _tap(WidgetTester tester, Finder target) async {
  await _reveal(tester, target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

Map<Object?, Object?> _state({required bool pro, DateTime? expiration}) => {
  'storeAvailable': true,
  'isPro': pro,
  'distribution': 'app_store',
  'expirationDateMillis': expiration?.millisecondsSinceEpoch,
};

class _Gateway implements MithkaProGateway, MithkaProEntitlementEvents {
  _Gateway({
    this.pro = false,
    this.purchaseGrants = false,
    this.purchaseError,
    this.productsAvailable = true,
  });
  bool pro;
  bool failState = false;
  bool productsAvailable;
  bool purchaseGrants;
  bool restoreGrants = false;
  String? purchaseError;
  String? restoreError;
  Completer<void>? productsWait;
  Completer<void>? purchaseWait;
  Completer<void>? restoreWait;
  DateTime? expiration;
  int stateQueries = 0;
  VoidCallback? entitlementChanged;
  Future<Map<Object?, Object?>> Function()? stateQuery;

  @override
  void setEntitlementChangedHandler(VoidCallback? handler) =>
      entitlementChanged = handler;

  @override
  Future<Map<Object?, Object?>> getState() async {
    stateQueries++;
    if (failState) throw PlatformException(code: 'offline');
    if (stateQuery != null) return stateQuery!();
    return _state(pro: pro, expiration: expiration);
  }

  @override
  Future<List<Object?>> getProducts() async {
    await productsWait?.future;
    return !productsAvailable
        ? []
        : [
            {
              'id': mithkaProMonthlyProductId,
              'displayPrice': r'$0.69',
              'period': 'monthly',
            },
            {
              'id': mithkaProYearlyProductId,
              'displayPrice': r'$3.99',
              'period': 'yearly',
            },
          ];
  }

  @override
  Future<void> purchase(String productId) async {
    await purchaseWait?.future;
    if (purchaseError != null) throw PlatformException(code: purchaseError!);
    pro = purchaseGrants;
  }

  @override
  Future<void> restore() async {
    await restoreWait?.future;
    if (restoreError != null) throw PlatformException(code: restoreError!);
    pro = restoreGrants;
  }

  @override
  Future<void> manage({String? productId}) async {}
}
