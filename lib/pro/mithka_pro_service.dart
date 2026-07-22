import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const mithkaProMonthlyProductId = 'ad.neko.mithka.pro.monthly';
const mithkaProYearlyProductId = 'ad.neko.mithka.pro.yearly';

enum MithkaDistribution {
  appStore,
  testFlight,
  googlePlay,
  apk,
  development,
  unknown;

  static MithkaDistribution parse(Object? value) {
    final normalized = value?.toString().trim().toLowerCase() ?? '';
    return switch (normalized) {
      'appstore' || 'app_store' || 'app-store' => appStore,
      'testflight' || 'test_flight' || 'test-flight' => testFlight,
      'play_store' ||
      'playstore' ||
      'play-store' ||
      'googleplay' ||
      'google_play' ||
      'google-play' ||
      'play' => googlePlay,
      'apk' || 'sideload' || 'sideloaded' => apk,
      'development' || 'debug' || 'dev' => development,
      _ => unknown,
    };
  }
}

@immutable
class MithkaProState {
  const MithkaProState({
    required this.storeAvailable,
    required this.isPro,
    required this.distribution,
    this.expirationDate,
  });

  const MithkaProState.development()
    : storeAvailable = false,
      isPro = false,
      distribution = MithkaDistribution.development,
      expirationDate = null;

  const MithkaProState.uninitialized()
    : storeAvailable = false,
      isPro = false,
      distribution = MithkaDistribution.unknown,
      expirationDate = null;

  factory MithkaProState.fromMap(Map<Object?, Object?> map) {
    final expirationMillis = _intValue(map['expirationDateMillis']);
    final distribution = MithkaDistribution.parse(map['distribution']);
    return MithkaProState(
      storeAvailable: map['storeAvailable'] == true,
      isPro: map['isPro'] == true,
      distribution: distribution,
      expirationDate: expirationMillis == null || expirationMillis <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expirationMillis, isUtc: true),
    );
  }

  final bool storeAvailable;
  final bool isPro;
  final MithkaDistribution distribution;
  final DateTime? expirationDate;

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}

@immutable
class MithkaProProduct {
  const MithkaProProduct({
    required this.id,
    required this.title,
    required this.description,
    required this.displayPrice,
    required this.period,
  });

  factory MithkaProProduct.fromMap(Map<Object?, Object?> map) =>
      MithkaProProduct(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? '',
        description: map['description']?.toString() ?? '',
        displayPrice: map['displayPrice']?.toString() ?? '',
        period: map['period']?.toString() ?? '',
      );

  final String id;
  final String title;
  final String description;
  final String displayPrice;
  final String period;

  bool get isKnownProduct =>
      id == mithkaProMonthlyProductId || id == mithkaProYearlyProductId;
}

abstract interface class MithkaProGateway {
  Future<Map<Object?, Object?>?> getState();
  Future<List<Object?>> getProducts();
  Future<void> purchase(String productId);
  Future<void> manage({String? productId});
  Future<void> restore();
}

class MethodChannelMithkaProGateway implements MithkaProGateway {
  const MethodChannelMithkaProGateway();

  static const _channel = MethodChannel('mithka/pro');

  @override
  Future<Map<Object?, Object?>?> getState() =>
      _channel.invokeMapMethod<Object?, Object?>('getState');

  @override
  Future<List<Object?>> getProducts() async =>
      await _channel.invokeListMethod<Object?>('getProducts') ?? const [];

  @override
  Future<void> purchase(String productId) => _channel.invokeMethod<void>(
    'purchase',
    <String, Object?>{'productId': productId},
  );

  @override
  Future<void> manage({String? productId}) => _channel.invokeMethod<void>(
    'manage',
    <String, Object?>{'productId': ?productId},
  );

  @override
  Future<void> restore() => _channel.invokeMethod<void>('restore');
}

class MithkaProService extends ChangeNotifier {
  MithkaProService({MithkaProGateway? gateway})
    : _gateway = gateway ?? const MethodChannelMithkaProGateway();

  static final MithkaProService shared = MithkaProService();

  final MithkaProGateway _gateway;
  MithkaProState _state = const MithkaProState.uninitialized();
  List<MithkaProProduct> _products = const [];
  bool _loading = false;
  bool _working = false;
  bool _initialized = false;

  MithkaProState get state => _state;
  List<MithkaProProduct> get products => _products;
  bool get loading => _loading;
  bool get working => _working;
  bool get initialized => _initialized;
  bool get isPro => _state.isPro;
  Future<void> initialize() async {
    if (_initialized || _loading) return;
    await refresh();
  }

  Future<void> refresh() async {
    if (_loading) return;
    _loading = true;
    notifyListeners();
    try {
      await Future.wait<void>([
        _refreshStateSafely(),
        _refreshProductsSafely(),
      ]);
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> _refreshStateSafely() async {
    try {
      final rawState = await _gateway.getState();
      if (rawState == null) return;
      _state = MithkaProState.fromMap(rawState);
      _initialized = true;
    } on MissingPluginException {
      // Stay fail-closed until the platform can identify its distribution.
    } on PlatformException {
      // Offline/store initialization errors are retried on app resume.
    } catch (_) {
      // App startup must remain non-fatal; policy stays fail-closed.
    }
  }

  Future<void> _refreshProductsSafely() async {
    try {
      final rawProducts = await _gateway.getProducts();
      _products = rawProducts
          .whereType<Map<Object?, Object?>>()
          .map(MithkaProProduct.fromMap)
          .where((product) => product.id.isNotEmpty && product.isKnownProduct)
          .toList(growable: false);
    } on MissingPluginException {
      // The paywall remains visible with configured fallback prices.
    } on PlatformException {
      // Product metadata is optional while offline.
    } catch (_) {
      // A catalog failure must not discard a valid entitlement state.
    }
  }

  Future<void> purchase(String productId) async {
    if (_working) return;
    if (productId != mithkaProMonthlyProductId &&
        productId != mithkaProYearlyProductId) {
      throw ArgumentError.value(productId, 'productId');
    }
    _working = true;
    notifyListeners();
    try {
      await _gateway.purchase(productId);
      await _reloadStateAfterTransaction();
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  Future<void> restore() async {
    if (_working) return;
    _working = true;
    notifyListeners();
    try {
      await _gateway.restore();
      await _reloadStateAfterTransaction();
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  Future<void> manage({String? productId}) async {
    if (_working) return;
    _working = true;
    notifyListeners();
    try {
      await _gateway.manage(productId: productId);
      await _reloadStateAfterTransaction();
    } finally {
      _working = false;
      notifyListeners();
    }
  }

  Future<void> _reloadStateAfterTransaction() async {
    final rawState = await _gateway.getState();
    if (rawState != null) _state = MithkaProState.fromMap(rawState);
  }
}
