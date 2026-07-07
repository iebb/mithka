//
//  auto_download_media_controller.dart
//
//  Persists Mithka's auto-download media preferences and mirrors them into
//  TDLib's per-network autoDownloadSettings.
//

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';

class AutoDownloadMediaController extends ChangeNotifier {
  AutoDownloadMediaController._();
  static final AutoDownloadMediaController shared =
      AutoDownloadMediaController._();

  static const _mobileKey = 'autoDownload.highResImages.mobile';
  static const _wifiKey = 'autoDownload.highResImages.wifi';
  static const _highResPhotoLimit = 20 * 1024 * 1024;

  final TdClient _client = TdClient.shared;
  SharedPreferences? _prefs;
  StreamSubscription? _tdSub;
  bool _mobileHighResImages = false;
  bool _wifiHighResImages = false;
  bool _applying = false;
  bool _applyQueued = false;

  bool get mobileHighResImages => _mobileHighResImages;
  bool get wifiHighResImages => _wifiHighResImages;
  bool get isApplying => _applying;

  void initialize(SharedPreferences prefs) {
    _prefs = prefs;
    _mobileHighResImages = prefs.getBool(_mobileKey) ?? false;
    _wifiHighResImages = prefs.getBool(_wifiKey) ?? false;
    _tdSub ??= _client.subscribe().listen((update) {
      if (update.type != 'updateAuthorizationState') return;
      final state = update.obj('authorization_state');
      if (state?.type == 'authorizationStateReady') {
        unawaited(apply().catchError((_) {}));
      }
    });
  }

  Future<void> setMobileHighResImages(bool value) async {
    if (_mobileHighResImages == value) return;
    final previous = _mobileHighResImages;
    _mobileHighResImages = value;
    await _prefs?.setBool(_mobileKey, value);
    notifyListeners();
    try {
      await apply();
    } catch (_) {
      _mobileHighResImages = previous;
      await _prefs?.setBool(_mobileKey, previous);
      notifyListeners();
      rethrow;
    }
  }

  Future<void> setWifiHighResImages(bool value) async {
    if (_wifiHighResImages == value) return;
    final previous = _wifiHighResImages;
    _wifiHighResImages = value;
    await _prefs?.setBool(_wifiKey, value);
    notifyListeners();
    try {
      await apply();
    } catch (_) {
      _wifiHighResImages = previous;
      await _prefs?.setBool(_wifiKey, previous);
      notifyListeners();
      rethrow;
    }
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
        _setForNetwork('networkTypeMobile', _mobileHighResImages),
        _setForNetwork('networkTypeWiFi', _wifiHighResImages),
      ]);
    } finally {
      _applying = false;
      final rerun = _applyQueued;
      _applyQueued = false;
      notifyListeners();
      if (rerun) await apply();
    }
  }

  Future<void> _setForNetwork(String networkType, bool enabled) {
    return _client.query({
      '@type': 'setAutoDownloadSettings',
      'type': {'@type': networkType},
      'settings': _photoOnlySettings(enabled),
    });
  }

  Map<String, dynamic> _photoOnlySettings(bool enabled) {
    return {
      '@type': 'autoDownloadSettings',
      'is_auto_download_enabled': enabled,
      'max_photo_file_size': enabled ? _highResPhotoLimit : 0,
      'max_video_file_size': 0,
      'max_other_file_size': 0,
      'video_upload_bitrate': 0,
      'preload_large_videos': false,
      'preload_next_audio': false,
      'preload_stories': false,
      'use_less_data_for_calls': false,
    };
  }

  @override
  void dispose() {
    unawaited(_tdSub?.cancel());
    _tdSub = null;
    super.dispose();
  }
}
