import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/premium_auth_purchase_service.dart';

void main() {
  test('Premium authorization requests preserve App Store receipt bytes', () {
    expect(
      PremiumAuthPurchaseService.checkRequest(
        premiumDayCount: 90,
        currency: 'JPY',
        amount: 1000,
      ),
      {
        '@type': 'checkAuthenticationPremiumPurchase',
        'premium_day_count': 90,
        'currency': 'JPY',
        'amount': 1000,
      },
    );
    expect(
      PremiumAuthPurchaseService.transactionRequest(
        receipt: Uint8List.fromList([1, 2, 3]),
        restore: true,
        premiumDayCount: 90,
        currency: 'JPY',
        amount: 1000,
      ),
      {
        '@type': 'setAuthenticationPremiumPurchaseTransaction',
        'transaction': {'@type': 'storeTransactionAppStore', 'receipt': 'AQID'},
        'is_restore': true,
        'premium_day_count': 90,
        'currency': 'JPY',
        'amount': 1000,
      },
    );
  });
}
