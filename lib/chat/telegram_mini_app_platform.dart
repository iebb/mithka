import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_requests.dart';

typedef MiniAppTdQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

typedef MiniAppEventEmitter =
    Future<void> Function(String event, Map<String, dynamic> data);

class MiniAppBridgePayload {
  const MiniAppBridgePayload({required this.type, required this.data});

  final String type;
  final Map<String, dynamic> data;
}

MiniAppBridgePayload? decodeMiniAppBridgePayload(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) return null;
    final map = Map<String, dynamic>.from(decoded);
    final type = map['eventType'];
    if (type is! String || type.isEmpty) return null;
    final rawData = map['eventData'];
    if (rawData is Map) {
      return MiniAppBridgePayload(
        type: type,
        data: Map<String, dynamic>.from(rawData),
      );
    }
    if (rawData is String && rawData.isNotEmpty) {
      final parsed = jsonDecode(rawData);
      if (parsed is Map) {
        return MiniAppBridgePayload(
          type: type,
          data: Map<String, dynamic>.from(parsed),
        );
      }
    }
    return MiniAppBridgePayload(type: type, data: const {});
  } catch (_) {
    return null;
  }
}

class MiniAppPlatformService {
  MiniAppPlatformService({
    required this.botUserId,
    required this.clientId,
    MiniAppTdQuery? query,
    http.Client? httpClient,
  }) : _query = query ?? TdClient.shared.query,
       _http = httpClient ?? http.Client();

  final int botUserId;
  final int clientId;
  final MiniAppTdQuery _query;
  final http.Client _http;

  Future<Map<String, dynamic>?> attachmentMenuBot() async {
    try {
      return await _query({
        '@type': 'getAttachmentMenuBot',
        'bot_user_id': botUserId,
      });
    } catch (_) {
      return null;
    }
  }

  Future<void> setAttachmentMenuInstalled({
    required bool installed,
    required bool allowWriteAccess,
  }) => _query({
    '@type': 'toggleBotIsAddedToAttachmentMenu',
    'bot_user_id': botUserId,
    'is_added': installed,
    'allow_write_access': installed && allowWriteAccess,
  });

  Future<bool> canSendMessages() async {
    try {
      await _query({'@type': 'canBotSendMessages', 'bot_user_id': botUserId});
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> allowSendMessages() =>
      _query({'@type': 'allowBotToSendMessages', 'bot_user_id': botUserId});

  Future<void> sharePhoneNumber() =>
      _query({'@type': 'sharePhoneNumber', 'user_id': botUserId});

  Future<bool> canManageEmojiStatus() async {
    try {
      final fullInfo = await _query({
        '@type': 'getUserFullInfo',
        'user_id': botUserId,
      });
      return fullInfo.obj('bot_info')?.boolean('can_manage_emoji_status') ??
          false;
    } catch (_) {
      return false;
    }
  }

  Future<void> setCanManageEmojiStatus(bool value) => _query({
    '@type': 'toggleBotCanManageEmojiStatus',
    'bot_user_id': botUserId,
    'can_manage_emoji_status': value,
  });

  Future<void> setEmojiStatus({
    required int customEmojiId,
    required int duration,
  }) => _query({
    '@type': 'setEmojiStatus',
    'emoji_status': customEmojiId == 0
        ? null
        : {
            '@type': 'emojiStatus',
            'type': {
              '@type': 'emojiStatusTypeCustomEmoji',
              'custom_emoji_id': customEmojiId,
            },
            'expiration_date': duration <= 0
                ? 0
                : DateTime.now().millisecondsSinceEpoch ~/ 1000 + duration,
          },
  });

  Future<Object?> invokeCustomMethod(
    String method,
    Map<String, dynamic> parameters,
  ) async {
    final result = await _query({
      '@type': 'sendWebAppCustomRequest',
      'bot_user_id': botUserId,
      'method': method,
      'parameters': jsonEncode(parameters),
    });
    final value = result.str('result') ?? '';
    if (value.isEmpty) return null;
    try {
      return jsonDecode(value);
    } catch (_) {
      return value;
    }
  }

  Future<bool> checkDownload({
    required String fileName,
    required String url,
  }) async {
    try {
      await _query({
        '@type': 'checkWebAppFileDownload',
        'bot_user_id': botUserId,
        'file_name': fileName,
        'url': url,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<File> download({required String fileName, required String url}) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') {
      throw const FormatException('Mini App downloads require HTTPS');
    }
    final safeName = _safeFileName(fileName);
    final root = await getDownloadsDirectory() ?? await getTemporaryDirectory();
    final destination = await _unusedFile(root, safeName);
    final request = http.Request('GET', uri);
    final response = await _http.send(request);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Download failed with status ${response.statusCode}',
        uri: uri,
      );
    }
    final sink = destination.openWrite();
    try {
      await response.stream.pipe(sink);
    } catch (_) {
      await sink.close();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
    return destination;
  }

  Future<File> downloadTemporaryStoryMedia(String url) async {
    final uri = Uri.parse(url);
    if (uri.scheme != 'https') {
      throw const FormatException('Story sharing requires HTTPS media');
    }
    final leaf = uri.pathSegments.lastOrNull ?? 'story-media';
    final root = await getTemporaryDirectory();
    final response = await _http.send(http.Request('GET', uri));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Story media download failed with status ${response.statusCode}',
        uri: uri,
      );
    }
    var safeLeaf = _safeFileName(leaf);
    if (!safeLeaf.contains('.')) {
      final contentType = response.headers['content-type']?.toLowerCase() ?? '';
      safeLeaf = contentType.startsWith('video/')
          ? '$safeLeaf.mp4'
          : contentType.startsWith('image/')
          ? '$safeLeaf.jpg'
          : safeLeaf;
    }
    final destination = await _unusedFile(root, 'miniapp-$safeLeaf');
    const maximumBytes = 100 * 1024 * 1024;
    final advertised = response.contentLength;
    if (advertised != null && advertised > maximumBytes) {
      throw const FileSystemException('Story media is larger than 100 MB');
    }
    final sink = destination.openWrite();
    var received = 0;
    try {
      await for (final chunk in response.stream) {
        received += chunk.length;
        if (received > maximumBytes) {
          throw const FileSystemException('Story media is larger than 100 MB');
        }
        sink.add(chunk);
      }
      await sink.close();
      return destination;
    } catch (_) {
      await sink.close();
      if (await destination.exists()) await destination.delete();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> checkLocation() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    return {
      'available': enabled,
      if (enabled) 'access_requested': permission != LocationPermission.denied,
      if (enabled)
        'access_granted':
            permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse,
    };
  }

  Future<Map<String, dynamic>> requestLocation() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return const {'available': false};
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return const {'available': false};
    }
    final value = await Geolocator.getCurrentPosition();
    return {
      'available': true,
      'latitude': value.latitude,
      'longitude': value.longitude,
      'altitude': value.altitude,
      'course': value.heading,
      'speed': value.speed,
      'horizontal_accuracy': value.accuracy,
      'vertical_accuracy': value.altitudeAccuracy,
      'course_accuracy': value.headingAccuracy,
      'speed_accuracy': value.speedAccuracy,
    };
  }

  Future<void> openLocationSettings() => Geolocator.openAppSettings();

  Future<void> setInlineDraft({
    required int chatId,
    required String botUsername,
    required String query,
  }) => _query(
    setTextChatDraftRequest(
      chatId: chatId,
      date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      formattedText: {
        '@type': 'formattedText',
        'text': '@$botUsername${query.isEmpty ? '' : ' $query'}',
        'entities': const <Map<String, dynamic>>[],
      },
    ),
  );

  Future<String?> botUsername() async {
    final user = await _query({'@type': 'getUser', 'user_id': botUserId});
    final usernames = user.obj('usernames');
    final active = usernames?['active_usernames'];
    final editable = usernames?.str('editable_username');
    if (editable != null && editable.isNotEmpty) return editable;
    return active is List ? active.whereType<String>().firstOrNull : null;
  }

  void dispose() => _http.close();

  static String _safeFileName(String value) {
    final normalized = value.replaceAll(RegExp(r'[/\\\x00-\x1F]'), '_').trim();
    if (normalized.isEmpty || normalized == '.' || normalized == '..') {
      return 'download';
    }
    return normalized.length <= 180 ? normalized : normalized.substring(0, 180);
  }

  static Future<File> _unusedFile(Directory root, String name) async {
    var candidate = File('${root.path}/$name');
    if (!await candidate.exists()) return candidate;
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    final suffix = dot > 0 ? name.substring(dot) : '';
    for (var index = 2; ; index++) {
      candidate = File('${root.path}/$stem ($index)$suffix');
      if (!await candidate.exists()) return candidate;
    }
  }
}

typedef SecureRead = Future<String?> Function(String key);
typedef SecureWrite = Future<void> Function(String key, String? value);
typedef SecureReadAll = Future<Map<String, String>> Function();
typedef BiometryRead = Future<String?> Function(String key);
typedef BiometryWrite = Future<void> Function(String key, String? value);

class MiniAppScopedStorage {
  MiniAppScopedStorage({
    required this.clientId,
    required this.botUserId,
    this._preferences,
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(),
    SecureRead? secureRead,
    SecureWrite? secureWrite,
    SecureReadAll? secureReadAll,
  }) : _secureRead = secureRead ?? ((key) => secureStorage.read(key: key)),
       _secureWrite =
           secureWrite ??
           ((key, value) => value == null
               ? secureStorage.delete(key: key)
               : secureStorage.write(key: key, value: value)),
       _secureReadAll = secureReadAll ?? secureStorage.readAll;

  static const _deviceBytesMax = 5 * 1024 * 1024;
  static const _secureItemMax = 10;

  final int clientId;
  final int botUserId;
  SharedPreferences? _preferences;
  final SecureRead _secureRead;
  final SecureWrite _secureWrite;
  final SecureReadAll _secureReadAll;

  String get _prefix => 'miniapp.$clientId.$botUserId.';

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<void> saveDevice(String key, String? value) async {
    _validateKey(key);
    final prefs = await _prefs;
    if (value == null) {
      await prefs.remove('$_prefix$key');
      return;
    }
    final values = <String, String>{};
    for (final storedKey in prefs.getKeys()) {
      if (storedKey.startsWith(_prefix)) {
        values[storedKey] = prefs.getString(storedKey) ?? '';
      }
    }
    values['$_prefix$key'] = value;
    final byteCount = values.entries.fold<int>(
      0,
      (sum, item) =>
          sum + utf8.encode(item.key).length + utf8.encode(item.value).length,
    );
    if (byteCount > _deviceBytesMax) throw StateError('QUOTA_EXCEEDED');
    await prefs.setString('$_prefix$key', value);
  }

  Future<String?> readDevice(String key) async {
    _validateKey(key);
    return (await _prefs).getString('$_prefix$key');
  }

  Future<void> clearDevice() async {
    final prefs = await _prefs;
    for (final key in prefs.getKeys().where((key) => key.startsWith(_prefix))) {
      await prefs.remove(key);
    }
  }

  Future<void> saveSecure(String key, String? value) async {
    _validateKey(key);
    if (value != null) {
      final current = await _secureReadAll();
      final keys = current.keys.where((key) => key.startsWith(_prefix)).toSet();
      if (!keys.contains('$_prefix$key') && keys.length >= _secureItemMax) {
        throw StateError('QUOTA_EXCEEDED');
      }
    }
    await _secureWrite('$_prefix$key', value);
  }

  Future<String?> readSecure(String key) async {
    _validateKey(key);
    return _secureRead('$_prefix$key');
  }

  Future<void> clearSecure() async {
    final current = await _secureReadAll();
    for (final key in current.keys.where((key) => key.startsWith(_prefix))) {
      await _secureWrite(key, null);
    }
  }

  static void _validateKey(String key) {
    if (key.isEmpty ||
        key.length > 256 ||
        key.contains(RegExp(r'[\x00-\x1F]'))) {
      throw const FormatException('KEY_INVALID');
    }
  }
}

class MiniAppBiometryController {
  MiniAppBiometryController({
    required this.clientId,
    required this.botUserId,
    this._preferences,
    FlutterSecureStorage secureStorage = const FlutterSecureStorage(
      iOptions: IOSOptions(
        accessibility: KeychainAccessibility.passcode,
        accessControlFlags: [AccessControlFlag.biometryCurrentSet],
      ),
      aOptions: AndroidOptions.biometric(
        enforceBiometrics: true,
        biometricType: AndroidBiometricType.strongBiometricOnly,
        biometricPromptTitle: 'Authenticate with biometrics',
        biometricPromptSubtitle: 'Confirm access for this Mini App',
        biometricPromptNegativeButton: 'Cancel',
      ),
    ),
    BiometryRead? secureRead,
    BiometryWrite? secureWrite,
    bool? supported,
    this.biometricType = 'unknown',
  }) : _secureRead = secureRead ?? ((key) => secureStorage.read(key: key)),
       _secureWrite =
           secureWrite ??
           ((key, value) => value == null
               ? secureStorage.delete(key: key)
               : secureStorage.write(key: key, value: value)),
       _supported = supported ?? (Platform.isAndroid || Platform.isIOS);

  final int clientId;
  final int botUserId;
  SharedPreferences? _preferences;
  final BiometryRead _secureRead;
  final BiometryWrite _secureWrite;
  final bool _supported;
  final String biometricType;

  String get _prefix => 'miniapp.biometry.$clientId.$botUserId.';
  String get _tokenKey => '${_prefix}token';
  String get _requestedKey => '${_prefix}requested';
  String get _grantedKey => '${_prefix}granted';
  String get _tokenSavedKey => '${_prefix}token_saved';
  String get _deviceIdKey => '${_prefix}device_id';

  Future<SharedPreferences> get _prefs async =>
      _preferences ??= await SharedPreferences.getInstance();

  Future<Map<String, dynamic>> info() async {
    final prefs = await _prefs;
    var deviceId = prefs.getString(_deviceIdKey);
    if (deviceId == null || deviceId.isEmpty) {
      final random = math.Random.secure();
      final bytes = List<int>.generate(24, (_) => random.nextInt(256));
      deviceId = base64UrlEncode(bytes).replaceAll('=', '');
      await prefs.setString(_deviceIdKey, deviceId);
    }
    return {
      'available': _supported,
      'type': _supported ? biometricType : 'unknown',
      'access_requested': prefs.getBool(_requestedKey) ?? false,
      'access_granted': _supported && (prefs.getBool(_grantedKey) ?? false),
      'token_saved': prefs.getBool(_tokenSavedKey) ?? false,
      'device_id': deviceId,
    };
  }

  Future<void> setAccess({required bool granted}) async {
    final prefs = await _prefs;
    await prefs.setBool(_requestedKey, true);
    await prefs.setBool(_grantedKey, _supported && granted);
  }

  Future<bool> updateToken(String token) async {
    if (token.length > 1024) return false;
    final prefs = await _prefs;
    if (!_supported || !(prefs.getBool(_grantedKey) ?? false)) return false;
    try {
      if (token.isEmpty) {
        if (prefs.getBool(_tokenSavedKey) ?? false) {
          final current = await _secureRead(_tokenKey);
          if (current == null) return false;
        }
        await _secureWrite(_tokenKey, null);
      } else {
        await _secureWrite(_tokenKey, token);
        final verified = await _secureRead(_tokenKey);
        if (verified != token) {
          await _secureWrite(_tokenKey, null);
          return false;
        }
      }
      await prefs.setBool(_tokenSavedKey, token.isNotEmpty);
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<String?> authenticate() async {
    final prefs = await _prefs;
    if (!_supported ||
        !(prefs.getBool(_grantedKey) ?? false) ||
        !(prefs.getBool(_tokenSavedKey) ?? false)) {
      return null;
    }
    try {
      return await _secureRead(_tokenKey);
    } catch (_) {
      return null;
    }
  }
}

enum MiniAppMotionKind { accelerometer, gyroscope, orientation }

class MiniAppMotionController {
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<AccelerometerEvent>? _orientationAcceleration;
  StreamSubscription<MagnetometerEvent>? _orientationMagnetometer;
  Timer? _orientationTimer;
  AccelerometerEvent? _acceleration;
  MagnetometerEvent? _magnetic;

  bool get isActive =>
      _accelerometerSubscription != null ||
      _gyroscopeSubscription != null ||
      _orientationTimer?.isActive == true;

  Future<void> start({
    required MiniAppMotionKind kind,
    required int refreshRate,
    required MiniAppEventEmitter emit,
    bool needAbsolute = false,
  }) async {
    final interval = Duration(milliseconds: refreshRate.clamp(20, 1000));
    switch (kind) {
      case MiniAppMotionKind.accelerometer:
        await _accelerometerSubscription?.cancel();
        _accelerometerSubscription =
            accelerometerEventStream(samplingPeriod: interval).listen(
              (event) => emit('accelerometer_changed', {
                'x': event.x,
                'y': event.y,
                'z': event.z,
              }),
              onError: (_) =>
                  emit('accelerometer_failed', {'error': 'UNSUPPORTED'}),
            );
        await emit('accelerometer_started', const {});
      case MiniAppMotionKind.gyroscope:
        await _gyroscopeSubscription?.cancel();
        _gyroscopeSubscription = gyroscopeEventStream(samplingPeriod: interval)
            .listen(
              (event) => emit('gyroscope_changed', {
                'x': event.x,
                'y': event.y,
                'z': event.z,
              }),
              onError: (_) =>
                  emit('gyroscope_failed', {'error': 'UNSUPPORTED'}),
            );
        await emit('gyroscope_started', const {});
      case MiniAppMotionKind.orientation:
        await _cancelOrientation();
        _orientationAcceleration = accelerometerEventStream(
          samplingPeriod: interval,
        ).listen((event) => _acceleration = event);
        if (needAbsolute) {
          _orientationMagnetometer = magnetometerEventStream(
            samplingPeriod: interval,
          ).listen((event) => _magnetic = event);
        }
        _orientationTimer = Timer.periodic(interval, (_) {
          final acceleration = _acceleration;
          final magnetic = _magnetic;
          if (acceleration == null || (needAbsolute && magnetic == null)) {
            return;
          }
          final beta = math.atan2(
            acceleration.y,
            math.sqrt(
              acceleration.x * acceleration.x + acceleration.z * acceleration.z,
            ),
          );
          final gamma = math.atan2(-acceleration.x, acceleration.z);
          final alpha = magnetic == null
              ? 0.0
              : math.atan2(magnetic.y, magnetic.x);
          emit('device_orientation_changed', {
            'alpha': alpha,
            'beta': beta,
            'gamma': gamma,
            'absolute': needAbsolute && magnetic != null,
          });
        });
        await emit('device_orientation_started', const {});
    }
  }

  Future<void> stop({
    required MiniAppEventEmitter emit,
    MiniAppMotionKind? kind,
    bool notify = true,
  }) async {
    switch (kind) {
      case MiniAppMotionKind.accelerometer:
        await _accelerometerSubscription?.cancel();
        _accelerometerSubscription = null;
      case MiniAppMotionKind.gyroscope:
        await _gyroscopeSubscription?.cancel();
        _gyroscopeSubscription = null;
      case MiniAppMotionKind.orientation:
        await _cancelOrientation();
      case null:
        await _accelerometerSubscription?.cancel();
        await _gyroscopeSubscription?.cancel();
        _accelerometerSubscription = null;
        _gyroscopeSubscription = null;
        await _cancelOrientation();
    }
    if (!notify || kind == null) return;
    await emit(switch (kind) {
      MiniAppMotionKind.accelerometer => 'accelerometer_stopped',
      MiniAppMotionKind.gyroscope => 'gyroscope_stopped',
      MiniAppMotionKind.orientation => 'device_orientation_stopped',
    }, const {});
  }

  Future<void> dispose(MiniAppEventEmitter emit) =>
      stop(emit: emit, notify: false);

  Future<void> _cancelOrientation() async {
    await _orientationAcceleration?.cancel();
    await _orientationMagnetometer?.cancel();
    _orientationTimer?.cancel();
    _orientationAcceleration = null;
    _orientationMagnetometer = null;
    _orientationTimer = null;
    _acceleration = null;
    _magnetic = null;
  }
}
