//
//  notification_controller.dart
//
//  Local notifications driven by TDLib updates. This is not a push service:
//  it can notify while the Flutter/TDLib process is alive in the background,
//  but APNs/FCM would still be needed for killed-app delivery.
//

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../app/chat_deep_link_controller.dart';
import '../l10n/telegram_language_controller.dart';
import '../settings/keyword_blocker.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';

class NotificationController with WidgetsBindingObserver {
  NotificationController._();
  static final NotificationController shared = NotificationController._();

  static const _androidChannel = AndroidNotificationChannel(
    'messages',
    'Messages',
    description: 'Incoming Mithka messages',
    importance: Importance.high,
  );

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final TdClient _client = TdClient.shared;
  StreamSubscription? _sub;
  AppLifecycleState _state = AppLifecycleState.resumed;
  bool _ready = false;
  bool _notificationsAvailable = true;
  int _notificationSeed = 0;

  Future<void> start() async {
    if (_ready) return;
    WidgetsBinding.instance.addObserver(this);
    _state =
        WidgetsBinding.instance.lifecycleState ?? AppLifecycleState.resumed;

    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          defaultPresentBanner: false,
          defaultPresentList: false,
          defaultPresentSound: false,
          defaultPresentBadge: false,
        ),
      ),
      onDidReceiveNotificationResponse: _openNotification,
    );

    final launch = await _plugin.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp ?? false) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _openNotification(launch?.notificationResponse);
      });
    }

    await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(_androidChannel);
    await requestPermissions();

    _sub = _client.subscribe().listen(_handle);
    _ready = true;
  }

  Future<void> requestPermissions() async {
    try {
      final androidGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.requestNotificationsPermission();
      final iosGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (androidGranted == false || iosGranted == false) {
        _notificationsAvailable = false;
      }
    } on PlatformException catch (error) {
      _notificationsAvailable = false;
      debugPrint('Local notification permission request failed: $error');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _state = state;
  }

  Future<void> _handle(Map<String, dynamic> update) async {
    if (update.type != 'updateNewMessage') return;
    if (_state == AppLifecycleState.resumed) return;
    if (!_notificationsAvailable) return;

    final raw = update.obj('message');
    if (raw == null || (raw.boolean('is_outgoing') ?? false)) return;

    final chatId = raw.int64('chat_id');
    final messageId = raw.int64('id');
    final content = raw.obj('content');
    if (chatId == null || messageId == null || content == null) return;

    final chat = await _chat(chatId);
    if (chat == null || _isMuted(chat)) return;

    final title = chat.str('title') ?? 'Mithka';
    final body = _notificationText(content);
    if (KeywordBlocker.shared.matches(body)) return;
    final payload = jsonEncode({'chat_id': chatId, 'message_id': messageId});

    _notificationSeed = (_notificationSeed + 1) & 0x7fffffff;
    try {
      await _plugin.show(
        id: _notificationSeed,
        title: title,
        body: body,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'messages',
            'Messages',
            channelDescription: 'Incoming Mithka messages',
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.message,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: true,
            presentSound: true,
          ),
        ),
        payload: payload,
      );
    } on PlatformException catch (error) {
      if (_isNotificationAuthorizationError(error)) {
        _notificationsAvailable = false;
      }
      debugPrint('Local notification display failed: $error');
    }
  }

  bool _isNotificationAuthorizationError(PlatformException error) {
    final text = '${error.code} ${error.message} ${error.details}';
    return text.contains('not authorized') ||
        text.contains('UNErrorDomain') ||
        text.contains('Error 2003');
  }

  Future<Map<String, dynamic>?> _chat(int chatId) async {
    try {
      return await _client.query({'@type': 'getChat', 'chat_id': chatId});
    } catch (_) {
      return null;
    }
  }

  bool _isMuted(Map<String, dynamic> chat) {
    final settings = chat.obj('notification_settings');
    return (settings?.integer('mute_for') ?? 0) > 0;
  }

  String _notificationText(Map<String, dynamic> content) {
    final text = TDParse.messageText(content).replaceAll('\n', ' ').trim();
    return text.isEmpty
        ? telegramText(AppStringKeys.chatSearchMessageResultLabel)
        : text;
  }

  Future<void> _openNotification(NotificationResponse? response) async {
    final payload = response?.payload;
    if (payload == null || payload.isEmpty) return;

    final data = _decodePayload(payload);
    final chatId = data?.int64('chat_id');
    final messageId = data?.int64('message_id');
    if (chatId == null) return;

    final chat = await _chat(chatId);
    final title = chat?.str('title') ?? 'Mithka';

    ChatDeepLinkController.shared.openChat(
      chatId: chatId,
      title: title,
      messageId: messageId,
    );
  }

  Map<String, dynamic>? _decodePayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map<String, dynamic> ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    await _sub?.cancel();
    _sub = null;
    _ready = false;
  }
}
