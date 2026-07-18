import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/pro/mithka_pro_service.dart';

void main() {
  test('state parser accepts native fields and Play Store distribution', () {
    final state = MithkaProState.fromMap({
      'storeAvailable': true,
      'isPro': true,
      'distribution': 'play_store',
      'isLimitExempt': false,
      'expirationDateMillis': 1800000000000,
    });

    expect(state.storeAvailable, isTrue);
    expect(state.isPro, isTrue);
    expect(state.distribution, MithkaDistribution.googlePlay);
    expect(
      state.expirationDate,
      DateTime.fromMillisecondsSinceEpoch(1800000000000, isUtc: true),
    );
  });

  test('free store builds stop at four cloud session syncs', () async {
    expect(MithkaProService.freeCloudSessionSyncLimit, 4);
    for (final distribution in ['app_store', 'play_store']) {
      final service = MithkaProService(
        gateway: _FakeGateway(distribution: distribution),
      );
      await service.initialize();

      expect(service.canAddCloudSessionSync(3), isTrue);
      expect(service.canAddCloudSessionSync(4), isFalse);
      expect(service.canAddCloudSessionSync(8), isFalse);
      expect(service.canAddCloudSessionSync(4, alreadySynced: true), isTrue);
    }
  });

  test('cloud session sync limit fails closed before initialization', () {
    final service = MithkaProService(
      gateway: _FakeGateway(distribution: 'apk'),
    );

    expect(service.initialized, isFalse);
    expect(service.canAddCloudSessionSync(3), isTrue);
    expect(service.canAddCloudSessionSync(4), isFalse);
  });

  test('catalog failure does not discard a valid distribution state', () async {
    final service = MithkaProService(
      gateway: _FakeGateway(distribution: 'apk', failProducts: true),
    );

    await expectLater(service.initialize(), completes);
    expect(service.initialized, isTrue);
    expect(service.state.distribution, MithkaDistribution.apk);
    expect(service.canAddCloudSessionSync(40), isTrue);
    expect(service.products, isEmpty);
  });

  test('state failure remains non-fatal and fail closed', () async {
    final service = MithkaProService(
      gateway: _FakeGateway(distribution: 'app_store', failState: true),
    );

    await expectLater(service.initialize(), completes);
    expect(service.initialized, isFalse);
    expect(service.canAddCloudSessionSync(4), isFalse);
  });

  test('TestFlight, development, and APK distributions are exempt', () async {
    for (final distribution in ['testflight', 'development', 'apk']) {
      final service = MithkaProService(
        gateway: _FakeGateway(distribution: distribution),
      );
      await service.initialize();

      expect(service.state.isLimitExempt, isTrue);
      expect(service.canAddCloudSessionSync(50), isTrue);
    }
  });

  test('Pro has unlimited cloud session syncs in store builds', () async {
    final service = MithkaProService(
      gateway: _FakeGateway(distribution: 'play_store', pro: true),
    );
    await service.initialize();

    expect(service.canAddCloudSessionSync(1000), isTrue);
  });

  test('products and purchase use the fixed Mithka Pro identifiers', () async {
    final gateway = _FakeGateway(distribution: 'app_store');
    final service = MithkaProService(gateway: gateway);
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
    this.pro = false,
    this.failProducts = false,
    this.failState = false,
  });

  final String distribution;
  bool pro;
  final bool failProducts;
  final bool failState;
  String? purchasedProductId;
  String? managedProductId;

  @override
  Future<Map<Object?, Object?>> getState() async {
    if (failState) throw StateError('offline');
    return {
      'storeAvailable': true,
      'isPro': pro,
      'distribution': distribution,
      'isLimitExempt': false,
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
        'displayPrice': r'$4.99',
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
    managedProductId = productId;
  }

  @override
  Future<void> restore() async {
    pro = true;
  }
}
