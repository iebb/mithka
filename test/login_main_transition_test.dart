import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/content_view.dart' show AuthGateTracker;
import 'package:mithka/auth/auth_manager.dart';

/// The auth gate's animation contract, unit-tested on the pure decision
/// helper — a widget-level pump of MainTabView needs the app's full provider
/// tree, which says nothing about this decision anyway.
void main() {
  group('AuthGateTracker.animates', () {
    test('cold start splash → sidebar stays a jump cut', () {
      // Failing-first: before the hand-off fix, EVERY switch onto MainTabView
      // ran Duration.zero, so finishing login hard-cut into the sidebar.
      expect(
        AuthGateTracker.animates(const AuthReady(), seenLoginSurface: false),
        isFalse,
        reason: 'cold launch must keep its deliberate jump cut',
      );
    });

    test('login → sidebar crossfades', () {
      expect(
        AuthGateTracker.animates(const AuthReady(), seenLoginSurface: true),
        isTrue,
        reason: 'completing login must fade into the sidebar',
      );
    });

    test('any departure from ready crossfades (logout, add account)', () {
      expect(
        AuthGateTracker.animates(
          const AuthWaitPhoneNumber(),
          seenLoginSurface: false,
        ),
        isTrue,
      );
      expect(
        AuthGateTracker.animates(
          const AuthLoggingOut(),
          seenLoginSurface: false,
        ),
        isTrue,
      );
    });

    test('sawLoginSurface only counts login-family steps', () {
      expect(
        AuthGateTracker.sawLoginSurface(const AuthInitializing()),
        isFalse,
      );
      expect(AuthGateTracker.sawLoginSurface(const AuthLoggingOut()), isFalse);
      expect(AuthGateTracker.sawLoginSurface(const AuthReady()), isFalse);
      expect(
        AuthGateTracker.sawLoginSurface(const AuthWaitPhoneNumber()),
        isTrue,
      );
      expect(AuthGateTracker.sawLoginSurface(const AuthReloading()), isTrue);
    });
  });
}
