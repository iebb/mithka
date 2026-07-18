import 'package:flutter/foundation.dart';

import '../tdlib/td_client.dart';

class AccountSecurityService {
  const AccountSecurityService();

  Future<Map<String, dynamic>> passwordState() =>
      TdClient.shared.query(passwordStateRequest());

  Future<Map<String, dynamic>> setPassword({
    required String oldPassword,
    required String newPassword,
    required String hint,
    String? recoveryEmail,
  }) => TdClient.shared.query(
    setPasswordRequest(
      oldPassword: oldPassword,
      newPassword: newPassword,
      hint: hint,
      recoveryEmail: recoveryEmail,
    ),
  );

  Future<Map<String, dynamic>> setRecoveryEmail({
    required String password,
    required String email,
  }) => TdClient.shared.query(
    setRecoveryEmailRequest(password: password, email: email),
  );

  Future<Map<String, dynamic>> checkRecoveryEmailCode(String code) =>
      TdClient.shared.query(checkRecoveryEmailCodeRequest(code));

  Future<Map<String, dynamic>> resendRecoveryEmailCode() =>
      TdClient.shared.query(resendRecoveryEmailCodeRequest());

  Future<Map<String, dynamic>> cancelRecoveryEmailVerification() =>
      TdClient.shared.query(cancelRecoveryEmailVerificationRequest());

  Future<Map<String, dynamic>> requestPasswordRecovery() =>
      TdClient.shared.query(requestPasswordRecoveryRequest());

  Future<Map<String, dynamic>> recoverPassword({
    required String code,
    required String newPassword,
    required String hint,
  }) => TdClient.shared.query(
    recoverPasswordRequest(code: code, newPassword: newPassword, hint: hint),
  );

  Future<Map<String, dynamic>> sendChangePhoneCode(String phoneNumber) =>
      TdClient.shared.query(changePhoneRequest(phoneNumber));

  Future<Map<String, dynamic>> checkChangePhoneCode(String code) =>
      TdClient.shared.query(checkPhoneCodeRequest(code));

  Future<Map<String, dynamic>> resendChangePhoneCode() =>
      TdClient.shared.query(resendPhoneCodeRequest());

  Future<Map<String, dynamic>> accountTtl() =>
      TdClient.shared.query(accountTtlRequest());

  Future<Map<String, dynamic>> setAccountTtl(int days) =>
      TdClient.shared.query(setAccountTtlRequest(days));

  Future<Map<String, dynamic>> deleteAccount({
    required String reason,
    required String password,
  }) => TdClient.shared.query(
    deleteAccountRequest(reason: reason, password: password),
  );

  @visibleForTesting
  static Map<String, dynamic> passwordStateRequest() => {
    '@type': 'getPasswordState',
  };

  @visibleForTesting
  static Map<String, dynamic> setPasswordRequest({
    required String oldPassword,
    required String newPassword,
    required String hint,
    String? recoveryEmail,
  }) => {
    '@type': 'setPassword',
    'old_password': oldPassword,
    'new_password': newPassword,
    'new_hint': hint,
    'set_recovery_email_address': recoveryEmail != null,
    'new_recovery_email_address': recoveryEmail ?? '',
  };

  @visibleForTesting
  static Map<String, dynamic> setRecoveryEmailRequest({
    required String password,
    required String email,
  }) => {
    '@type': 'setRecoveryEmailAddress',
    'password': password,
    'new_recovery_email_address': email,
  };

  @visibleForTesting
  static Map<String, dynamic> checkRecoveryEmailCodeRequest(String code) => {
    '@type': 'checkRecoveryEmailAddressCode',
    'code': code,
  };

  @visibleForTesting
  static Map<String, dynamic> resendRecoveryEmailCodeRequest() => {
    '@type': 'resendRecoveryEmailAddressCode',
  };

  @visibleForTesting
  static Map<String, dynamic> cancelRecoveryEmailVerificationRequest() => {
    '@type': 'cancelRecoveryEmailAddressVerification',
  };

  @visibleForTesting
  static Map<String, dynamic> requestPasswordRecoveryRequest() => {
    '@type': 'requestPasswordRecovery',
  };

  @visibleForTesting
  static Map<String, dynamic> recoverPasswordRequest({
    required String code,
    required String newPassword,
    required String hint,
  }) => {
    '@type': 'recoverPassword',
    'recovery_code': code,
    'new_password': newPassword,
    'new_hint': hint,
  };

  @visibleForTesting
  static Map<String, dynamic> changePhoneRequest(String phoneNumber) => {
    '@type': 'sendPhoneNumberCode',
    'phone_number': phoneNumber,
    'settings': null,
    'type': {'@type': 'phoneNumberCodeTypeChange'},
  };

  @visibleForTesting
  static Map<String, dynamic> checkPhoneCodeRequest(String code) => {
    '@type': 'checkPhoneNumberCode',
    'code': code,
  };

  @visibleForTesting
  static Map<String, dynamic> resendPhoneCodeRequest() => {
    '@type': 'resendPhoneNumberCode',
    'reason': null,
  };

  @visibleForTesting
  static Map<String, dynamic> accountTtlRequest() => {'@type': 'getAccountTtl'};

  @visibleForTesting
  static Map<String, dynamic> setAccountTtlRequest(int days) => {
    '@type': 'setAccountTtl',
    'ttl': {'@type': 'accountTtl', 'days': days},
  };

  @visibleForTesting
  static Map<String, dynamic> deleteAccountRequest({
    required String reason,
    required String password,
  }) => {'@type': 'deleteAccount', 'reason': reason, 'password': password};
}
