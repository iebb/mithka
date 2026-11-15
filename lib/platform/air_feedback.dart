import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';

/// AirFeedback, AirBuild's feedback inbox, alongside Sentry.
///
/// The request mirrors AirFeedback's `AppFeedback.swift` template: one JSON
/// `POST` with the public ingest key as a bearer token. The key only allows
/// submitting reports, so it may ship in the app. Dart clients send no App
/// Attest proof; AirFeedback stores their entries as unverified.
abstract final class AirFeedbackConfig {
  static final endpoint = Uri.parse(
    'https://apps.air.build/v1/ingest/feedback',
  );
  static const appKey =
      'ak_production_Knmbmr-NVDAz2VycHPJpjcU06Cr73h9T-6qdA9PrW70';

  /// AirFeedback's ingest limit for the message text.
  static const maximumMessageLength = 4000;
}

/// What a report says about the app and device, as `AppFeedback.swift`
/// sends it. No account or stable device identifier.
class AirFeedbackDeviceInfo {
  const AirFeedbackDeviceInfo({
    required this.appVersion,
    required this.appBuild,
    required this.deviceModel,
    required this.osVersion,
    required this.locale,
  });

  final String appVersion;
  final String appBuild;
  final String deviceModel;
  final String osVersion;
  final String locale;

  static Future<AirFeedbackDeviceInfo> current() async {
    var version = '';
    var build = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      build = info.buildNumber;
    } catch (_) {}
    return AirFeedbackDeviceInfo(
      appVersion: version,
      appBuild: build,
      deviceModel: _safe(_deviceModel),
      osVersion: _safe(_osVersion),
      locale: _safe(() => ui.PlatformDispatcher.instance.locale.toString()),
    );
  }
}

/// Thrown when AirFeedback did not take the report.
class AirFeedbackException implements Exception {
  const AirFeedbackException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => 'AirFeedbackException($statusCode): $message';
}

class AirFeedbackClient {
  AirFeedbackClient({
    this.httpClient,
    Uri? endpoint,
    String? appKey,
    Future<AirFeedbackDeviceInfo> Function()? deviceInfo,
    this.timeout = const Duration(seconds: 10),
  }) : endpoint = endpoint ?? AirFeedbackConfig.endpoint,
       appKey = appKey ?? AirFeedbackConfig.appKey,
       _deviceInfo = deviceInfo ?? AirFeedbackDeviceInfo.current;

  /// Injected for tests; a fresh client per send otherwise.
  final http.Client? httpClient;
  final Uri endpoint;
  final String appKey;
  final Future<AirFeedbackDeviceInfo> Function() _deviceInfo;

  /// The whole send, device details included, gives up after this.
  final Duration timeout;

  /// The JSON body `AppFeedback.swift` posts. The form has no screenshots,
  /// so `images` is always empty.
  static Map<String, Object> requestBody(
    String message,
    AirFeedbackDeviceInfo info,
  ) => {
    'message': truncateMessage(message),
    'appVersion': info.appVersion,
    'appBuild': info.appBuild,
    'deviceModel': info.deviceModel,
    'osVersion': info.osVersion,
    'locale': info.locale,
    'images': const <Object>[],
  };

  /// Keeps the message within AirFeedback's limit without splitting a
  /// surrogate pair.
  static String truncateMessage(String message) {
    const limit = AirFeedbackConfig.maximumMessageLength;
    if (message.length <= limit) return message;
    var end = limit;
    final last = message.codeUnitAt(end - 1);
    if (last >= 0xD800 && last <= 0xDBFF) end -= 1;
    return message.substring(0, end);
  }

  /// Sends one report. Returns the stored entry's id when AirFeedback
  /// answers with one; throws [AirFeedbackException] or [TimeoutException]
  /// otherwise.
  Future<String?> send(String message) => _send(message).timeout(timeout);

  Future<String?> _send(String message) async {
    final info = await _deviceInfo();
    final client = httpClient ?? http.Client();
    try {
      final response = await client.post(
        endpoint,
        headers: {
          'Authorization': 'Bearer $appKey',
          'Content-Type': 'application/json',
        },
        body: utf8.encode(jsonEncode(requestBody(message, info))),
      );
      final decoded = _decode(response.bodyBytes);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final reason = decoded is Map ? decoded['reason'] : null;
        throw AirFeedbackException(
          reason is String
              ? reason
              : 'The server answered ${response.statusCode}.',
          statusCode: response.statusCode,
        );
      }
      final id = decoded is Map ? decoded['id'] : null;
      return id is String && id.isNotEmpty ? id : null;
    } finally {
      if (httpClient == null) client.close();
    }
  }

  static Object? _decode(List<int> bytes) {
    try {
      return jsonDecode(utf8.decode(bytes));
    } catch (_) {
      return null;
    }
  }
}

String _safe(String Function() read) {
  try {
    return read();
  } catch (_) {
    return '';
  }
}

/// The hardware identifier (`iPhone17,2`, `Mac14,2`, `Pixel 8`), which is
/// what a bug report needs.
String _deviceModel() {
  if (Platform.isIOS) return _sysctlString('hw.machine');
  if (Platform.isMacOS) return _sysctlString('hw.model');
  if (Platform.isAndroid) {
    final manufacturer = _androidProperty('ro.product.manufacturer');
    final model = _androidProperty('ro.product.model');
    if (manufacturer.isEmpty ||
        model.toLowerCase().startsWith(manufacturer.toLowerCase())) {
      return model;
    }
    return '$manufacturer $model';
  }
  return '';
}

/// `iOS 17.1`, `macOS 14.1`, `Android 14`, like `AppFeedback.swift`'s
/// system name and version.
String _osVersion() {
  if (Platform.isAndroid) {
    return 'Android ${_androidProperty('ro.build.version.release')}'.trim();
  }
  final raw = Platform.operatingSystemVersion.trim();
  if (Platform.isIOS || Platform.isMacOS) {
    // Darwin reports `Version 17.1 (Build 21B80)`.
    final version = RegExp(r'Version ([0-9.]+)').firstMatch(raw)?.group(1);
    return '${Platform.isIOS ? 'iOS' : 'macOS'} ${version ?? raw}';
  }
  return '${Platform.operatingSystem} $raw'.trim();
}

typedef _SysctlByNameNative =
    Int32 Function(
      Pointer<Utf8> name,
      Pointer<Void> value,
      Pointer<Size> length,
      Pointer<Void> newValue,
      Size newLength,
    );
typedef _SysctlByName =
    int Function(
      Pointer<Utf8> name,
      Pointer<Void> value,
      Pointer<Size> length,
      Pointer<Void> newValue,
      int newLength,
    );

String _sysctlString(String key) {
  final sysctl = DynamicLibrary.process()
      .lookupFunction<_SysctlByNameNative, _SysctlByName>('sysctlbyname');
  return using((arena) {
    final name = key.toNativeUtf8(allocator: arena);
    final length = arena<Size>();
    if (sysctl(name, nullptr, length, nullptr, 0) != 0 || length.value == 0) {
      return '';
    }
    final buffer = arena<Uint8>(length.value);
    if (sysctl(name, buffer.cast(), length, nullptr, 0) != 0) return '';
    return buffer.cast<Utf8>().toDartString();
  });
}

typedef _SystemPropertyGetNative =
    Int32 Function(Pointer<Utf8> name, Pointer<Utf8> value);
typedef _SystemPropertyGet =
    int Function(Pointer<Utf8> name, Pointer<Utf8> value);

String _androidProperty(String key) {
  final get = DynamicLibrary.open('libc.so')
      .lookupFunction<_SystemPropertyGetNative, _SystemPropertyGet>(
        '__system_property_get',
      );
  return using((arena) {
    // PROP_VALUE_MAX is 92 bytes, terminator included.
    final value = arena<Uint8>(92).cast<Utf8>();
    final length = get(key.toNativeUtf8(allocator: arena), value);
    return length > 0 ? value.toDartString(length: length).trim() : '';
  });
}
