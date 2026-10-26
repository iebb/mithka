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
    bool? canMakePayments,
    bool? canManageSubscriptions,
    this.expirationDate,
  }) : canMakePayments = canMakePayments ?? storeAvailable,
       canManageSubscriptions = canManageSubscriptions ?? storeAvailable;

  const MithkaProState.development()
    : storeAvailable = false,
      canMakePayments = false,
      canManageSubscriptions = false,
      isPro = false,
      distribution = MithkaDistribution.development,
      expirationDate = null;

  const MithkaProState.uninitialized()
    : storeAvailable = false,
      canMakePayments = false,
      canManageSubscriptions = false,
      isPro = false,
      distribution = MithkaDistribution.unknown,
      expirationDate = null;

  factory MithkaProState.fromMap(Map<Object?, Object?> map) {
    final expirationMillis = _intValue(map['expirationDateMillis']);
    final distribution = MithkaDistribution.parse(map['distribution']);
    return MithkaProState(
      storeAvailable: map['storeAvailable'] == true,
      canMakePayments: map.containsKey('canMakePayments')
          ? map['canMakePayments'] == true
          : null,
      canManageSubscriptions: map.containsKey('canManageSubscriptions')
          ? map['canManageSubscriptions'] == true
          : null,
      isPro: map['isPro'] == true,
      distribution: distribution,
      expirationDate: expirationMillis == null || expirationMillis <= 0
          ? null
          : DateTime.fromMillisecondsSinceEpoch(expirationMillis, isUtc: true),
    );
  }

  final bool storeAvailable;
  final bool canMakePayments;
  final bool canManageSubscriptions;
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

/// Optional invalidation source. Events never grant access by themselves.
abstract interface class MithkaProEntitlementEvents {
  void setEntitlementChangedHandler(VoidCallback? handler);
}

class MethodChannelMithkaProGateway
    implements MithkaProGateway, MithkaProEntitlementEvents {
  const MethodChannelMithkaProGateway();

  static const _channel = MethodChannel('mithka/pro');

  @override
  void setEntitlementChangedHandler(VoidCallback? handler) {
    _channel.setMethodCallHandler(
      handler == null
          ? null
          : (call) async {
              if (call.method == 'entitlementChanged') handler();
            },
    );
  }

  @override
  Future<Map<Object?, Object?>?> getState() =>
      _channel.invokeMapMethod<Object?, Object?>('getState');

  @override
  Future<List<Object?>> getProducts() async =>
      await _channel.invokeListMethod<Object?>('getProducts') ?? const [];

  @override
  Future<void> purchase(String productId) async {
    final result = await _channel.invokeMethod<Object?>(
      'purchase',
      <String, Object?>{'productId': productId},
    );
    // Google Play returns an explicit result; StoreKit reports these as errors.
    if (result is Map) {
      final status = result['status'];
      if (status == 'pending' || status == 'cancelled') {
        throw PlatformException(code: 'purchase_$status');
      }
    }
  }

  @override
  Future<void> manage({String? productId}) => _channel.invokeMethod<void>(
    'manage',
    <String, Object?>{'productId': ?productId},
  );

  @override
  Future<void> restore() => _channel.invokeMethod<void>('restore');
}

bool supporterIconsAvailableForPlatform(
  TargetPlatform platform, {
  bool isWeb = kIsWeb,
}) =>
    !isWeb &&
    (platform == TargetPlatform.iOS || platform == TargetPlatform.android);

class MithkaProService extends ChangeNotifier {
  MithkaProService({MithkaProGateway? gateway, TargetPlatform? platform})
    : _gateway = gateway ?? const MethodChannelMithkaProGateway(),
      _platform = platform ?? defaultTargetPlatform {
    final events = _gateway;
    if (events is MithkaProEntitlementEvents) {
      (events as MithkaProEntitlementEvents).setEntitlementChangedHandler(
        _entitlementChanged,
      );
    }
  }

  static final MithkaProService shared = MithkaProService();

  final MithkaProGateway _gateway;
  final TargetPlatform _platform;
  MithkaProState _state = const MithkaProState.uninitialized();
  List<MithkaProProduct> _products = const [];
  Future<void>? _refreshFuture;
  bool _working = false;
  bool _initialized = false;
  bool _verified = false;
  bool _disposed = false;
  int _stateRequest = 0;
  Timer? _expiryTimer;

  MithkaProState get state => _state;
  List<MithkaProProduct> get products => _products;
  bool get loading => _refreshFuture != null;
  bool get working => _working;
  bool get initialized => _initialized;
  bool get mobileSupporterAvailable =>
      supporterIconsAvailableForPlatform(_platform);
  bool get isAppleStore => _platform == TargetPlatform.iOS;
  bool get storeAvailable =>
      mobileSupporterAvailable &&
      !_disposed &&
      _verified &&
      _state.storeAvailable;
  bool get canMakePayments => storeAvailable && _state.canMakePayments;
  bool get canRestore => storeAvailable;
  // Management can open the provider's account UI even when billing is offline.
  // It grants no entitlement; native code still checks for a scene/URL handler.
  bool get canManageSubscriptions =>
      mobileSupporterAvailable && !_disposed && _state.canManageSubscriptions;
  bool get isPro =>
      mobileSupporterAvailable &&
      _verified &&
      _state.isPro &&
      (_state.expirationDate == null ||
          _state.expirationDate!.isAfter(DateTime.now()));

  MithkaProProduct? product(String id) {
    for (final product in _products) {
      if (product.id == id && product.displayPrice.trim().isNotEmpty) {
        return product;
      }
    }
    return null;
  }

  Future<void> initialize() async {
    if (!_initialized) await refresh();
  }

  Future<void> refresh() {
    final pending = _refreshFuture;
    if (pending != null) return pending;
    if (!mobileSupporterAvailable) return Future<void>.value();
    final future = _refresh();
    _refreshFuture = future;
    _notify();
    return future;
  }

  Future<void> _refresh() async {
    try {
      await Future.wait<void>([
        refreshEntitlement().then((_) {}),
        _refreshProductsSafely(),
      ]);
    } finally {
      _refreshFuture = null;
      _notify();
    }
  }

  /// Invalidate immediately on backgrounding or native transaction changes.
  /// A later result from an older request must never reinstate stale access.
  void invalidateEntitlement() {
    _stateRequest++;
    _verified = false;
    _expiryTimer?.cancel();
    _notify();
  }

  void _entitlementChanged() {
    invalidateEntitlement();
    unawaited(refreshEntitlement());
  }

  /// Always asks the current native provider, never a persisted Pro flag.
  /// This is also the central controller's authorization boundary.
  Future<bool> refreshEntitlement() async {
    if (!mobileSupporterAvailable) return false;
    final request = ++_stateRequest;
    _verified = false;
    try {
      final raw = await _gateway.getState();
      if (_disposed || request != _stateRequest) return false;
      if (raw == null) throw StateError('Entitlement unavailable');
      _state = MithkaProState.fromMap(raw);
      _initialized = true;
      _verified = true;
      _expiryTimer?.cancel();
      final expiration = _state.expirationDate;
      if (_state.isPro &&
          expiration != null &&
          expiration.isAfter(DateTime.now())) {
        _expiryTimer = Timer(expiration.difference(DateTime.now()), () {
          if (!_disposed) invalidateEntitlement();
        });
      }
      return isPro;
    } catch (_) {
      if (request == _stateRequest) _verified = false;
      return false;
    } finally {
      _notify();
    }
  }

  Future<void> _refreshProductsSafely() async {
    try {
      final raw = await _gateway.getProducts();
      if (_disposed) return;
      _products = raw
          .whereType<Map<Object?, Object?>>()
          .map(MithkaProProduct.fromMap)
          .where(
            (product) =>
                product.isKnownProduct &&
                product.displayPrice.trim().isNotEmpty,
          )
          .toList(growable: false);
    } catch (_) {
      // Do not advertise stale or invented prices after a catalog failure.
      _products = const [];
    }
  }

  Future<bool> purchase(String productId) async {
    if (productId != mithkaProMonthlyProductId &&
        productId != mithkaProYearlyProductId) {
      throw ArgumentError.value(productId, 'productId');
    }
    if (_working || !canMakePayments || product(productId) == null) {
      return false;
    }
    return _transaction(() => _gateway.purchase(productId));
  }

  Future<bool> restore() async {
    if (_working || !canRestore) return false;
    return _transaction(_gateway.restore);
  }

  Future<bool> _transaction(Future<void> Function() action) async {
    _working = true;
    _notify();
    try {
      await action();
      await refreshEntitlement();
      // A transaction update can supersede this request and finish first.
      // Reconcile against the newest verified snapshot, not the older
      // request's (correctly rejected) result.
      return isPro;
    } finally {
      _working = false;
      _notify();
    }
  }

  Future<void> manage({String? productId}) async {
    if (_working || !canManageSubscriptions) return;
    await _transaction(() => _gateway.manage(productId: productId));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _stateRequest++;
    _expiryTimer?.cancel();
    final events = _gateway;
    if (events is MithkaProEntitlementEvents) {
      (events as MithkaProEntitlementEvents).setEntitlementChangedHandler(null);
    }
    super.dispose();
  }
}
