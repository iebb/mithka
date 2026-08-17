import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/auth/auth_manager.dart';
import 'package:mithka/auth/login_view.dart';

import 'support/l10n_fixtures.dart';

final fixtures = L10nFixtures.load();

void main() {
  test(
    'system back stays inside login when the page exposes back navigation',
    () {
      expect(
        loginHasBackAction(
          showBotLogin: false,
          forcePhone: false,
          step: const AuthWaitCode(AuthCodeInfo.fallback),
          configuredAccountCount: 1,
        ),
        isTrue,
      );
      expect(
        loginHasBackAction(
          showBotLogin: false,
          forcePhone: false,
          step: const AuthWaitPhoneNumber(),
          configuredAccountCount: 1,
        ),
        isFalse,
      );
      expect(
        loginHasBackAction(
          showBotLogin: false,
          forcePhone: true,
          step: const AuthWaitCode(AuthCodeInfo.fallback),
          configuredAccountCount: 1,
        ),
        isFalse,
      );
      expect(
        loginHasBackAction(
          showBotLogin: false,
          forcePhone: true,
          step: const AuthWaitPhoneNumber(),
          configuredAccountCount: 2,
        ),
        isTrue,
      );
      expect(
        loginHasBackAction(
          showBotLogin: true,
          forcePhone: false,
          step: const AuthWaitPhoneNumber(),
          configuredAccountCount: 1,
        ),
        isTrue,
      );
    },
  );

  test('login exposes passkeys as an Android-only labeled button', () {
    final source = File('lib/auth/login_view.dart').readAsStringSync();
    expect(
      source,
      contains('if (Platform.isAndroid && auth.canUseLoginPasskey)'),
    );
    expect(source, contains("ValueKey('android-login-passkey')"));
    expect(source, contains('AppStringKeys.loginWithPasskey'));

    final topActionsStart = source.indexOf('Widget _topRightActions(');
    final topActionsEnd = source.indexOf(
      'Widget _loginPasskeyButton(',
      topActionsStart,
    );
    expect(topActionsStart, greaterThanOrEqualTo(0));
    expect(topActionsEnd, greaterThan(topActionsStart));
    expect(
      source.substring(topActionsStart, topActionsEnd),
      isNot(contains('loginWithPasskey')),
    );
  });

  test('terms sheet opens only from the explicit login footer', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    final loginSource = File('lib/auth/login_view.dart').readAsStringSync();

    expect(mainSource, isNot(contains('FirstLaunchTermsGate')));
    expect(mainSource, isNot(contains('showTelegramTermsSheet')));
    expect(mainSource, isNot(contains('mithka.terms.accepted')));
    expect(
      loginSource,
      contains('onTap: () => showTelegramTermsSheet(context)'),
    );
    expect(loginSource, contains('AppStringKeys.loginTermsButton'));
  });

  test('login explains existing Telegram account requirement', () {
    expect(
      fixtures.messages('en')['loginCodeWillBeSentToNumber'],
      "We will send a verification code to your Telegram account. If you don't have one, create it in an official Telegram client first.",
    );
    expect(
      fixtures.messages('zhHans')['loginCodeWillBeSentToNumber'],
      contains('Telegram 官方客户端'),
    );
  });

  test('account backup reuses the shared settings page skeleton', () {
    final source = File(
      'lib/settings/account_backup_view.dart',
    ).readAsStringSync();

    expect(source, contains('SettingsPageScaffold('));
    expect(source, contains('SettingsListView('));
    expect(source, isNot(contains("ValueKey('account-backup-header')")));
  });
}
