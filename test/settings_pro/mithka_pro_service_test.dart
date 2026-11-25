import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_interactive_surface.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/pro/mithka_pro_service.dart';
import 'package:mithka/pro/mithka_pro_view.dart';
import 'package:mithka/settings/developer_mode_controller.dart';
import 'package:mithka/settings/notification_settings_view.dart';
import 'package:mithka/settings/settings_view.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final split in [false, true]) {
    for (final availability in [
      (store: true, manage: false),
      (store: false, manage: true),
      (store: false, manage: false),
    ]) {
      testWidgets('Support Us in ${split ? 'split' : 'compact'} settings: '
          'store=${availability.store}, manage=${availability.manage}', (
        tester,
      ) async {
        final gateway = _FakeGateway(
          distribution: 'app_store',
          storeAvailable: availability.store,
          canManageSubscriptions: availability.manage,
        );
        final service = MithkaProService(
          gateway: gateway,
          platform: TargetPlatform.iOS,
        );
        addTearDown(service.dispose);
        await service.initialize();
        await _pumpSettings(tester, service, split: split);

        final support = find.byKey(
          ValueKey(
            split
                ? 'settings-category-support'
                : 'settings-destination-mithka-pro',
          ),
        );
        if (!availability.store && !availability.manage) {
          expect(support, findsNothing);
          expect(find.byType(MithkaProView), findsNothing);
        } else {
          expect(support, findsOneWidget);
          expect(
            find.descendant(of: support, matching: find.text('Support us')),
            findsOneWidget,
          );
          if (split) {
            expect(find.byType(NotificationSettingsView), findsOneWidget);
            expect(
              tester.widget<AppInteractiveSurface>(support).selected,
              isFalse,
            );
          }
          await tester.tap(support);
          await tester.pumpAndSettle();
          expect(find.byType(MithkaProView), findsOneWidget);
          if (split) {
            expect(
              tester.widget<AppInteractiveSurface>(support).selected,
              isTrue,
            );
            expect(
              find.byKey(const ValueKey('settings-detail-mithka-pro')),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      });
    }
  }

  test('restricted purchases still allow Restore and Manage', () async {
    final gateway = _FakeGateway(
      distribution: 'app_store',
      canMakePayments: false,
      canManageSubscriptions: true,
    );
    final service = MithkaProService(
      gateway: gateway,
      platform: TargetPlatform.iOS,
    );
    addTearDown(service.dispose);
    await service.initialize();

    expect(service.canMakePayments, isFalse);
    expect(service.canRestore, isTrue);
    expect(await service.purchase(mithkaProYearlyProductId), isFalse);
    expect(gateway.purchasedProductId, isNull);
    expect(await service.restore(), isTrue);
    expect(gateway.restoreCalls, 1);
    expect(service.isPro, isTrue);
    await service.manage(productId: mithkaProYearlyProductId);
    expect(gateway.managedProductId, mithkaProYearlyProductId);
    expect(gateway.manageCalls, 1);
  });

  test(
    'actual store unavailable blocks payments and Restore but not account UI',
    () async {
      final gateway = _FakeGateway(
        distribution: 'play_store',
        storeAvailable: false,
        canMakePayments: true,
        canManageSubscriptions: true,
      );
      final service = MithkaProService(
        gateway: gateway,
        platform: TargetPlatform.android,
      );
      addTearDown(service.dispose);
      await service.initialize();
      expect(service.canMakePayments, isFalse);
      expect(service.canRestore, isFalse);
      expect(await service.purchase(mithkaProYearlyProductId), isFalse);
      expect(await service.restore(), isFalse);
      expect(gateway.purchasedProductId, isNull);
      expect(gateway.restoreCalls, 0);
      await service.manage();
      expect(gateway.manageCalls, 1);
      expect(service.isPro, isFalse);
    },
  );

  test('catalog failure cannot disable existing-customer actions', () async {
    final gateway = _FakeGateway(
      distribution: 'app_store',
      failProducts: true,
      canMakePayments: false,
    );
    final service = MithkaProService(
      gateway: gateway,
      platform: TargetPlatform.iOS,
    );
    addTearDown(service.dispose);
    await service.initialize();
    expect(service.products, isEmpty);
    expect(await service.restore(), isTrue);
    await service.manage();
    expect(gateway.restoreCalls, 1);
    expect(gateway.manageCalls, 1);
    expect(gateway.purchasedProductId, isNull);
  });

  test('missing bridge fails closed for all store actions', () async {
    final gateway = _FakeGateway(distribution: 'app_store', failState: true);
    final service = MithkaProService(
      gateway: gateway,
      platform: TargetPlatform.iOS,
    );
    addTearDown(service.dispose);
    await service.initialize();
    expect(await service.purchase(mithkaProYearlyProductId), isFalse);
    expect(await service.restore(), isFalse);
    await service.manage();
    expect(gateway.purchasedProductId, isNull);
    expect(gateway.restoreCalls, 0);
    expect(gateway.manageCalls, 0);
  });

  test(
    'failed state refresh never reuses old store or entitlement authority',
    () async {
      final gateway = _FakeGateway(distribution: 'play_store')..pro = true;
      final service = MithkaProService(
        gateway: gateway,
        platform: TargetPlatform.android,
      );
      addTearDown(service.dispose);
      await service.initialize();
      gateway.failState = true;
      await service.refreshEntitlement();
      expect(service.storeAvailable, isFalse);
      expect(service.isPro, isFalse);
      expect(await service.purchase(mithkaProYearlyProductId), isFalse);
      expect(await service.restore(), isFalse);
      // The provider can still open its account-management URL while offline.
      await service.manage();
      expect(gateway.manageCalls, 1);
      expect(gateway.restoreCalls, 0);
      expect(service.isPro, isFalse);
    },
  );

  test('unsupported platforms cannot call any store action', () async {
    for (final platform in [
      TargetPlatform.macOS,
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      final gateway = _FakeGateway(distribution: 'app_store');
      final service = MithkaProService(gateway: gateway, platform: platform);
      await service.initialize();
      expect(await service.purchase(mithkaProYearlyProductId), isFalse);
      expect(await service.restore(), isFalse);
      await service.manage();
      expect(gateway.manageCalls, 0);
      expect(gateway.restoreCalls, 0);
      expect(gateway.purchasedProductId, isNull);
      service.dispose();
    }
  });

  test(
    'restricted Restore serializes actions and propagates real store errors',
    () async {
      final gateway = _FakeGateway(
        distribution: 'app_store',
        canMakePayments: false,
      );
      final service = MithkaProService(
        gateway: gateway,
        platform: TargetPlatform.iOS,
      );
      addTearDown(service.dispose);
      await service.initialize();
      final wait = gateway.restoreWait = Completer<void>();
      final restore = service.restore();
      final expectation = expectLater(
        restore,
        throwsA(isA<PlatformException>()),
      );
      expect(service.working, isTrue);
      expect(await service.restore(), isFalse);
      await service.manage();
      expect(gateway.manageCalls, 0);
      wait.completeError(PlatformException(code: 'pro_restore_failed'));
      await expectation;
      expect(service.working, isFalse);
      expect(service.isPro, isFalse);
      expect(gateway.restoreCalls, 1);
    },
  );

  test(
    'source contract: StoreKit Restore and Manage ignore purchase limits',
    () {
      // App Review requires Restore even when in-app purchases are restricted.
      final source = File(
        'ios/Runner/MithkaProBridge.swift',
      ).readAsStringSync();
      final restoreAndManage = source
          .split('private func restore(')[1]
          .split('private func state(')[0];
      expect(restoreAndManage, isNot(contains('canMakePayments')));
    },
  );

  test('products and purchase use the fixed Mithka Pro identifiers', () async {
    final gateway = _FakeGateway(distribution: 'app_store');
    final service = MithkaProService(gateway: gateway);
    addTearDown(service.dispose);
    await service.initialize();

    expect(service.products.map((product) => product.id), [
      mithkaProMonthlyProductId,
      mithkaProYearlyProductId,
    ]);
    await service.purchase(mithkaProYearlyProductId);
    expect(gateway.purchasedProductId, mithkaProYearlyProductId);
    expect(service.isPro, isTrue);
    await service.manage(productId: mithkaProYearlyProductId);
    expect(gateway.managedProductId, mithkaProYearlyProductId);
  });
}

Future<void> _pumpSettings(
  WidgetTester tester,
  MithkaProService service, {
  required bool split,
}) async {
  SharedPreferences.setMockInitialValues({});
  PackageInfo.setMockInitialValues(
    appName: 'Mithka',
    packageName: 'ad.neko.mithka',
    version: '1.10.0',
    buildNumber: '1',
    buildSignature: '',
  );
  final prefs = await SharedPreferences.getInstance();
  tester.view.physicalSize = split
      ? const Size(951, 669)
      : const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeController(prefs)),
        ChangeNotifierProvider(create: (_) => DeveloperModeController(prefs)),
        ChangeNotifierProvider<MithkaProService>.value(value: service),
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
        home: const SettingsView(allowSessionLifecycleActions: false),
      ),
    ),
  );
  // The default Notifications page can be loading without a TDLib account.
  await tester.pump();
}

class _FakeGateway implements MithkaProGateway {
  _FakeGateway({
    required this.distribution,
    this.failProducts = false,
    this.failState = false,
    this.storeAvailable = true,
    this.canMakePayments,
    this.canManageSubscriptions,
  });

  final String distribution;
  bool pro = false;
  final bool failProducts;
  bool failState;
  final bool storeAvailable;
  final bool? canMakePayments;
  final bool? canManageSubscriptions;
  int restoreCalls = 0;
  int manageCalls = 0;
  Completer<void>? restoreWait;
  String? purchasedProductId;
  String? managedProductId;

  @override
  Future<Map<Object?, Object?>> getState() async {
    if (failState) throw StateError('offline');
    return {
      'storeAvailable': storeAvailable,
      if (canMakePayments != null) 'canMakePayments': canMakePayments,
      if (canManageSubscriptions != null)
        'canManageSubscriptions': canManageSubscriptions,
      'isPro': pro,
      'distribution': distribution,
      'expirationDateMillis': pro ? 1800000000000 : null,
    };
  }

  @override
  Future<List<Object?>> getProducts() async {
    if (failProducts) throw StateError('offline');
    return [
      {
        'id': mithkaProMonthlyProductId,
        'title': 'Monthly',
        'description': 'Monthly plan',
        'displayPrice': r'$0.69',
        'period': 'monthly',
      },
      {
        'id': mithkaProYearlyProductId,
        'title': 'Yearly',
        'description': 'Yearly plan',
        'displayPrice': r'$3.99',
        'period': 'yearly',
      },
      {
        'id': 'not.mithka.pro',
        'title': 'Unknown',
        'description': '',
        'displayPrice': r'$99',
        'period': 'yearly',
      },
    ];
  }

  @override
  Future<void> purchase(String productId) async {
    purchasedProductId = productId;
    pro = true;
  }

  @override
  Future<void> manage({String? productId}) async {
    manageCalls++;
    managedProductId = productId;
  }

  @override
  Future<void> restore() async {
    restoreCalls++;
    await restoreWait?.future;
    pro = true;
  }
}
