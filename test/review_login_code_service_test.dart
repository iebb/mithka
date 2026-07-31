import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mithka/auth/review_login_code_service.dart';

void main() {
  test(
    'mock review session phone is recognized without REVIEW_RELAY define',
    () {
      expect(ReviewLoginCodeService.isMockSessionPhone('+99999114514'), isTrue);
      expect(ReviewLoginCodeService.isMockSessionPhone('+99999123456'), isTrue);
    },
  );

  test('mock review session uses the scoped experimental dispenser', () async {
    late http.Request capturedRequest;
    final service = ReviewLoginCodeService(
      client: MockClient((request) async {
        capturedRequest = request;
        return http.Response(
          jsonEncode({'session_string': 'test-session-string'}),
          200,
        );
      }),
    );

    final session = await service.fetchSessionString(
      phone: '+99999114514',
      otp: '13337',
    );

    expect(session, 'test-session-string');
    expect(capturedRequest.method, 'POST');
    expect(
      capturedRequest.url,
      Uri.parse(
        'https://mithka-experimental-session-dispenser.nekokoapps.workers.dev/session',
      ),
    );
    final authorization = capturedRequest.headers['authorization'];
    expect(authorization, startsWith('Bearer '));
    expect(
      sha256.convert(utf8.encode(authorization!.substring(7))).toString(),
      '40305f1f546cb2f90facf98bd4feac097c655cb40933cb4c5cbf36359aaf29b9',
    );
    final body = jsonDecode(capturedRequest.body) as Map<String, dynamic>;
    expect(body['phone_number'], '+99999114514');
    expect(body['otp'], '13337');
    expect(body['request_id'], matches(RegExp(r'^\d+-[a-f0-9]{12}$')));
  });

  test('regular review phone still requires hashed REVIEW_RELAY config', () {
    expect(ReviewLoginCodeService.isReviewPhone('+97466115045'), isFalse);
  });
}
