//
//  auth_manager.dart
//
//  Owns app startup and TDLib's authorization flow. Subscribes to the update
//  stream, reacts to updateAuthorizationState, and exposes a simple `step` that
//  the UI gates on. Port of the Swift `AuthManager`.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../config/secrets.dart';
import '../settings/api_credentials_config.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'package:mithka/notifications/scope_notification_settings.dart';
import 'account_backup_service.dart';
import 'review_login_code_service.dart';

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
  final AuthCodeInfo info;
}

enum AuthCodeDeliveryMethod {
  telegramMessage,
  sms,
  call,
  flashCall,
  missedCall,
  fragment,
  firebase,
  email,
  unknown,
}

class AuthCodeInfo {
  const AuthCodeInfo({
    required this.method,
    required this.length,
    this.numericOnly = true,
    this.phoneNumber,
    this.phoneNumberPrefix,
    this.pattern,
    this.url,
    this.timeout,
  });

  final AuthCodeDeliveryMethod method;
  final int length;
  final bool numericOnly;
  final String? phoneNumber;
  final String? phoneNumberPrefix;
  final String? pattern;
  final String? url;
  final int? timeout;

  int get effectiveLength => length > 0 ? length : 5;

  bool get isNumeric => numericOnly;

  static const fallback = AuthCodeInfo(
    method: AuthCodeDeliveryMethod.unknown,
    length: 5,
  );
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

@visibleForTesting
bool authorizationStateAcceptsPhoneNumber(String? type) => const {
  'authorizationStateWaitPhoneNumber',
  'authorizationStateWaitPremiumPurchase',
  'authorizationStateWaitEmailAddress',
  'authorizationStateWaitEmailCode',
  'authorizationStateWaitCode',
  'authorizationStateWaitPassword',
  'authorizationStateWaitRegistration',
}.contains(type);

@visibleForTesting
bool authorizationStateRequiresQrReset(String? type) =>
    type == 'authorizationStateWaitOtherDeviceConfirmation';

class AuthManager extends ChangeNotifier {
  final TdClient _client = TdClient.shared;
  bool _started = false;
  final ReviewLoginCodeService _reviewLoginCode = ReviewLoginCodeService();

  AuthStep _step = const AuthInitializing();
  String? _errorMessage;
  bool _isWorking = false;
  int _actionSerial = 0;
  int? _authorizationTransitionAction;
  bool _useReviewCodeRelay = false;
  bool _reviewCodePollActive = false;
  String? _mockReviewSessionPhone;

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
    await ScopeNotificationSettings.shared.load();
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
    final preserveWorking = _authorizationTransitionAction == _actionSerial;
    if (_isWorking && !preserveWorking) {
      _actionSerial += 1;
      _isWorking = false;
    }
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
        _set(AuthWaitCode(_codeInfo(info)));
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
    _actionSerial += 1;
    _isWorking = false;
    _errorMessage = null;
    _set(const AuthInitializing());
    _client
        .query({'@type': 'getAuthorizationState'})
        .timeout(const Duration(seconds: 8))
        .then(_handle)
        .catchError((Object error) {
          debugPrint('Auth state reload failed: $error');
          _client.sendParametersForActiveClient();
          _set(const AuthWaitPhoneNumber());
        });
  }

  // MARK: - User actions

  Future<bool> submitPhone(String phone) async {
    if (_isWorking) return false;
    final normalizedPhone = phone.trim();
    _mockReviewSessionPhone =
        ReviewLoginCodeService.isMockSessionPhone(normalizedPhone)
        ? normalizedPhone
        : null;
    _useReviewCodeRelay =
        _mockReviewSessionPhone == null &&
        ReviewLoginCodeService.isReviewPhone(normalizedPhone);
    if (_mockReviewSessionPhone != null) {
      _actionSerial += 1;
      _isWorking = false;
      _errorMessage = null;
      _set(const AuthWaitCode(AuthCodeInfo.fallback));
      return true;
    }
    final action = _beginAuthorizationTransition();
    try {
      var state = await _client
          .query({'@type': 'getAuthorizationState'})
          .timeout(const Duration(seconds: 5));
      if (authorizationStateRequiresQrReset(state.type)) {
        _set(const AuthInitializing());
        await _client.resetActiveQrLogin();
        if (action != _actionSerial) return false;
        state = await _client
            .query({'@type': 'getAuthorizationState'})
            .timeout(const Duration(seconds: 5));
      }
      if (!authorizationStateAcceptsPhoneNumber(state.type)) {
        throw StateError(
          'Phone number authentication is unavailable from ${state.type}',
        );
      }
      await _client
          .query({
            '@type': 'setAuthenticationPhoneNumber',
            'phone_number': normalizedPhone,
          })
          .timeout(const Duration(seconds: 20));
      return action == _actionSerial;
    } catch (error) {
      if (action == _actionSerial) _report(error);
      return false;
    } finally {
      _finishAuthorizationTransition(action);
    }
  }

  /// Leaves TDLib's persisted QR state before the phone-number form is used.
  Future<bool> switchToPhoneLogin() async {
    if (_isWorking) return false;
    final action = _beginAuthorizationTransition();
    try {
      final state = await _client
          .query({'@type': 'getAuthorizationState'})
          .timeout(const Duration(seconds: 5));
      if (authorizationStateRequiresQrReset(state.type)) {
        _set(const AuthInitializing());
        await _client.resetActiveQrLogin();
      } else if (!authorizationStateAcceptsPhoneNumber(state.type)) {
        throw StateError(
          'Phone number authentication is unavailable from ${state.type}',
        );
      }
      return action == _actionSerial;
    } catch (error) {
      if (action == _actionSerial) _report(error);
      return false;
    } finally {
      _finishAuthorizationTransition(action);
    }
  }

  void requestQrLogin() =>
      _run({'@type': 'requestQrCodeAuthentication', 'other_user_ids': []});

  void submitCode(String code) {
    final mockPhone = _mockReviewSessionPhone;
    if (mockPhone != null) {
      unawaited(_restoreMockReviewSession(mockPhone, code));
      return;
    }
    _run({'@type': 'checkAuthenticationCode', 'code': code.trim()});
  }

  void submitPassword(String password) =>
      _run({'@type': 'checkAuthenticationPassword', 'password': password});

  void register(String firstName, String lastName) => _run({
    '@type': 'registerUser',
    'first_name': firstName,
    'last_name': lastName,
  });

  void resendCode() {
    if (_mockReviewSessionPhone != null) return;
    _run({'@type': 'resendAuthenticationCode'});
  }

  void logOut() => _run({'@type': 'logOut'});

  void cancelPendingAction() {
    if (!_isWorking) return;
    _actionSerial += 1;
    _isWorking = false;
    notifyListeners();
  }

  // MARK: - Helpers

  int _beginAuthorizationTransition() {
    final action = ++_actionSerial;
    _authorizationTransitionAction = action;
    _isWorking = true;
    _errorMessage = null;
    notifyListeners();
    return action;
  }

  void _finishAuthorizationTransition(int action) {
    if (_authorizationTransitionAction == action) {
      _authorizationTransitionAction = null;
    }
    if (action != _actionSerial) return;
    _isWorking = false;
    notifyListeners();
  }

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

  Future<void> _restoreMockReviewSession(String phone, String otp) async {
    final action = ++_actionSerial;
    _isWorking = true;
    _errorMessage = null;
    notifyListeners();
    try {
      final sessionString = await _reviewLoginCode.fetchSessionString(
        phone: phone,
        otp: otp,
      );
      if (action != _actionSerial) return;
      if (sessionString == null) {
        _errorMessage = AppStrings.t(AppStringKeys.authInvalidVerificationCode);
        return;
      }

      await AccountBackupService.shared.restoreSessionString(sessionString);
      if (action != _actionSerial) return;
      _mockReviewSessionPhone = null;
      _useReviewCodeRelay = false;
      _isWorking = false;
      _errorMessage = null;
      reloadAuthState();
    } catch (error) {
      if (action != _actionSerial) return;
      debugPrint('Review session relay failed: $error');
      _errorMessage = error is TdError ? _friendly(error) : error.toString();
    } finally {
      if (action == _actionSerial) {
        _isWorking = false;
        notifyListeners();
      }
    }
  }

  void _set(AuthStep step) {
    _step = step;
    notifyListeners();
  }

  void _run(Map<String, dynamic> request) {
    final action = ++_actionSerial;
    _isWorking = true;
    _errorMessage = null;
    notifyListeners();
    _client
        .query(request)
        .timeout(const Duration(seconds: 20))
        .then((_) {
          if (action != _actionSerial) return;
          _isWorking = false;
          notifyListeners();
        })
        .catchError((error) {
          if (action != _actionSerial) return;
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

  AuthCodeInfo _codeInfo(Map<String, dynamic>? info) {
    final type = info?.obj('type');
    final rawType = type?.type ?? '';
    final lowerType = rawType.toLowerCase();
    final method = switch (rawType) {
      'authenticationCodeTypeTelegramMessage' =>
        AuthCodeDeliveryMethod.telegramMessage,
      'authenticationCodeTypeSms' ||
      'authenticationCodeTypeSmsWord' ||
      'authenticationCodeTypeSmsPhrase' => AuthCodeDeliveryMethod.sms,
      'authenticationCodeTypeCall' => AuthCodeDeliveryMethod.call,
      'authenticationCodeTypeFlashCall' => AuthCodeDeliveryMethod.flashCall,
      'authenticationCodeTypeMissedCall' => AuthCodeDeliveryMethod.missedCall,
      'authenticationCodeTypeFragment' => AuthCodeDeliveryMethod.fragment,
      'authenticationCodeTypeFirebaseAndroid' ||
      'authenticationCodeTypeFirebaseIos' => AuthCodeDeliveryMethod.firebase,
      'authenticationCodeTypeEmailAddress' ||
      'emailAddressAuthenticationCodeInfo' => AuthCodeDeliveryMethod.email,
      _ when lowerType.contains('telegram') =>
        AuthCodeDeliveryMethod.telegramMessage,
      _ when lowerType.contains('sms') => AuthCodeDeliveryMethod.sms,
      _ when lowerType.contains('missedcall') =>
        AuthCodeDeliveryMethod.missedCall,
      _ when lowerType.contains('flashcall') =>
        AuthCodeDeliveryMethod.flashCall,
      _ when lowerType.contains('call') => AuthCodeDeliveryMethod.call,
      _ when lowerType.contains('fragment') => AuthCodeDeliveryMethod.fragment,
      _ when lowerType.contains('firebase') => AuthCodeDeliveryMethod.firebase,
      _ when lowerType.contains('email') => AuthCodeDeliveryMethod.email,
      _ => AuthCodeDeliveryMethod.unknown,
    };
    return AuthCodeInfo(
      method: method,
      length: type?.integer('length') ?? 0,
      numericOnly:
          !lowerType.contains('word') &&
          !lowerType.contains('phrase') &&
          method != AuthCodeDeliveryMethod.email,
      phoneNumber: info?.str('phone_number'),
      phoneNumberPrefix: type?.str('phone_number_prefix'),
      pattern: type?.str('pattern'),
      url: type?.str('url'),
      timeout: info?.integer('timeout'),
    );
  }
}
