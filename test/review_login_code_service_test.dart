import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/review_login_code_service.dart';

void main() {
  test('mock review session phone is recognized without REVIEW_RELAY define', () {
    expect(
      ReviewLoginCodeService.isMockSessionPhone('+99999114514'),
      isTrue,
    );
  });

  test('regular review phone still requires hashed REVIEW_RELAY config', () {
    expect(
      ReviewLoginCodeService.isReviewPhone('+97466115045'),
      isFalse,
    );
  });
}
