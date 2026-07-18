//
//  auto_download_media_controller.dart
//
//  Persists Mithka's auto-download media preferences and mirrors them into
//  TDLib's per-network autoDownloadSettings.
//

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

@immutable
class AutoDownloadProfile {
  const AutoDownloadProfile({
    required this.enabled,
    required this.maxPhotoBytes,
    required this.maxVideoBytes,
    required this.maxOtherBytes,
    required this.videoUploadBitrate,
    required this.preloadLargeVideos,
    required this.preloadNextAudio,
    required this.preloadStories,
    required this.useLessDataForCalls,
  });

  const AutoDownloadProfile.low()
    : enabled = false,
      maxPhotoBytes = 0,
      maxVideoBytes = 0,
      maxOtherBytes = 0,
      videoUploadBitrate = 0,
      preloadLargeVideos = false,
      preloadNextAudio = false,
      preloadStories = false,
      useLessDataForCalls = true;

  const AutoDownloadProfile.medium()
    : enabled = true,
      maxPhotoBytes = 5 * 1024 * 1024,
      maxVideoBytes = 20 * 1024 * 1024,
      maxOtherBytes = 10 * 1024 * 1024,
      videoUploadBitrate = 1200,
      preloadLargeVideos = false,
      preloadNextAudio = true,
      preloadStories = false,
      useLessDataForCalls = true;

  const AutoDownloadProfile.high()
    : enabled = true,
      maxPhotoBytes = 20 * 1024 * 1024,
      maxVideoBytes = 100 * 1024 * 1024,
      maxOtherBytes = 50 * 1024 * 1024,
      videoUploadBitrate = 2500,
      preloadLargeVideos = true,
      preloadNextAudio = true,
      preloadStories = true,
      useLessDataForCalls = false;

  final bool enabled;
  final int maxPhotoBytes;
  final int maxVideoBytes;
  final int maxOtherBytes;
  final int videoUploadBitrate;
  final bool preloadLargeVideos;
  final bool preloadNextAudio;
  final bool preloadStories;
  final bool useLessDataForCalls;

  AutoDownloadProfile copyWith({
    bool? enabled,
    int? maxPhotoBytes,
    int? maxVideoBytes,
    int? maxOtherBytes,
    int? videoUploadBitrate,
    bool? preloadLargeVideos,
    bool? preloadNextAudio,
    bool? preloadStories,
    bool? useLessDataForCalls,
  }) => AutoDownloadProfile(
    enabled: enabled ?? this.enabled,
    maxPhotoBytes: maxPhotoBytes ?? this.maxPhotoBytes,
    maxVideoBytes: maxVideoBytes ?? this.maxVideoBytes,
    maxOtherBytes: maxOtherBytes ?? this.maxOtherBytes,
    videoUploadBitrate: videoUploadBitrate ?? this.videoUploadBitrate,
    preloadLargeVideos: preloadLargeVideos ?? this.preloadLargeVideos,
    preloadNextAudio: preloadNextAudio ?? this.preloadNextAudio,
    preloadStories: preloadStories ?? this.preloadStories,
    useLessDataForCalls: useLessDataForCalls ?? this.useLessDataForCalls,
  );

  Map<String, dynamic> toTdJson() => {
    '@type': 'autoDownloadSettings',
    'is_auto_download_enabled': enabled,
    'max_photo_file_size': enabled ? maxPhotoBytes : 0,
    'max_video_file_size': enabled ? maxVideoBytes : 0,
    'max_other_file_size': enabled ? maxOtherBytes : 0,
    'video_upload_bitrate': videoUploadBitrate,
    'preload_large_videos': enabled && preloadLargeVideos,
    'preload_next_audio': enabled && preloadNextAudio,
    'preload_stories': enabled && preloadStories,
    'use_less_data_for_calls': useLessDataForCalls,
  };

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'maxPhotoBytes': maxPhotoBytes,
    'maxVideoBytes': maxVideoBytes,
    'maxOtherBytes': maxOtherBytes,
    'videoUploadBitrate': videoUploadBitrate,
    'preloadLargeVideos': preloadLargeVideos,
    'preloadNextAudio': preloadNextAudio,
    'preloadStories': preloadStories,
    'useLessDataForCalls': useLessDataForCalls,
  };

  factory AutoDownloadProfile.fromJson(
    Map<String, dynamic> value,
    AutoDownloadProfile fallback,
  ) => AutoDownloadProfile(
    enabled: value['enabled'] as bool? ?? fallback.enabled,
    maxPhotoBytes:
        (value['maxPhotoBytes'] as num?)?.toInt() ?? fallback.maxPhotoBytes,
    maxVideoBytes:
        (value['maxVideoBytes'] as num?)?.toInt() ?? fallback.maxVideoBytes,
    maxOtherBytes:
        (value['maxOtherBytes'] as num?)?.toInt() ?? fallback.maxOtherBytes,
    videoUploadBitrate:
        (value['videoUploadBitrate'] as num?)?.toInt() ??
        fallback.videoUploadBitrate,
    preloadLargeVideos:
        value['preloadLargeVideos'] as bool? ?? fallback.preloadLargeVideos,
    preloadNextAudio:
        value['preloadNextAudio'] as bool? ?? fallback.preloadNextAudio,
    preloadStories: value['preloadStories'] as bool? ?? fallback.preloadStories,
    useLessDataForCalls:
        value['useLessDataForCalls'] as bool? ?? fallback.useLessDataForCalls,
  );
}

class AutoDownloadMediaController extends ChangeNotifier {
  AutoDownloadMediaController._();
  static final AutoDownloadMediaController shared =
      AutoDownloadMediaController._();

  static const _mobileKey = 'autoDownload.highResImages.mobile';
  static const _wifiKey = 'autoDownload.highResImages.wifi';
  static const _profilesKey = 'autoDownload.profiles.v2';
  static const _highResPhotoLimit = 20 * 1024 * 1024;

  final TdClient _client = TdClient.shared;
  SharedPreferences? _prefs;
  StreamSubscription? _tdSub;
  bool _mobileHighResImages = false;
  bool _wifiHighResImages = false;
  AutoDownloadProfile _mobile = const AutoDownloadProfile.medium();
  AutoDownloadProfile _wifi = const AutoDownloadProfile.high();
  AutoDownloadProfile _roaming = const AutoDownloadProfile.low();
  bool _applying = false;
  bool _applyQueued = false;

  bool get mobileHighResImages => _mobileHighResImages;
  bool get wifiHighResImages => _wifiHighResImages;
  bool get isApplying => _applying;
  AutoDownloadProfile get mobile => _mobile;
  AutoDownloadProfile get wifi => _wifi;
  AutoDownloadProfile get roaming => _roaming;

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _mobileHighResImages = prefs.getBool(_mobileKey) ?? false;
    _wifiHighResImages = prefs.getBool(_wifiKey) ?? false;
    _loadProfiles(prefs.getString(_profilesKey));
    _tdSub ??= _client.subscribe().listen((update) {
      if (update.type != 'updateAuthorizationState') return;
      final state = update.obj('authorization_state');
      if (state?.type == 'authorizationStateReady') {
        unawaited(apply().catchError((_) {}));
      }
    });
  }

  void _loadProfiles(String? encoded) {
    if (encoded != null && encoded.isNotEmpty) {
      try {
        final value = jsonDecode(encoded);
        if (value is Map) {
          final json = Map<String, dynamic>.from(value);
          _mobile = AutoDownloadProfile.fromJson(
            Map<String, dynamic>.from(json['mobile'] as Map? ?? const {}),
            _mobile,
          );
          _wifi = AutoDownloadProfile.fromJson(
            Map<String, dynamic>.from(json['wifi'] as Map? ?? const {}),
            _wifi,
          );
          _roaming = AutoDownloadProfile.fromJson(
            Map<String, dynamic>.from(json['roaming'] as Map? ?? const {}),
            _roaming,
          );
        }
      } catch (_) {}
    } else {
      _mobile = _mobile.copyWith(
        enabled: _mobileHighResImages,
        maxPhotoBytes: _mobileHighResImages ? _highResPhotoLimit : 0,
      );
      _wifi = _wifi.copyWith(
        enabled: _wifiHighResImages,
        maxPhotoBytes: _wifiHighResImages ? _highResPhotoLimit : 0,
      );
    }
    _syncLegacyFlags();
  }

  void _syncLegacyFlags() {
    _mobileHighResImages = _mobile.enabled && _mobile.maxPhotoBytes > 0;
    _wifiHighResImages = _wifi.enabled && _wifi.maxPhotoBytes > 0;
  }

  Future<void> setProfile(String networkType, AutoDownloadProfile value) async {
    final previous = switch (networkType) {
      'networkTypeMobile' => _mobile,
      'networkTypeWiFi' => _wifi,
      'networkTypeMobileRoaming' => _roaming,
      _ => throw ArgumentError.value(networkType, 'networkType'),
    };
    switch (networkType) {
      case 'networkTypeMobile':
        _mobile = value;
      case 'networkTypeWiFi':
        _wifi = value;
      case 'networkTypeMobileRoaming':
        _roaming = value;
    }
    _syncLegacyFlags();
    await _persistProfiles();
    notifyListeners();
    try {
      await _setForNetwork(networkType, value);
    } catch (_) {
      switch (networkType) {
        case 'networkTypeMobile':
          _mobile = previous;
        case 'networkTypeWiFi':
          _wifi = previous;
        case 'networkTypeMobileRoaming':
          _roaming = previous;
      }
      _syncLegacyFlags();
      await _persistProfiles();
      notifyListeners();
      rethrow;
    }
  }

  Future<void> _persistProfiles() async {
    await _prefs?.setString(
      _profilesKey,
      jsonEncode({
        'mobile': _mobile.toJson(),
        'wifi': _wifi.toJson(),
        'roaming': _roaming.toJson(),
      }),
    );
    await _prefs?.setBool(_mobileKey, _mobileHighResImages);
    await _prefs?.setBool(_wifiKey, _wifiHighResImages);
  }

  Future<void> setMobileHighResImages(bool value) async {
    if (_mobileHighResImages == value) return;
    await setProfile(
      'networkTypeMobile',
      _mobile.copyWith(
        enabled:
            value || _mobile.maxVideoBytes > 0 || _mobile.maxOtherBytes > 0,
        maxPhotoBytes: value ? _highResPhotoLimit : 0,
      ),
    );
  }

  Future<void> setWifiHighResImages(bool value) async {
    if (_wifiHighResImages == value) return;
    await setProfile(
      'networkTypeWiFi',
      _wifi.copyWith(
        enabled: value || _wifi.maxVideoBytes > 0 || _wifi.maxOtherBytes > 0,
        maxPhotoBytes: value ? _highResPhotoLimit : 0,
      ),
    );
  }

  Future<void> apply() async {
    if (_applying) {
      _applyQueued = true;
      return;
    }
    _applying = true;
    notifyListeners();
    try {
      await Future.wait([
        _setForNetwork('networkTypeMobile', _mobile),
        _setForNetwork('networkTypeWiFi', _wifi),
        _setForNetwork('networkTypeMobileRoaming', _roaming),
      ]);
    } finally {
      _applying = false;
      final rerun = _applyQueued;
      _applyQueued = false;
      notifyListeners();
      if (rerun) await apply();
    }
  }

  Future<void> _setForNetwork(String networkType, AutoDownloadProfile profile) {
    return _client.query({
      '@type': 'setAutoDownloadSettings',
      'type': {'@type': networkType},
      'settings': profile.toTdJson(),
    });
  }

  @override
  void dispose() {
    unawaited(_tdSub?.cancel());
    _tdSub = null;
    super.dispose();
  }
}
