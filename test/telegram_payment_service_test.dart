import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/chat/telegram_invoice_checkout_view.dart';
import 'package:mithka/chat/telegram_payment_service.dart';

void main() {
  test('payment web event decodes provider credential submission', () {
    final submission = decodePaymentFormSubmit(
      jsonEncode({
        'eventType': 'payment_form_submit',
        'eventData': jsonEncode({
          'credentials': jsonEncode({'type': 'card', 'id': 'tok_web'}),
          'title': 'Visa •••• 4242',
        }),
      }),
    );
    expect(submission?.credentials, {'type': 'card', 'id': 'tok_web'});
    expect(submission?.title, 'Visa •••• 4242');
    final authenticated = jsonEncode({
      'bridgeNonce': 'right',
      'eventType': 'payment_form_submit',
      'eventData': jsonEncode({
        'credentials': jsonEncode({'type': 'card', 'id': 'tok_web'}),
      }),
    });
    expect(
      decodePaymentFormSubmit(authenticated, expectedBridgeNonce: 'right'),
      isNotNull,
    );
    expect(
      decodePaymentFormSubmit(authenticated, expectedBridgeNonce: 'wrong'),
      isNull,
    );
  });

  test('Stripe card tokenization sends fields only to Stripe', () async {
    late http.Request captured;
    final client = MockClient((request) async {
      captured = request;
      return http.Response(jsonEncode({'id': 'tok_live', 'type': 'card'}), 200);
    });
    final service = TelegramPaymentService(
      query: (_) async => const {'@type': 'ok'},
      httpClient: client,
    );

    final token = await service.tokenizeStripeCard(
      publishableKey: 'pk_test_example',
      number: '4242 4242 4242 4242',
      expirationMonth: 12,
      expirationYear: 2030,
      cvc: '123',
      cardholderName: 'A Person',
      country: 'jp',
      postalCode: '100-0001',
    );

    expect(captured.url, Uri.https('api.stripe.com', '/v1/tokens'));
    expect(captured.headers['authorization'], 'Bearer pk_test_example');
    expect(captured.bodyFields['card[number]'], '4242424242424242');
    expect(captured.bodyFields['card[address_country]'], 'JP');
    expect(token, {'id': 'tok_live', 'type': 'card'});
  });

  test(
    'store purchase checks authorization before assigning receipt',
    () async {
      final requests = <Map<String, dynamic>>[];
      final bridge = _FakeStoreBridge();
      final service = TelegramStorePurchaseService(
        query: (request) async {
          requests.add(request);
          return const {'@type': 'ok'};
        },
        bridge: bridge,
      );
      final purpose = TelegramStorePurchaseService.starsPurpose(
        currency: 'USD',
        amount: 499,
        starCount: 250,
      );

      await service.purchaseAndAssign(
        productId: 'org.telegram.stars.250',
        purpose: purpose,
      );

      expect(bridge.purchasedProduct, 'org.telegram.stars.250');
      expect(requests, [
        {'@type': 'canPurchaseFromStore', 'purpose': purpose},
        {
          '@type': 'assignStoreTransaction',
          'transaction': {
            '@type': 'storeTransactionAppStore',
            'receipt': 'AQID',
          },
          'purpose': purpose,
        },
      ]);
    },
  );

  test('assignment retry resends receipt without purchasing twice', () async {
    var assignmentAttempts = 0;
    final bridge = _FakeStoreBridge();
    final service = TelegramStorePurchaseService(
      query: (request) async {
        if (request['@type'] == 'assignStoreTransaction') {
          assignmentAttempts++;
          if (assignmentAttempts == 1) throw StateError('network');
        }
        return const {'@type': 'ok'};
      },
      bridge: bridge,
    );
    final purpose = TelegramStorePurchaseService.starsPurpose(
      currency: 'USD',
      amount: 99,
      starCount: 50,
    );

    await expectLater(
      service.purchaseAndAssign(productId: 'stars.50', purpose: purpose),
      throwsStateError,
    );
    await service.purchaseAndAssign(productId: 'stars.50', purpose: purpose);

    expect(bridge.purchaseCount, 1);
    expect(assignmentAttempts, 2);
  });
}

class _FakeStoreBridge implements TelegramStoreBridge {
  String? purchasedProduct;
  int purchaseCount = 0;
  bool didRestore = false;

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<Uint8List> purchase(String productId) async {
    purchasedProduct = productId;
    purchaseCount++;
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<Uint8List> restoreTransactions() async {
    didRestore = true;
    return Uint8List.fromList([1, 2, 3]);
  }
}
