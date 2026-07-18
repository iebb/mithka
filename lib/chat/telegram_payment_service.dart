import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

import '../tdlib/td_client.dart';

typedef TelegramPaymentQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

enum TelegramInvoiceStatus { paid, cancelled, failed, pending }

class TelegramInvoiceOutcome {
  const TelegramInvoiceOutcome(this.status, {this.message});

  final TelegramInvoiceStatus status;
  final String? message;
}

class TelegramPaymentException implements Exception {
  const TelegramPaymentException(this.code, [this.message]);

  final String code;
  final String? message;

  @override
  String toString() => message == null ? code : '$code: $message';
}

class TelegramPaymentService {
  TelegramPaymentService({TelegramPaymentQuery? query, http.Client? httpClient})
    : _query = query ?? TdClient.shared.query,
      _http = httpClient ?? http.Client();

  final TelegramPaymentQuery _query;
  final http.Client _http;

  Future<Map<String, dynamic>> paymentForm(Map<String, dynamic> inputInvoice) =>
      _query(paymentFormRequest(inputInvoice));

  Future<Map<String, dynamic>> validateOrder({
    required Map<String, dynamic> inputInvoice,
    Map<String, dynamic>? orderInfo,
    required bool allowSave,
  }) => _query(
    validateOrderRequest(
      inputInvoice: inputInvoice,
      orderInfo: orderInfo,
      allowSave: allowSave,
    ),
  );

  Future<Map<String, dynamic>> sendPayment({
    required Map<String, dynamic> inputInvoice,
    required int paymentFormId,
    required String orderInfoId,
    required String shippingOptionId,
    Map<String, dynamic>? credentials,
    required int tipAmount,
  }) => _query(
    sendPaymentRequest(
      inputInvoice: inputInvoice,
      paymentFormId: paymentFormId,
      orderInfoId: orderInfoId,
      shippingOptionId: shippingOptionId,
      credentials: credentials,
      tipAmount: tipAmount,
    ),
  );

  Future<bool> hasTemporaryPassword() async {
    final state = await _query({'@type': 'getTemporaryPasswordState'});
    return state['has_password'] == true;
  }

  Future<void> createTemporaryPassword(String password) async {
    await _query({
      '@type': 'createTemporaryPassword',
      'password': password,
      'valid_for': 1800,
    });
  }

  Future<Map<String, dynamic>> tokenizeStripeCard({
    required String publishableKey,
    required String number,
    required int expirationMonth,
    required int expirationYear,
    required String cvc,
    String cardholderName = '',
    String country = '',
    String postalCode = '',
  }) async {
    if (!publishableKey.startsWith('pk_')) {
      throw const TelegramPaymentException(
        'stripe_configuration_invalid',
        'The payment provider supplied an invalid Stripe key.',
      );
    }
    final response = await _http.post(
      Uri.https('api.stripe.com', '/v1/tokens'),
      headers: {'Authorization': 'Bearer $publishableKey'},
      body: {
        'card[number]': number.replaceAll(RegExp(r'\s+'), ''),
        'card[exp_month]': '$expirationMonth',
        'card[exp_year]': '$expirationYear',
        'card[cvc]': cvc,
        if (cardholderName.trim().isNotEmpty)
          'card[name]': cardholderName.trim(),
        if (country.trim().isNotEmpty)
          'card[address_country]': country.trim().toUpperCase(),
        if (postalCode.trim().isNotEmpty)
          'card[address_zip]': postalCode.trim(),
      },
    );
    Object? decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {}
    final body = decoded is Map
        ? Map<String, dynamic>.from(decoded)
        : const <String, dynamic>{};
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final error = body['error'];
      final message = error is Map ? error['message'] as String? : null;
      throw TelegramPaymentException(
        'stripe_tokenization_failed',
        message ?? 'Stripe rejected the payment details.',
      );
    }
    final id = body['id'] as String? ?? '';
    final type = body['type'] as String? ?? '';
    if (id.isEmpty || type.isEmpty) {
      throw const TelegramPaymentException(
        'stripe_tokenization_invalid',
        'Stripe returned an incomplete credential token.',
      );
    }
    return {'type': type, 'id': id};
  }

  @visibleForTesting
  static Map<String, dynamic> paymentFormRequest(
    Map<String, dynamic> inputInvoice,
  ) => {
    '@type': 'getPaymentForm',
    'input_invoice': inputInvoice,
    'theme': null,
  };

  @visibleForTesting
  static Map<String, dynamic> validateOrderRequest({
    required Map<String, dynamic> inputInvoice,
    Map<String, dynamic>? orderInfo,
    required bool allowSave,
  }) => {
    '@type': 'validateOrderInfo',
    'input_invoice': inputInvoice,
    'order_info': orderInfo,
    'allow_save': allowSave,
  };

  @visibleForTesting
  static Map<String, dynamic> sendPaymentRequest({
    required Map<String, dynamic> inputInvoice,
    required int paymentFormId,
    required String orderInfoId,
    required String shippingOptionId,
    Map<String, dynamic>? credentials,
    required int tipAmount,
  }) => {
    '@type': 'sendPaymentForm',
    'input_invoice': inputInvoice,
    'payment_form_id': paymentFormId,
    'order_info_id': orderInfoId,
    'shipping_option_id': shippingOptionId,
    'credentials': credentials,
    'tip_amount': tipAmount,
  };

  static Map<String, dynamic> savedCredentials(String id) => {
    '@type': 'inputCredentialsSaved',
    'saved_credentials_id': id,
  };

  static Map<String, dynamic> newCredentials(
    Map<String, dynamic> token, {
    required bool allowSave,
  }) => {
    '@type': 'inputCredentialsNew',
    'data': jsonEncode(token),
    'allow_save': allowSave,
  };
}

class TelegramStoreProduct {
  const TelegramStoreProduct({
    required this.productId,
    required this.currency,
    required this.amount,
    required this.label,
    this.starCount = 0,
    this.monthCount = 0,
  });

  final String productId;
  final String currency;
  final int amount;
  final String label;
  final int starCount;
  final int monthCount;
}

abstract interface class TelegramStoreBridge {
  Future<bool> isSupported();

  Future<Uint8List> purchase(String productId);

  Future<Uint8List> restoreTransactions();
}

class MethodChannelTelegramStoreBridge implements TelegramStoreBridge {
  const MethodChannelTelegramStoreBridge();

  static const _channel = MethodChannel('mithka/premium_auth_purchase');

  @override
  Future<bool> isSupported() async {
    try {
      return await _channel.invokeMethod<bool>('isSupported') ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List> purchase(String productId) async {
    final result = await _invoke('purchase', {'productId': productId});
    return _receipt(result);
  }

  @override
  Future<Uint8List> restoreTransactions() async {
    final result = await _invoke('restoreTransactions', const {});
    return _receipt(result);
  }

  Future<Map<Object?, Object?>> _invoke(
    String method,
    Map<String, Object?> arguments,
  ) async {
    try {
      final response = await _channel.invokeMethod<Map<Object?, Object?>>(
        method,
        arguments,
      );
      if (response == null) {
        throw const TelegramPaymentException('store_response_invalid');
      }
      return response;
    } on PlatformException catch (error) {
      throw TelegramPaymentException(error.code, error.message);
    } on MissingPluginException catch (error) {
      throw TelegramPaymentException('store_unavailable', error.message);
    }
  }

  Uint8List _receipt(Map<Object?, Object?> response) {
    final receipt = response['receipt'];
    if (receipt is Uint8List && receipt.isNotEmpty) return receipt;
    throw const TelegramPaymentException(
      'store_receipt_missing',
      'The App Store did not provide a receipt.',
    );
  }
}

class TelegramStorePurchaseService {
  TelegramStorePurchaseService({
    TelegramPaymentQuery? query,
    TelegramStoreBridge? bridge,
  }) : _query = query ?? TdClient.shared.query,
       _bridge = bridge ?? const MethodChannelTelegramStoreBridge();

  final TelegramPaymentQuery _query;
  final TelegramStoreBridge _bridge;
  Uint8List? _pendingReceipt;
  Map<String, dynamic>? _pendingPurpose;

  Future<bool> isSupported() => _bridge.isSupported();

  Future<void> checkCanPurchase(Map<String, dynamic> purpose) =>
      _query(canPurchaseRequest(purpose));

  Future<void> purchaseAndAssign({
    required String productId,
    required Map<String, dynamic> purpose,
  }) async {
    if (_pendingReceipt != null) {
      await _assignPendingReceipt();
      return;
    }
    if (productId.trim().isEmpty) {
      throw const TelegramPaymentException(
        'store_product_missing',
        'Telegram did not provide an App Store product identifier.',
      );
    }
    await checkCanPurchase(purpose);
    final receipt = await _bridge.purchase(productId);
    _pendingReceipt = receipt;
    _pendingPurpose = purpose;
    await _assignPendingReceipt();
  }

  Future<void> restorePremiumPurchases() async {
    final purpose = premiumSubscriptionPurpose(restore: true);
    if (_pendingReceipt != null) {
      await _assignPendingReceipt();
      return;
    }
    await checkCanPurchase(purpose);
    final receipt = await _bridge.restoreTransactions();
    _pendingReceipt = receipt;
    _pendingPurpose = purpose;
    await _assignPendingReceipt();
  }

  Future<void> _assignPendingReceipt() async {
    final receipt = _pendingReceipt;
    final purpose = _pendingPurpose;
    if (receipt == null || purpose == null) {
      throw const TelegramPaymentException(
        'store_receipt_missing',
        'There is no verified store receipt to assign.',
      );
    }
    await _query(assignTransactionRequest(receipt: receipt, purpose: purpose));
    _pendingReceipt = null;
    _pendingPurpose = null;
  }

  static Map<String, dynamic> premiumSubscriptionPurpose({
    required bool restore,
    bool upgrade = false,
  }) => {
    '@type': 'storePaymentPurposePremiumSubscription',
    'is_restore': restore,
    'is_upgrade': upgrade,
  };

  static Map<String, dynamic> premiumGiftPurpose({
    required String currency,
    required int amount,
    required int userId,
    String text = '',
  }) => {
    '@type': 'storePaymentPurposePremiumGift',
    'currency': currency,
    'amount': amount,
    'user_id': userId,
    'text': {
      '@type': 'formattedText',
      'text': text,
      'entities': <Map<String, dynamic>>[],
    },
  };

  static Map<String, dynamic> starsPurpose({
    required String currency,
    required int amount,
    required int starCount,
    int chatId = 0,
  }) => {
    '@type': 'storePaymentPurposeStars',
    'currency': currency,
    'amount': amount,
    'star_count': starCount,
    'chat_id': chatId,
  };

  @visibleForTesting
  static Map<String, dynamic> canPurchaseRequest(
    Map<String, dynamic> purpose,
  ) => {'@type': 'canPurchaseFromStore', 'purpose': purpose};

  @visibleForTesting
  static Map<String, dynamic> assignTransactionRequest({
    required Uint8List receipt,
    required Map<String, dynamic> purpose,
  }) => {
    '@type': 'assignStoreTransaction',
    'transaction': {
      '@type': 'storeTransactionAppStore',
      'receipt': base64.encode(receipt),
    },
    'purpose': purpose,
  };
}
