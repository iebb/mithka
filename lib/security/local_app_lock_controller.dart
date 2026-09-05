import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import 'app_lock_privacy.dart';

enum AppLockCredentialType { pin, gesture }

enum AppLockAutoLockOption {
  disabled(0),
  oneMinute(60),
  fiveMinutes(300),
  oneHour(3600),
  fiveHours(18000);

  const AppLockAutoLockOption(this.seconds);

  final int seconds;

  static AppLockAutoLockOption? fromSeconds(int seconds) {
    for (final option in values) {
      if (option.seconds == seconds) return option;
    }
    return null;
  }
}

enum AppLockBiometricKind { face, fingerprint, generic }

enum AppLockBiometricResult {
  success,
  canceled,
  unavailable,
  lockedOut,
  failed,
}

typedef AppLockSecureRead = Future<String?> Function(String key);
typedef AppLockSecureWrite = Future<void> Function(String key, String? value);
typedef AppLockBiometricProbe = Future<List<BiometricType>> Function();
typedef AppLockBiometricAuthenticate =
    Future<bool> Function(String localizedReason);
typedef AppLockPrivacyShieldApply = Future<void> Function(bool visible);
typedef AppLockNow = DateTime Function();

/// Owns the app-local lock credential and the current foreground lock state.
///
/// Only a salted PBKDF2 digest is persisted. The clear-text PIN or gesture is
/// held for the duration of a single method call and is never written to disk.
class LocalAppLockController extends ChangeNotifier {
  LocalAppLockController({
    AppLockSecureRead? secureRead,
    AppLockSecureWrite? secureWrite,
    AppLockBiometricProbe? biometricProbe,
    AppLockBiometricAuthenticate? biometricAuthenticate,
    AppLockPrivacyShieldApply? privacyShieldApply,
    this.hashRounds = _defaultHashRounds,
    bool? platformSupportsBiometrics,
    AppLockNow? now,
  }) : _secureRead = secureRead ?? _defaultSecureRead,
       _secureWrite = secureWrite ?? _defaultSecureWrite,
       _biometricProbe = biometricProbe ?? _defaultBiometricProbe,
       _biometricAuthenticate =
           biometricAuthenticate ?? _defaultBiometricAuthenticate,
       _privacyShieldApply =
           privacyShieldApply ?? AppLockPrivacyPlatform.setPrivacyShieldVisible,
       _platformSupportsBiometrics =
           platformSupportsBiometrics ?? _defaultPlatformSupportsBiometrics,
       _now = now ?? DateTime.now;

  static final LocalAppLockController shared = LocalAppLockController();

  static const _storageKey = 'mithka.local_app_lock.v1';
  static const _attemptStorageKey = 'mithka.local_app_lock.attempts.v1';
  static const _defaultHashRounds = 120000;
  static const _pinLength = 4;
  static const _minimumGestureNodes = 4;
  static const _storage = FlutterSecureStorage();

  final AppLockSecureRead _secureRead;
  final AppLockSecureWrite _secureWrite;
  final AppLockBiometricProbe _biometricProbe;
  final AppLockBiometricAuthenticate _biometricAuthenticate;
  final AppLockPrivacyShieldApply _privacyShieldApply;
  final int hashRounds;
  final bool _platformSupportsBiometrics;
  final AppLockNow _now;

  _StoredAppLock? _stored;
  _StoredFailedAttempts _failedAttempts = const _StoredFailedAttempts();
  bool _initialized = false;
  bool _locked = false;
  bool _storageUnavailable = false;
  bool _readingStorage = false;
  bool _authenticatingBiometrics = false;
  bool _biometricAvailable = false;
  AppLockBiometricKind _biometricKind = AppLockBiometricKind.generic;
  int _lockEpoch = 0;
  Timer? _autoLockTimer;
  DateTime? _awaySince;

  bool get initialized => _initialized;
  bool get enabled => _stored != null;
  bool get locked => _locked;
  bool get storageUnavailable => _storageUnavailable;
  bool get readingStorage => _readingStorage;
  bool get authenticatingBiometrics => _authenticatingBiometrics;
  bool get biometricAvailable => _biometricAvailable;
  bool get biometricEnabled => _stored?.biometricEnabled ?? false;
  AppLockAutoLockOption get autoLockOption =>
      AppLockAutoLockOption.fromSeconds(_stored?.autoLockSeconds ?? 0) ??
      AppLockAutoLockOption.disabled;
  AppLockBiometricKind get biometricKind => _biometricKind;
  AppLockCredentialType? get credentialType => _stored?.type;
  int get lockEpoch => _lockEpoch;
  int get failedAttemptCount => _failedAttempts.count;
  Duration get credentialRetryAfter {
    final retryAt = _failedAttempts.retryAt;
    if (retryAt == null) return Duration.zero;
    final remaining = retryAt.difference(_now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get canAttemptCredential => credentialRetryAfter == Duration.zero;

  static int get pinLength => _pinLength;
  static int get minimumGestureNodes => _minimumGestureNodes;

  Future<void> initialize() async {
    if (_initialized) return;
    _readingStorage = true;
    try {
      final value = await _secureRead(_storageKey);
      _stored = _StoredAppLock.tryParse(value);
      if (value != null && value.isNotEmpty && _stored == null) {
        throw const FormatException('Invalid app-lock record');
      }
      _failedAttempts = _StoredFailedAttempts.tryParse(
        await _secureRead(_attemptStorageKey),
      );
      if (_stored != null) {
        _locked = true;
        _lockEpoch = 1;
        if (_stored!.storageVersion < 2) {
          await _persist(_stored!);
        }
      }
    } catch (error) {
      debugPrint('Local app lock could not read secure storage: $error');
      _failClosedForStorageError();
    } finally {
      _readingStorage = false;
    }
    _initialized = true;
    await refreshBiometricAvailability();
    unawaited(_applyPrivacyShield(false));
    notifyListeners();
  }

  /// Refreshes secure lock configuration changed by another desktop engine.
  /// Enabling a lock does not immediately cover the already-unlocked primary
  /// window; its normal lifecycle transition will lock it.
  Future<void> reloadFromStorage() async {
    if (!_initialized) {
      await initialize();
      return;
    }
    if (_readingStorage) return;
    _readingStorage = true;
    notifyListeners();
    try {
      final wasStorageUnavailable = _storageUnavailable;
      final value = await _secureRead(_storageKey);
      _stored = _StoredAppLock.tryParse(value);
      if (value != null && value.isNotEmpty && _stored == null) {
        throw const FormatException('Invalid app-lock record');
      }
      _failedAttempts = _StoredFailedAttempts.tryParse(
        await _secureRead(_attemptStorageKey),
      );
      _storageUnavailable = false;
      if (_stored == null) {
        _locked = false;
        _authenticatingBiometrics = false;
      } else if (_stored!.storageVersion < 2) {
        await _persist(_stored!);
      } else if (wasStorageUnavailable && !_locked) {
        _locked = true;
        _lockEpoch += 1;
      }
    } catch (error) {
      debugPrint('Local app lock could not reload secure storage: $error');
      _failClosedForStorageError();
    } finally {
      _readingStorage = false;
    }
    await refreshBiometricAvailability();
    unawaited(_applyPrivacyShield(false));
    notifyListeners();
  }

  void _failClosedForStorageError() {
    _storageUnavailable = true;
    _locked = true;
    _authenticatingBiometrics = false;
    _lockEpoch += 1;
  }

  Future<void> refreshBiometricAvailability() async {
    if (!_platformSupportsBiometrics) {
      _biometricAvailable = false;
      return;
    }
    try {
      final types = await _biometricProbe();
      _biometricAvailable = types.isNotEmpty;
      if (types.contains(BiometricType.face)) {
        _biometricKind = AppLockBiometricKind.face;
      } else if (types.contains(BiometricType.fingerprint)) {
        _biometricKind = AppLockBiometricKind.fingerprint;
      } else {
        _biometricKind = AppLockBiometricKind.generic;
      }
    } catch (error) {
      _biometricAvailable = false;
      debugPrint('Local app lock could not inspect biometrics: $error');
    }
    if (_initialized) notifyListeners();
  }

  Future<void> setCredential(
    AppLockCredentialType type,
    String credential,
  ) async {
    if (!_isValidCredential(type, credential)) {
      throw ArgumentError.value(credential, 'credential');
    }
    final secureRandom = Random.secure();
    final salt = List<int>.generate(32, (_) => secureRandom.nextInt(256));
    final digest = await compute(
      _deriveCredentialHash,
      _CredentialHashInput(
        credential: credential,
        salt: salt,
        rounds: hashRounds,
      ),
    );
    final next = _StoredAppLock(
      type: type,
      salt: salt,
      digest: digest,
      rounds: hashRounds,
      biometricEnabled: _stored?.biometricEnabled ?? false,
      autoLockSeconds: _stored?.autoLockSeconds ?? 0,
    );
    await _persist(next);
    await _clearFailedAttempts();
    _stored = next;
    _storageUnavailable = false;
    _locked = false;
    unawaited(_applyPrivacyShield(false));
    notifyListeners();
  }

  Future<bool> verifyCredential(String credential) async {
    final stored = _stored;
    if (stored == null || !_isValidCredential(stored.type, credential)) {
      return false;
    }
    final digest = await compute(
      _deriveCredentialHash,
      _CredentialHashInput(
        credential: credential,
        salt: stored.salt,
        rounds: stored.rounds,
      ),
    );
    return _constantTimeEquals(digest, stored.digest);
  }

  Future<bool> unlockWithCredential(String credential) async {
    if (_storageUnavailable || !canAttemptCredential) return false;
    final verified = await verifyCredential(credential);
    if (verified) {
      try {
        await _clearFailedAttempts();
      } catch (error) {
        debugPrint('Local app lock could not clear failed attempts: $error');
        _failClosedForStorageError();
        notifyListeners();
        return false;
      }
      unlock();
    } else {
      try {
        await _recordFailedAttempt();
      } catch (error) {
        debugPrint('Local app lock could not persist failed attempts: $error');
        _failClosedForStorageError();
        notifyListeners();
      }
    }
    return verified;
  }

  Future<void> _recordFailedAttempt() async {
    final count = _failedAttempts.count + 1;
    final next = _StoredFailedAttempts(
      count: count,
      retryAt: _now().add(_failedAttemptDelay(count)),
    );
    await _secureWrite(_attemptStorageKey, next.encode());
    _failedAttempts = next;
    notifyListeners();
  }

  Future<void> _clearFailedAttempts() async {
    if (_failedAttempts.count == 0 && _failedAttempts.retryAt == null) return;
    await _secureWrite(_attemptStorageKey, null);
    _failedAttempts = const _StoredFailedAttempts();
  }

  static Duration _failedAttemptDelay(int count) => switch (count) {
    <= 1 => const Duration(seconds: 1),
    2 => const Duration(seconds: 2),
    3 => const Duration(seconds: 5),
    4 => const Duration(seconds: 15),
    5 => const Duration(seconds: 30),
    6 => const Duration(minutes: 1),
    7 => const Duration(minutes: 5),
    8 => const Duration(minutes: 15),
    _ => const Duration(hours: 1),
  };

  void lock() {
    if (!enabled || _locked || _authenticatingBiometrics) return;
    _locked = true;
    _lockEpoch += 1;
    notifyListeners();
  }

  void unlock() {
    if (!_locked || _storageUnavailable) return;
    _locked = false;
    notifyListeners();
  }

  Future<void> disable() async {
    await _secureWrite(_storageKey, null);
    await _secureWrite(_attemptStorageKey, null);
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    _awaySince = null;
    _stored = null;
    _failedAttempts = const _StoredFailedAttempts();
    _locked = false;
    _storageUnavailable = false;
    _authenticatingBiometrics = false;
    unawaited(_applyPrivacyShield(false));
    notifyListeners();
  }

  Future<void> setAutoLockOption(AppLockAutoLockOption option) async {
    final stored = _stored;
    if (stored == null || stored.autoLockSeconds == option.seconds) return;
    final next = stored.copyWith(autoLockSeconds: option.seconds);
    await _persist(next);
    _stored = next;
    _rescheduleAutoLock();
    notifyListeners();
  }

  /// Applies auto-lock timing and iOS app-switcher shielding to lifecycle
  /// transitions. A disabled timeout preserves the current unlocked session
  /// across brief background transitions, matching the official clients.
  void handleLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        _handleResumed();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        _handleAway();
    }
  }

  void _handleAway() {
    if (!enabled && !_storageUnavailable) return;
    _awaySince ??= DateTime.now();
    unawaited(_applyPrivacyShield(true));
    _rescheduleAutoLock();
  }

  void _handleResumed() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    final awaySince = _awaySince;
    final option = autoLockOption;
    if (enabled &&
        awaySince != null &&
        option != AppLockAutoLockOption.disabled &&
        DateTime.now().difference(awaySince) >=
            Duration(seconds: option.seconds)) {
      lock();
    }
    _awaySince = null;
    if (enabled || _storageUnavailable) {
      unawaited(_applyPrivacyShield(false));
    }
  }

  void _rescheduleAutoLock() {
    _autoLockTimer?.cancel();
    _autoLockTimer = null;
    final awaySince = _awaySince;
    final option = autoLockOption;
    if (!enabled ||
        awaySince == null ||
        option == AppLockAutoLockOption.disabled) {
      return;
    }
    final elapsed = DateTime.now().difference(awaySince);
    final remaining = Duration(seconds: option.seconds) - elapsed;
    if (remaining <= Duration.zero) {
      lock();
      return;
    }
    _autoLockTimer = Timer(remaining, () {
      _autoLockTimer = null;
      final currentAwaySince = _awaySince;
      if (!enabled || currentAwaySince == null) return;
      if (DateTime.now().difference(currentAwaySince) >=
          Duration(seconds: autoLockOption.seconds)) {
        lock();
      } else {
        _rescheduleAutoLock();
      }
    });
  }

  Future<void> _applyPrivacyShield(bool visible) async {
    try {
      await _privacyShieldApply(visible);
    } catch (error) {
      debugPrint('Local app lock privacy shield could not be applied: $error');
    }
  }

  Future<AppLockBiometricResult> setBiometricEnabled(
    bool value, {
    required String localizedReason,
  }) async {
    final stored = _stored;
    if (stored == null) return AppLockBiometricResult.unavailable;
    if (!value) {
      final next = stored.copyWith(biometricEnabled: false);
      await _persist(next);
      _stored = next;
      notifyListeners();
      return AppLockBiometricResult.success;
    }
    if (!_biometricAvailable) {
      await refreshBiometricAvailability();
      if (!_biometricAvailable) return AppLockBiometricResult.unavailable;
    }
    final result = await authenticateBiometric(
      localizedReason: localizedReason,
      unlockOnSuccess: false,
      requireEnabled: false,
    );
    if (result != AppLockBiometricResult.success) return result;
    final next = stored.copyWith(biometricEnabled: true);
    await _persist(next);
    _stored = next;
    notifyListeners();
    return AppLockBiometricResult.success;
  }

  Future<AppLockBiometricResult> authenticateBiometric({
    required String localizedReason,
    bool unlockOnSuccess = true,
    bool requireEnabled = true,
  }) async {
    if (_authenticatingBiometrics ||
        !_biometricAvailable ||
        (requireEnabled && !biometricEnabled)) {
      return AppLockBiometricResult.unavailable;
    }
    _authenticatingBiometrics = true;
    notifyListeners();
    try {
      final authenticated = await _biometricAuthenticate(localizedReason);
      if (!authenticated) return AppLockBiometricResult.failed;
      if (unlockOnSuccess) {
        try {
          await _clearFailedAttempts();
        } catch (error) {
          debugPrint(
            'Local app lock could not clear failed attempts after biometrics: '
            '$error',
          );
          _failClosedForStorageError();
          return AppLockBiometricResult.failed;
        }
        unlock();
      }
      return AppLockBiometricResult.success;
    } on LocalAuthException catch (error) {
      return switch (error.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.userRequestedFallback =>
          AppLockBiometricResult.canceled,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout =>
          AppLockBiometricResult.lockedOut,
        LocalAuthExceptionCode.noCredentialsSet ||
        LocalAuthExceptionCode.noBiometricsEnrolled ||
        LocalAuthExceptionCode.noBiometricHardware ||
        LocalAuthExceptionCode.biometricHardwareTemporarilyUnavailable =>
          AppLockBiometricResult.unavailable,
        _ => AppLockBiometricResult.failed,
      };
    } catch (error) {
      debugPrint('Local app lock biometric authentication failed: $error');
      return AppLockBiometricResult.failed;
    } finally {
      _authenticatingBiometrics = false;
      notifyListeners();
    }
  }

  Future<void> _persist(_StoredAppLock value) =>
      _secureWrite(_storageKey, value.encode());

  static bool _isValidCredential(
    AppLockCredentialType type,
    String credential,
  ) {
    switch (type) {
      case AppLockCredentialType.pin:
        return RegExp(r'^\d{4}$').hasMatch(credential);
      case AppLockCredentialType.gesture:
        final nodes = credential
            .split(',')
            .map(int.tryParse)
            .whereType<int>()
            .toList();
        return nodes.length >= _minimumGestureNodes &&
            nodes.length == nodes.toSet().length &&
            nodes.every((node) => node >= 0 && node < 9);
    }
  }

  static Future<String?> _defaultSecureRead(String key) =>
      _storage.read(key: key);

  static Future<void> _defaultSecureWrite(String key, String? value) =>
      value == null
      ? _storage.delete(key: key)
      : _storage.write(key: key, value: value);

  static Future<List<BiometricType>> _defaultBiometricProbe() =>
      LocalAuthentication().getAvailableBiometrics();

  static Future<bool> _defaultBiometricAuthenticate(String reason) =>
      LocalAuthentication().authenticate(
        localizedReason: reason,
        biometricOnly: true,
        persistAcrossBackgrounding: true,
      );

  static bool get _defaultPlatformSupportsBiometrics =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void dispose() {
    _autoLockTimer?.cancel();
    super.dispose();
  }
}

@immutable
class _CredentialHashInput {
  const _CredentialHashInput({
    required this.credential,
    required this.salt,
    required this.rounds,
  });

  final String credential;
  final List<int> salt;
  final int rounds;
}

List<int> _deriveCredentialHash(_CredentialHashInput input) {
  final mac = Hmac(sha256, utf8.encode(input.credential));
  var block = mac.convert([...input.salt, 0, 0, 0, 1]).bytes;
  final derived = List<int>.from(block);
  for (var round = 1; round < input.rounds; round += 1) {
    block = mac.convert(block).bytes;
    for (var index = 0; index < derived.length; index += 1) {
      derived[index] ^= block[index];
    }
  }
  return derived;
}

bool _constantTimeEquals(List<int> first, List<int> second) {
  var difference = first.length ^ second.length;
  final length = min(first.length, second.length);
  for (var index = 0; index < length; index += 1) {
    difference |= first[index] ^ second[index];
  }
  return difference == 0;
}

@immutable
class _StoredAppLock {
  const _StoredAppLock({
    required this.type,
    required this.salt,
    required this.digest,
    required this.rounds,
    required this.biometricEnabled,
    required this.autoLockSeconds,
    this.storageVersion = 2,
  });

  final AppLockCredentialType type;
  final List<int> salt;
  final List<int> digest;
  final int rounds;
  final bool biometricEnabled;
  final int autoLockSeconds;
  final int storageVersion;

  _StoredAppLock copyWith({bool? biometricEnabled, int? autoLockSeconds}) =>
      _StoredAppLock(
        type: type,
        salt: salt,
        digest: digest,
        rounds: rounds,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
        autoLockSeconds: autoLockSeconds ?? this.autoLockSeconds,
      );

  String encode() => jsonEncode({
    'version': 2,
    'type': type.name,
    'salt': base64Encode(salt),
    'digest': base64Encode(digest),
    'rounds': rounds,
    'biometric': biometricEnabled,
    'autoLockSeconds': autoLockSeconds,
  });

  static _StoredAppLock? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic>) return null;
      final version = json['version'];
      if (version != 1 && version != 2) return null;
      final type = AppLockCredentialType.values.firstWhere(
        (candidate) => candidate.name == json['type'],
      );
      final salt = base64Decode(json['salt'] as String);
      final digest = base64Decode(json['digest'] as String);
      final rounds = json['rounds'] as int;
      final autoLockSeconds = version == 1
          ? 0
          : json['autoLockSeconds'] as int? ?? 0;
      if (salt.length != 32 ||
          digest.length != 32 ||
          rounds < 1 ||
          AppLockAutoLockOption.fromSeconds(autoLockSeconds) == null) {
        return null;
      }
      return _StoredAppLock(
        type: type,
        salt: salt,
        digest: digest,
        rounds: rounds,
        biometricEnabled: json['biometric'] == true,
        autoLockSeconds: autoLockSeconds,
        storageVersion: version,
      );
    } catch (_) {
      return null;
    }
  }
}

@immutable
class _StoredFailedAttempts {
  const _StoredFailedAttempts({this.count = 0, this.retryAt});

  final int count;
  final DateTime? retryAt;

  String encode() => jsonEncode({
    'version': 1,
    'count': count,
    'retryAtEpochMs': retryAt?.millisecondsSinceEpoch,
  });

  static _StoredFailedAttempts tryParse(String? value) {
    if (value == null || value.isEmpty) return const _StoredFailedAttempts();
    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic> || json['version'] != 1) {
        return const _StoredFailedAttempts();
      }
      final count = json['count'];
      final retryAtEpochMs = json['retryAtEpochMs'];
      if (count is! int ||
          count < 0 ||
          count > 100000 ||
          (retryAtEpochMs != null && retryAtEpochMs is! int)) {
        return const _StoredFailedAttempts();
      }
      return _StoredFailedAttempts(
        count: count,
        retryAt: retryAtEpochMs is int
            ? DateTime.fromMillisecondsSinceEpoch(retryAtEpochMs)
            : null,
      );
    } catch (_) {
      return const _StoredFailedAttempts();
    }
  }
}
