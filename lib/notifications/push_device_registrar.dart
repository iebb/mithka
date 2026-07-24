import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'notification_preferences.dart';

class PushDeviceRegistrar {
  PushDeviceRegistrar._();
  static final PushDeviceRegistrar shared = PushDeviceRegistrar._();

  static const _channel = MethodChannel('mithka/push');

  final TdClient _client = TdClient.shared;
  final NotificationPreferences _preferences = NotificationPreferences.shared;
  StreamSubscription? _sub;
  StreamSubscription<int>? _accountSub;
  String? _deviceToken;
  String? _lastRegistrationSignature;
  bool _running = false;
  bool _registering = false;

  Future<void> start() async {
    if (_running || !Platform.isIOS) return;
    _running = true;
    _preferences.addListener(_preferencesChanged);
    _channel.setMethodCallHandler(_handleNativeMethod);
    _sub = _client.subscribe().listen(_handleTdUpdate);
    _accountSub = _client.subscribeActiveSlotChanges().listen((_) {
      if (_preferences.accountMode != NotificationAccountMode.current) return;
      _lastRegistrationSignature = null;
      unawaited(_registerIfPossible());
    });
    try {
      final token = await _channel.invokeMethod<String>(
        'registerForRemoteNotifications',
      );
      _setDeviceToken(token);
    } catch (error) {
      debugPrint('APNs registration request failed: $error');
    }
    unawaited(_registerIfPossible());
  }

  void _preferencesChanged() {
    _lastRegistrationSignature = null;
    unawaited(_registerIfPossible());
  }

  Future<dynamic> _handleNativeMethod(MethodCall call) async {
    switch (call.method) {
      case 'deviceToken':
        _setDeviceToken(call.arguments as String?);
        unawaited(_registerIfPossible());
      case 'registrationError':
        debugPrint('APNs registration failed: ${call.arguments}');
    }
  }

  void _handleTdUpdate(Map<String, dynamic> update) {
    if (update.type != 'updateAuthorizationState') return;
    final state = update.obj('authorization_state');
    if (state?.type == 'authorizationStateReady') {
      unawaited(_registerIfPossible());
    }
  }

  void _setDeviceToken(String? token) {
    final normalized = token?.trim();
    if (normalized == null || normalized.isEmpty) return;
    if (_deviceToken == normalized) return;
    _deviceToken = normalized;
    _lastRegistrationSignature = null;
  }

  Future<void> _registerIfPossible() async {
    final token = _deviceToken;
    if (token == null || _registering) return;
    _registering = true;
    try {
      final readyUsersByClient = await _readyUsersByClient();
      final usersByClient = <int, int>{
        for (final entry in readyUsersByClient.entries)
          if (_preferences.receivesNotificationsFrom(
            userId: entry.value,
            isActiveAccount: entry.key == _client.activeClientId,
          ))
            entry.key: entry.value,
      };
      if (usersByClient.isEmpty) return;
      final userIds = usersByClient.values.toSet().toList()..sort();
      final signature = '$token|$kDebugMode|${userIds.join(',')}';
      if (_lastRegistrationSignature == signature) return;

      for (final entry in usersByClient.entries) {
        final otherUserIds = userIds
            .where((userId) => userId != entry.value)
            .toList(growable: false);
        await _client
            .queryTo({
              '@type': 'registerDevice',
              'device_token': {
                '@type': 'deviceTokenApplePush',
                'device_token': token,
                'is_app_sandbox': kDebugMode,
              },
              'other_user_ids': otherUserIds,
            }, entry.key)
            .timeout(const Duration(seconds: 8));
      }
      _lastRegistrationSignature = signature;
      debugPrint('Registered APNs device token with TDLib');
    } catch (error) {
      debugPrint('TDLib APNs device registration failed: $error');
    } finally {
      _registering = false;
    }
  }

  Future<Map<int, int>> _readyUsersByClient() async {
    final usersByClient = <int, int>{};
    for (final slot in _client.configuredSlots) {
      final clientId = _client.clientId(slot);
      if (clientId == null) continue;
      try {
        final state = await _client
            .queryTo({'@type': 'getAuthorizationState'}, clientId)
            .timeout(const Duration(seconds: 2));
        if (state.type != 'authorizationStateReady') continue;
        final me = await _client
            .queryTo({'@type': 'getMe'}, clientId)
            .timeout(const Duration(seconds: 3));
        final userId = me.int64('id');
        if (userId != null) usersByClient[clientId] = userId;
      } catch (_) {
        continue;
      }
    }
    return usersByClient;
  }

  Future<void> stop() async {
    _preferences.removeListener(_preferencesChanged);
    await _sub?.cancel();
    _sub = null;
    await _accountSub?.cancel();
    _accountSub = null;
    _running = false;
  }
}
