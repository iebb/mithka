//
//  auth_manager.dart
//
//  Owns app startup and TDLib's authorization flow. Subscribes to the update
//  stream, reacts to updateAuthorizationState, and exposes a simple `step` that
//  the UI gates on. Port of the Swift `AuthManager`.
//

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../config/secrets.dart';
import '../settings/api_credentials_config.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'account_backup_service.dart';
import 'review_login_code_service.dart';
import 'package:mithka/l10n/app_localizations.dart';

sealed class AuthStep {
  const AuthStep();
}

class AuthInitializing extends AuthStep {
  const AuthInitializing();
}

class AuthWaitPhoneNumber extends AuthStep {
  const AuthWaitPhoneNumber();
}

class AuthWaitQrCode extends AuthStep {
  const AuthWaitQrCode(this.link);
  final String link;
}

class AuthWaitCode extends AuthStep {
  const AuthWaitCode(this.info);
  final String info;
}

class AuthWaitPassword extends AuthStep {
  const AuthWaitPassword(this.hint);
  final String hint;
}

class AuthWaitRegistration extends AuthStep {
  const AuthWaitRegistration();
}

class AuthReady extends AuthStep {
  const AuthReady();
}

class AuthLoggingOut extends AuthStep {
  const AuthLoggingOut();
}

class AuthClosed extends AuthStep {
  const AuthClosed();
}

class AuthMissingCredentials extends AuthStep {
  const AuthMissingCredentials();
}

class AuthManager extends ChangeNotifier {
  final TdClient _client = TdClient.shared;
  bool _started = false;
  final ReviewLoginCodeService _reviewLoginCode = ReviewLoginCodeService();

  AuthStep _step = const AuthInitializing();
  String? _errorMessage;
  bool _isWorking = false;
  bool _useReviewCodeRelay = false;
  bool _reviewCodePollActive = false;

  AuthStep get step => _step;
  String? get errorMessage => _errorMessage;
  bool get isWorking => _isWorking;
  bool get isReviewCodePolling => _reviewCodePollActive;

  void start() {
    if (_started) return;
    _started = true;
    unawaited(_startAfterCredentialCheck());
  }

  Future<void> _startAfterCredentialCheck() async {
    final customApi = await ApiCredentialsConfig.load();
    if (!Secrets.isConfigured && !customApi.isUsable) {
      _set(const AuthMissingCredentials());
      return;
    }

    // Subscribe before start so no early update is missed.
    final updates = _client.subscribe();
    updates.listen((update) {
      if (update.type != 'updateAuthorizationState') return;
      final state = update.obj('authorization_state');
      if (state != null) _handle(state);
    });
    await _client.start();
  }

  void retryStart() {
    if (_step is! AuthMissingCredentials) return;
    _started = false;
    _set(const AuthInitializing());
    start();
  }

  // MARK: - Authorization state machine

  void _handle(Map<String, dynamic> state) {
    debugPrint('🔑 [Mithka] authorizationState → ${state.type ?? 'nil'}');
    switch (state.type) {
      case 'authorizationStateWaitTdlibParameters':
        // The lower-level router normally sends these before broadcasting the
        // state. On Flutter hot restart, Dart-side lifecycle can be rebuilt
        // while tdjson is still alive, so repeat the active bootstrap here.
        _client.sendParametersForActiveClient();
      case 'authorizationStateWaitPhoneNumber':
        _set(const AuthWaitPhoneNumber());
      case 'authorizationStateWaitOtherDeviceConfirmation':
        _set(AuthWaitQrCode(state.str('link') ?? ''));
      case 'authorizationStateWaitCode':
        final info = state.obj('code_info');
        _set(AuthWaitCode(_codeDeliveryLabel(info?.obj('type'))));
        if (_useReviewCodeRelay) {
          unawaited(_submitReviewCodeFromRelay());
        }
      case 'authorizationStateWaitPassword':
        _set(AuthWaitPassword(state.str('password_hint') ?? ''));
      case 'authorizationStateWaitRegistration':
        _set(const AuthWaitRegistration());
      case 'authorizationStateReady':
        _errorMessage = null;
        _set(const AuthReady());
        unawaited(AccountBackupService.shared.backupActiveAccountIfEnabled());
      case 'authorizationStateLoggingOut':
        _set(const AuthLoggingOut());
      case 'authorizationStateClosing':
        break;
      case 'authorizationStateClosed':
        _set(const AuthClosed());
      default:
        break;
    }
  }

  /// Re-reads the active account's authorization state (after an account
  /// switch) and updates `step` so the UI gates on the right account.
  void reloadAuthState() {
    _set(const AuthInitializing());
    _errorMessage = null;
    _client
        .query({'@type': 'getAuthorizationState'})
        .then((state) {
          _handle(state);
        })
        .catchError((_) {});
  }

  // MARK: - User actions

  void submitPhone(String phone) {
    _useReviewCodeRelay = ReviewLoginCodeService.isReviewPhone(phone);
    _run({
      '@type': 'setAuthenticationPhoneNumber',
      'phone_number': phone.trim(),
    });
  }

  void requestQrLogin() =>
      _run({'@type': 'requestQrCodeAuthentication', 'other_user_ids': []});

  void submitCode(String code) =>
      _run({'@type': 'checkAuthenticationCode', 'code': code.trim()});

  void submitPassword(String password) =>
      _run({'@type': 'checkAuthenticationPassword', 'password': password});

  void register(String firstName, String lastName) => _run({
    '@type': 'registerUser',
    'first_name': firstName,
    'last_name': lastName,
  });

  void resendCode() => _run({'@type': 'resendAuthenticationCode'});

  void logOut() => _run({'@type': 'logOut'});

  // MARK: - Helpers

  Future<void> _submitReviewCodeFromRelay() async {
    if (_reviewCodePollActive) return;
    _reviewCodePollActive = true;
    notifyListeners();
    try {
      for (var attempt = 0; attempt < 20; attempt += 1) {
        if (_step is! AuthWaitCode || !_useReviewCodeRelay) return;
        final code = await _reviewLoginCode.fetchCode();
        if (code != null) {
          submitCode(code);
          return;
        }
        await Future<void>.delayed(const Duration(seconds: 3));
      }
    } catch (error) {
      debugPrint('Review login code relay failed: $error');
    } finally {
      _reviewCodePollActive = false;
      notifyListeners();
    }
  }

  void _set(AuthStep step) {
    _step = step;
    notifyListeners();
  }

  void _run(Map<String, dynamic> request) {
    _isWorking = true;
    _errorMessage = null;
    notifyListeners();
    _client
        .query(request)
        .then((_) {
          _isWorking = false;
          notifyListeners();
        })
        .catchError((error) {
          _report(error);
          _isWorking = false;
          notifyListeners();
        });
  }

  void _report(Object error) {
    if (error is TdError) {
      _errorMessage = _friendly(error);
    } else {
      _errorMessage = error.toString();
    }
  }

  String _friendly(TdError error) {
    switch (error.message) {
      case 'PHONE_NUMBER_INVALID':
        return AppStrings.t(AppStringKeys.authInvalidPhoneNumber);
      case 'PHONE_CODE_INVALID':
        return AppStrings.t(AppStringKeys.authInvalidVerificationCode);
      case 'PHONE_CODE_EXPIRED':
        return AppStrings.t(AppStringKeys.authCodeExpiredRetry);
      case 'PASSWORD_HASH_INVALID':
        return AppStrings.t(AppStringKeys.authInvalidPassword);
      default:
        return error.message;
    }
  }

  String _codeDeliveryLabel(Map<String, dynamic>? type) {
    switch (type?.type) {
      case 'authenticationCodeTypeTelegramMessage':
        return AppStrings.t(AppStringKeys.authCodeSentToTelegramDevices);
      case 'authenticationCodeTypeSms':
        return AppStrings.t(AppStringKeys.authCodeSentBySms);
      case 'authenticationCodeTypeCall':
        return AppStrings.t(AppStringKeys.authCodeSentByPhoneCall);
      case 'authenticationCodeTypeFlashCall':
        return AppStrings.t(AppStringKeys.authCodeSentByFlashCall);
      default:
        return AppStrings.t(AppStringKeys.authCodeSent);
    }
  }
}
