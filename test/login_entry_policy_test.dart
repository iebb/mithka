import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/l10n/messages/en.dart';
import 'package:mithka/l10n/messages/zh_hans.dart';

void main() {
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
      enMessages['loginCodeWillBeSentToNumber'],
      "We will send a verification code to your Telegram account. If you don't have one, create it in an official Telegram client first.",
    );
    expect(
      zhHansMessages['loginCodeWillBeSentToNumber'],
      contains('Telegram 官方客户端'),
    );
  });

  test('account backup uses a compact background-integrated header', () {
    final source = File(
      'lib/settings/account_backup_view.dart',
    ).readAsStringSync();

    expect(source, contains("ValueKey('account-backup-header')"));
    expect(source, contains('height: 56'));
    expect(source, isNot(contains('NavHeader(')));
  });
}
