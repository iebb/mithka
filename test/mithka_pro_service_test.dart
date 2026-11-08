import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/pro/mithka_pro_service.dart';

void main() {
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
