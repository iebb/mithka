//
//  Local premium (Telegram §1.4 self-build feature): defaults off, persists,
//  short-circuits only the OWN account's premium answer.
//

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/config/build_flags.dart';
import 'package:mithka/settings/local_premium.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('defaults to off', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    LocalPremium.shared.initialize(prefs);
    expect(LocalPremium.shared.enabled, isFalse);
    // Without the switch the real server value passes through.
    expect(LocalPremium.shared.premiumForMe(true), isTrue);
    expect(
      LocalPremium.shared.premiumForMe(false),
      allowTelegramTosViolations ? isFalse : isTrue,
    );
  });

  test('enabling unlocks the own-account premium answer', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final lp = LocalPremium.shared;
    lp.initialize(prefs);
    lp.setEnabled(true);
    expect(lp.enabled, allowTelegramTosViolations ? isTrue : isFalse);
    expect(
      lp.premiumForMe(false),
      allowTelegramTosViolations ? isTrue : isFalse,
    );
    expect(
      prefs.getBool('local_premium.enabled'),
      allowTelegramTosViolations ? isTrue : isNull,
    );
  });

  test('toggles notify listeners exactly once per change', () async {
    SharedPreferences.setMockInitialValues(const {});
    final prefs = await SharedPreferences.getInstance();
    final lp = LocalPremium.shared;
    lp.initialize(prefs);
    var notified = 0;
    lp.addListener(() => notified++);
    lp.setEnabled(true);
    lp.setEnabled(true);
    expect(notified, allowTelegramTosViolations ? 1 : 0);
  });
}
