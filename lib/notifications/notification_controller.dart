//
//  notification_controller.dart
//
//  Local notifications driven by TDLib updates. This is not a push service:
//  it can notify while the Flutter/TDLib process is alive in the background,
//  but APNs/FCM would still be needed for killed-app delivery.
//

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/chat_deep_link_controller.dart';
import '../l10n/telegram_language_controller.dart';
import '../settings/country_message_filter.dart';
import '../settings/keyword_blocker.dart';
import '../tdlib/chat_membership.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'notification_target.dart';
import 'scope_notification_settings.dart';

enum NotificationSurface { none, inApp, system }

@visibleForTesting
NotificationSurface notificationSurfaceFor({
  required AppLifecycleState lifecycleState,
  required bool inAppBannersEnabled,
  required bool systemNotificationsAvailable,
}) {
  if (lifecycleState == AppLifecycleState.resumed) {
    return inAppBannersEnabled
        ? NotificationSurface.inApp
        : NotificationSurface.none;
  }
  return systemNotificationsAvailable
      ? NotificationSurface.system
      : NotificationSurface.none;
}

class InAppNotificationBannerData {
  const InAppNotificationBannerData({
    required this.target,
    required this.title,
    required this.body,
    required this.photo,
    required this.squarePhoto,
  });

  final NotificationTarget target;
  final String title;
  final String body;
  final TdFileRef? photo;
  final bool squarePhoto;

  String get key => '${target.chatId}:${target.messageId ?? 0}';
}

class NotificationController with WidgetsBindingObserver, ChangeNotifier {
  NotificationController._();
  static final NotificationController shared = NotificationController._();

  static const _androidChannel = AndroidNotificationChannel(
    'messages',
    'Messages',
    description: 'Incoming Mithka messages',
    importance: Importance.high,
  );
  static const _notificationTapChannel = MethodChannel(
    'mithka/notification_tap',
  );
  static const _inAppBannersKey = 'mithka.notifications.inAppBanners.v1';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final TdClient _client = TdClient.shared;
  StreamSubscription? _sub;
  AppLifecycleState _state = AppLifecycleState.resumed;
  bool _ready = false;
  bool _notificationsAvailable = true;
  int _notificationSeed = 0;
  NotificationTarget? _lastOpenedTarget;
  DateTime? _lastOpenedAt;
  SharedPreferences? _preferences;
  bool _inAppBannersEnabled = true;
  InAppNotificationBannerData? _inAppBanner;
  Timer? _inAppBannerTimer;
  final Map<Object, _VisibleChatRegistration> _visibleChats = {};
  final Map<int, Map<String, dynamic>> _chatNotificationSettings = {};

  bool get inAppBannersEnabled => _inAppBannersEnabled;
  InAppNotificationBannerData? get inAppBanner => _inAppBanner;

  Future<void> start(SharedPreferences preferences) async {
    if (_ready) return;
    _preferences = preferences;
    _inAppBannersEnabled = preferences.getBool(_inAppBannersKey) ?? true;
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

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _notificationTapChannel.setMethodCallHandler(_handleNativeTap);
      try {
        final initial = await _notificationTapChannel
            .invokeMapMethod<String, dynamic>('getInitialNotification');
        if (initial != null) _openRemoteNotification(initial);
      } on PlatformException catch (error) {
        debugPrint('Initial notification tap lookup failed: $error');
      }
    }

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
    _sub = _client.subscribe().listen(_handle);
    _ready = true;
    // Foreground banners don't require notification permission. Subscribe
    // before asking so an OS permission sheet can't create a blind spot.
    unawaited(requestPermissions());
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
    if (state != AppLifecycleState.resumed) dismissInAppBanner();
  }

  Future<void> _handle(Map<String, dynamic> update) async {
    if (update.type == 'updateChatNotificationSettings') {
      _applyChatNotificationSettingsUpdate(update);
      return;
    }
    if (update.type == 'updateScopeNotificationSettings') {
      final scope = update.obj('scope')?.type;
      final settings = update.obj('notification_settings');
      if (scope != null && settings != null) {
        ScopeNotificationSettings.shared.update(
          scope,
          settings.integer('mute_for') ?? 0,
        );
        ScopeNotificationSettings.shared.updateShowPreview(
          scope,
          settings.boolean('show_preview') ?? true,
        );
        await _dismissBannerIfMuted();
      }
      return;
    }
    if (update.type == 'updateBasicGroup' ||
        update.type == 'updateSupergroup') {
      final group = update.obj(
        update.type == 'updateBasicGroup' ? 'basic_group' : 'supergroup',
      );
      if (!isJoinedMemberStatus(group?.obj('status'))) {
        unawaited(_dismissBannerIfNoLongerJoined());
      }
      return;
    }
    if (update.type != 'updateNewMessage') return;

    final raw = update.obj('message');
    if (raw == null || (raw.boolean('is_outgoing') ?? false)) return;

    final chatId = raw.int64('chat_id');
    final messageId = raw.int64('id');
    final content = raw.obj('content');
    if (chatId == null || messageId == null || content == null) return;

    final chat = await _chat(chatId);
    if (chat == null ||
        _isMuted(chat) ||
        !await isJoinedGroupOrChannelChat(chatId, chat: chat) ||
        await _isCountryFiltered(chat)) {
      return;
    }

    final messageText = _notificationText(content);
    if (KeywordBlocker.shared.matches(messageText)) return;
    final surface = notificationSurfaceFor(
      lifecycleState: _state,
      inAppBannersEnabled: _inAppBannersEnabled,
      systemNotificationsAvailable: _notificationsAvailable,
    );
    if (surface == NotificationSurface.inApp) {
      if (_isChatVisible(chatId)) return;
      final sender = ScopeNotificationSettings.shared.showPreview(chat)
          ? await _senderLabel(raw, chat)
          : null;
      final latestChat = await _chat(chatId);
      if (latestChat == null || _isMuted(latestChat)) return;
      final showPreview = ScopeNotificationSettings.shared.showPreview(
        latestChat,
      );
      final title = latestChat.str('title') ?? 'Mithka';
      final body = showPreview
          ? messageText
          : AppStrings.t(AppStringKeys.notificationNewMessage);
      _presentInAppBanner(
        InAppNotificationBannerData(
          target: NotificationTarget(
            chatId: chatId,
            messageId: messageId,
            title: title,
          ),
          title: title,
          body: !showPreview || sender == null || sender.isEmpty
              ? body
              : '$sender: $body',
          photo: TDParse.smallPhoto(latestChat.obj('photo')),
          squarePhoto: switch (TDParse.chatKind(latestChat)) {
            ChatKind.group || ChatKind.channel => true,
            _ => false,
          },
        ),
      );
      return;
    }
    if (surface != NotificationSurface.system) return;
    final latestChat = await _chat(chatId);
    if (latestChat == null || _isMuted(latestChat)) return;
    final title = latestChat.str('title') ?? 'Mithka';
    final showPreview = ScopeNotificationSettings.shared.showPreview(
      latestChat,
    );
    final body = showPreview
        ? messageText
        : AppStrings.t(AppStringKeys.notificationNewMessage);
    final payload = jsonEncode({
      'chat_id': chatId,
      'message_id': messageId,
      'title': title,
    });

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

  void _applyChatNotificationSettingsUpdate(Map<String, dynamic> update) {
    final chatId = update.int64('chat_id');
    final settings = update.obj('notification_settings');
    if (chatId == null || settings == null) return;
    _chatNotificationSettings[chatId] = Map<String, dynamic>.from(settings);
    final useDefault = settings.boolean('use_default_mute_for') ?? false;
    if (!useDefault) {
      if ((settings.integer('mute_for') ?? 0) > 0 &&
          _inAppBanner?.target.chatId == chatId) {
        dismissInAppBanner();
      }
      return;
    }
    unawaited(_dismissBannerIfMuted(chatId: chatId));
  }

  Future<void> _dismissBannerIfMuted({int? chatId}) async {
    final targetChatId = _inAppBanner?.target.chatId;
    if (targetChatId == null || chatId != null && targetChatId != chatId) {
      return;
    }
    final chat = await _chat(targetChatId);
    if (chat != null && _isMuted(chat)) dismissInAppBanner();
  }

  Future<void> _dismissBannerIfNoLongerJoined() async {
    final chatId = _inAppBanner?.target.chatId;
    if (chatId == null) return;
    final chat = await _chat(chatId);
    if (chat != null && !await isJoinedGroupOrChannelChat(chatId, chat: chat)) {
      dismissInAppBanner();
    }
  }

  @visibleForTesting
  void applyChatNotificationSettingsUpdateForTesting(
    Map<String, dynamic> update,
  ) {
    _applyChatNotificationSettingsUpdate(update);
  }

  Future<Map<String, dynamic>?> _chat(int chatId) async {
    try {
      return await _client.query({'@type': 'getChat', 'chat_id': chatId});
    } catch (_) {
      return null;
    }
  }

  bool _isMuted(Map<String, dynamic> chat) {
    final chatId = chat.int64('id');
    final latestSettings = chatId == null
        ? null
        : _chatNotificationSettings[chatId];
    if (latestSettings == null) {
      return ScopeNotificationSettings.shared.isMuted(chat);
    }
    return ScopeNotificationSettings.shared.isMuted({
      ...chat,
      'notification_settings': latestSettings,
    });
  }

  @visibleForTesting
  bool isChatMutedForTesting(Map<String, dynamic> chat) => _isMuted(chat);

  Future<bool> _isCountryFiltered(Map<String, dynamic> chat) async {
    final type = chat.obj('type');
    if (type?.type != 'chatTypePrivate' && type?.type != 'chatTypeSecret') {
      return false;
    }
    final userId = type?.int64('user_id');
    if (userId == null) return false;
    try {
      final user = await _client.query({'@type': 'getUser', 'user_id': userId});
      return CountryMessageFilter.shared.matchesUser(
        isContact: user.boolean('is_contact') ?? false,
        phoneNumber: user.str('phone_number'),
      );
    } catch (_) {
      return false;
    }
  }

  String _notificationText(Map<String, dynamic> content) {
    final text = TDParse.messageText(content).replaceAll('\n', ' ').trim();
    return text.isEmpty
        ? telegramText(AppStringKeys.chatSearchMessageResultLabel)
        : text;
  }

  Future<String?> _senderLabel(
    Map<String, dynamic> message,
    Map<String, dynamic> chat,
  ) async {
    final kind = TDParse.chatKind(chat);
    if (kind != ChatKind.group && kind != ChatKind.channel) return null;
    final sender = message.obj('sender_id');
    try {
      switch (sender?.type) {
        case 'messageSenderUser':
          final userId = sender?.int64('user_id');
          if (userId == null) return null;
          final user = await _client.query({
            '@type': 'getUser',
            'user_id': userId,
          });
          return TDParse.userName(user);
        case 'messageSenderChat':
          final senderChatId = sender?.int64('chat_id');
          if (senderChatId == null) return null;
          return (await _chat(senderChatId))?.str('title');
      }
    } catch (_) {}
    return null;
  }

  Future<void> setInAppBannersEnabled(bool enabled) async {
    if (_inAppBannersEnabled == enabled) return;
    _inAppBannersEnabled = enabled;
    if (!enabled) dismissInAppBanner();
    notifyListeners();
    await _preferences?.setBool(_inAppBannersKey, enabled);
  }

  void _presentInAppBanner(InAppNotificationBannerData banner) {
    _inAppBannerTimer?.cancel();
    _inAppBanner = banner;
    notifyListeners();
    _inAppBannerTimer = Timer(const Duration(seconds: 4), dismissInAppBanner);
  }

  @visibleForTesting
  void presentInAppBannerForTesting(InAppNotificationBannerData banner) {
    _presentInAppBanner(banner);
  }

  void dismissInAppBanner() {
    _inAppBannerTimer?.cancel();
    _inAppBannerTimer = null;
    if (_inAppBanner == null) return;
    _inAppBanner = null;
    notifyListeners();
  }

  void openInAppBanner() {
    final target = _inAppBanner?.target;
    dismissInAppBanner();
    if (target != null) _openTarget(target);
  }

  void registerVisibleChat(
    Object owner,
    int chatId,
    bool Function() isVisible,
  ) {
    _visibleChats[owner] = _VisibleChatRegistration(chatId, isVisible);
  }

  void unregisterVisibleChat(Object owner) {
    _visibleChats.remove(owner);
  }

  bool _isChatVisible(int chatId) {
    for (final registration in _visibleChats.values) {
      if (registration.chatId != chatId) continue;
      try {
        if (registration.isVisible()) return true;
      } catch (_) {}
    }
    return false;
  }

  void _openNotification(NotificationResponse? response) {
    final target = NotificationTarget.fromLocalPayload(response?.payload);
    if (target != null) _openTarget(target);
  }

  Future<dynamic> _handleNativeTap(MethodCall call) async {
    if (call.method != 'notificationTap') return;
    _openRemoteNotification(call.arguments);
  }

  void _openRemoteNotification(Object? userInfo) {
    final target = NotificationTarget.fromRemoteUserInfo(userInfo);
    if (target != null) _openTarget(target);
  }

  void _openTarget(NotificationTarget target) {
    final now = DateTime.now();
    final previous = _lastOpenedTarget;
    if (previous?.chatId == target.chatId &&
        previous?.messageId == target.messageId &&
        now.difference(
              _lastOpenedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
            ) <
            const Duration(seconds: 2)) {
      return;
    }
    _lastOpenedTarget = target;
    _lastOpenedAt = now;
    ChatDeepLinkController.shared.openChat(
      chatId: target.chatId,
      title: target.title ?? 'Mithka',
      messageId: target.messageId,
    );
  }

  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    dismissInAppBanner();
    _visibleChats.clear();
    await _sub?.cancel();
    _sub = null;
    _ready = false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _notificationTapChannel.setMethodCallHandler(null);
    }
  }
}

class _VisibleChatRegistration {
  const _VisibleChatRegistration(this.chatId, this.isVisible);

  final int chatId;
  final bool Function() isVisible;
}
