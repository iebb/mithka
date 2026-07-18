import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

enum AppLockCredentialType { pin, gesture }

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
    this.hashRounds = _defaultHashRounds,
    bool? platformSupportsBiometrics,
  }) : _secureRead = secureRead ?? _defaultSecureRead,
       _secureWrite = secureWrite ?? _defaultSecureWrite,
       _biometricProbe = biometricProbe ?? _defaultBiometricProbe,
       _biometricAuthenticate =
           biometricAuthenticate ?? _defaultBiometricAuthenticate,
       _platformSupportsBiometrics =
           platformSupportsBiometrics ?? _defaultPlatformSupportsBiometrics;

  static final LocalAppLockController shared = LocalAppLockController();

  static const _storageKey = 'mithka.local_app_lock.v1';
  static const _defaultHashRounds = 120000;
  static const _pinLength = 4;
  static const _minimumGestureNodes = 4;
  static const _storage = FlutterSecureStorage();

  final AppLockSecureRead _secureRead;
  final AppLockSecureWrite _secureWrite;
  final AppLockBiometricProbe _biometricProbe;
  final AppLockBiometricAuthenticate _biometricAuthenticate;
  final int hashRounds;
  final bool _platformSupportsBiometrics;

  _StoredAppLock? _stored;
  bool _initialized = false;
  bool _locked = false;
  bool _authenticatingBiometrics = false;
  bool _biometricAvailable = false;
  AppLockBiometricKind _biometricKind = AppLockBiometricKind.generic;
  int _lockEpoch = 0;

  bool get initialized => _initialized;
  bool get enabled => _stored != null;
  bool get locked => _locked;
  bool get authenticatingBiometrics => _authenticatingBiometrics;
  bool get biometricAvailable => _biometricAvailable;
  bool get biometricEnabled => _stored?.biometricEnabled ?? false;
  AppLockBiometricKind get biometricKind => _biometricKind;
  AppLockCredentialType? get credentialType => _stored?.type;
  int get lockEpoch => _lockEpoch;

  static int get pinLength => _pinLength;
  static int get minimumGestureNodes => _minimumGestureNodes;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final value = await _secureRead(_storageKey);
      _stored = _StoredAppLock.tryParse(value);
      if (_stored != null) {
        _locked = true;
        _lockEpoch = 1;
      }
    } catch (error) {
      debugPrint('Local app lock could not read secure storage: $error');
    }
    _initialized = true;
    await refreshBiometricAvailability();
    notifyListeners();
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
    );
    await _persist(next);
    _stored = next;
    _locked = false;
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
    final verified = await verifyCredential(credential);
    if (verified) unlock();
    return verified;
  }

  void lock() {
    if (!enabled || _locked || _authenticatingBiometrics) return;
    _locked = true;
    _lockEpoch += 1;
    notifyListeners();
  }

  void unlock() {
    if (!_locked) return;
    _locked = false;
    notifyListeners();
  }

  Future<void> disable() async {
    await _secureWrite(_storageKey, null);
    _stored = null;
    _locked = false;
    _authenticatingBiometrics = false;
    notifyListeners();
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
      if (unlockOnSuccess) unlock();
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
  });

  final AppLockCredentialType type;
  final List<int> salt;
  final List<int> digest;
  final int rounds;
  final bool biometricEnabled;

  _StoredAppLock copyWith({bool? biometricEnabled}) => _StoredAppLock(
    type: type,
    salt: salt,
    digest: digest,
    rounds: rounds,
    biometricEnabled: biometricEnabled ?? this.biometricEnabled,
  );

  String encode() => jsonEncode({
    'version': 1,
    'type': type.name,
    'salt': base64Encode(salt),
    'digest': base64Encode(digest),
    'rounds': rounds,
    'biometric': biometricEnabled,
  });

  static _StoredAppLock? tryParse(String? value) {
    if (value == null || value.isEmpty) return null;
    try {
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic> || json['version'] != 1) return null;
      final type = AppLockCredentialType.values.firstWhere(
        (candidate) => candidate.name == json['type'],
      );
      final salt = base64Decode(json['salt'] as String);
      final digest = base64Decode(json['digest'] as String);
      final rounds = json['rounds'] as int;
      if (salt.length != 32 || digest.length != 32 || rounds < 1) return null;
      return _StoredAppLock(
        type: type,
        salt: salt,
        digest: digest,
        rounds: rounds,
        biometricEnabled: json['biometric'] == true,
      );
    } catch (_) {
      return null;
    }
  }
}
