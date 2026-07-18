import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../tdlib/td_client.dart';

class PremiumAuthProduct {
  const PremiumAuthProduct({
    required this.currency,
    required this.amount,
    required this.displayPrice,
  });

  final String currency;
  final int amount;
  final String displayPrice;
}

class PremiumAuthPurchaseException implements Exception {
  const PremiumAuthPurchaseException(this.code, [this.message]);

  final String code;
  final String? message;

  bool get isCancelled => code == 'purchase_cancelled';

  @override
  String toString() => message == null ? code : '$code: $message';
}

class PremiumAuthPurchaseService {
  const PremiumAuthPurchaseService();

  static const _channel = MethodChannel('mithka/premium_auth_purchase');

  Future<bool> isSupported() async {
    if (!Platform.isIOS) return false;
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<PremiumAuthProduct> product(String productId) async {
    final response = await _invoke('productInfo', productId: productId);
    return PremiumAuthProduct(
      currency: response['currency'] as String? ?? '',
      amount: (response['amount'] as num?)?.toInt() ?? 0,
      displayPrice: response['displayPrice'] as String? ?? '',
    );
  }

  Future<void> purchaseAndAuthorize({
    required int clientId,
    required String productId,
    required int premiumDayCount,
    bool restore = false,
  }) async {
    if (!Platform.isIOS) {
      throw const PremiumAuthPurchaseException(
        'purchase_unavailable',
        'Pre-authorization Premium purchases need a platform billing adapter.',
      );
    }
    final productInfo = await product(productId);
    await TdClient.shared.queryTo(
      checkRequest(
        premiumDayCount: premiumDayCount,
        currency: productInfo.currency,
        amount: productInfo.amount,
      ),
      clientId,
    );
    final purchase = await _invoke(
      'purchase',
      productId: productId,
      restore: restore,
    );
    final receipt = purchase['receipt'];
    if (receipt is! Uint8List || receipt.isEmpty) {
      throw const PremiumAuthPurchaseException(
        'purchase_invalid',
        'App Store receipt is missing.',
      );
    }
    await TdClient.shared.queryTo(
      transactionRequest(
        receipt: receipt,
        restore: restore,
        premiumDayCount: premiumDayCount,
        currency: productInfo.currency,
        amount: productInfo.amount,
      ),
      clientId,
    );
  }

  @visibleForTesting
  static Map<String, dynamic> checkRequest({
    required int premiumDayCount,
    required String currency,
    required int amount,
  }) => {
    '@type': 'checkAuthenticationPremiumPurchase',
    'premium_day_count': premiumDayCount,
    'currency': currency,
    'amount': amount,
  };

  @visibleForTesting
  static Map<String, dynamic> transactionRequest({
    required Uint8List receipt,
    required bool restore,
    required int premiumDayCount,
    required String currency,
    required int amount,
  }) => {
    '@type': 'setAuthenticationPremiumPurchaseTransaction',
    'transaction': {
      '@type': 'storeTransactionAppStore',
      'receipt': base64.encode(receipt),
    },
    'is_restore': restore,
    'premium_day_count': premiumDayCount,
    'currency': currency,
    'amount': amount,
  };

  Future<Map<Object?, Object?>> _invoke(
    String method, {
    required String productId,
    bool restore = false,
  }) async {
    try {
      final response = await _channel.invokeMethod<Map<Object?, Object?>>(
        method,
        {'productId': productId, 'restore': restore},
      );
      if (response == null) {
        throw const PremiumAuthPurchaseException('purchase_invalid');
      }
      return response;
    } on PlatformException catch (error) {
      throw PremiumAuthPurchaseException(error.code, error.message);
    } on MissingPluginException catch (error) {
      throw PremiumAuthPurchaseException('purchase_unavailable', error.message);
    }
  }
}
