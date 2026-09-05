//
//  notification_controller.dart
//
//  Local notifications driven by TDLib updates. This is not a push service:
//  it can notify while the Flutter/TDLib process is alive in the background,
//  but APNs/FCM would still be needed for killed-app delivery.
//

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app/chat_deep_link_controller.dart';
import '../settings/country_chat_blocker.dart';
import '../settings/keyword_blocker.dart';
import '../tdlib/chat_membership.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'ios_communication_notification.dart';
import 'notification_preferences.dart';
import 'notification_target.dart';
import 'scope_notification_settings.dart';
import 'system_notification_details.dart';

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

@visibleForTesting
String notificationTitleForAccount({
  required String title,
  required bool isActiveAccount,
  String? targetAccountName,
}) {
  final accountName = targetAccountName?.trim();
  if (isActiveAccount || accountName == null || accountName.isEmpty) {
    return title;
  }
  return '$title → $accountName';
}

@visibleForTesting
TdFileRef? notificationChatPhotoFromChat(Map<String, dynamic> chat) =>
    TDParse.smallPhoto(chat.obj('photo'));

/// Incoming messages up to `last_read_inbox_message_id` are read, no matter
/// which device read them. TDLib replays the whole offline backlog as
/// `updateNewMessage` once it reconnects, so this marker is what keeps a
/// launch from announcing conversations the user already cleared elsewhere.
@visibleForTesting
bool notificationMessageIsRead({
  required int messageId,
  required int lastReadInboxMessageId,
}) => messageId <= lastReadInboxMessageId;

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

  // Built per call rather than held as a const: the channel name and
  // description are shown in Android's own settings and follow the app locale.
  static AndroidNotificationChannel get _androidChannel =>
      AndroidNotificationChannel(
        'messages',
        AppStrings.t(AppStringKeys.notificationChannelMessagesName),
        description: AppStrings.t(
          AppStringKeys.notificationChannelMessagesDescription,
        ),
        importance: Importance.high,
      );
  static const _notificationTapChannel = MethodChannel(
    'mithka/notification_tap',
  );
  static const _inAppBannersKey = 'mithka.notifications.inAppBanners.v1';

  /// How long the offline backlog is held when an account never reports
  /// `connectionStateReady` — a stalled sync must not mute notifications.
  static const _backlogSettleTimeout = Duration(seconds: 8);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();
  final IOSCommunicationNotificationBridge _iosCommunicationNotifications =
      const IOSCommunicationNotificationBridge();
  final TdClient _client = TdClient.shared;
  final NotificationPreferences _notificationPreferences =
      NotificationPreferences.shared;
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
  final Map<(int, int), Map<String, dynamic>> _chatNotificationSettings = {};
  final Map<int, int> _accountUserIdsByClient = {};
  final Map<(int, int), int> _lastReadInboxMessageIds = {};
  final Map<(int, int), Map<String, dynamic>> _backlogMessages = {};
  final Map<int, Timer> _backlogTimers = {};
  final Set<int> _syncedClients = {};

  /// Join status per (clientId, is-supergroup, group id). Keyed by group rather
  /// than chat because the invalidating update carries only the group, and the
  /// kind is part of the key because basic-group and supergroup identifiers are
  /// separate TDLib id spaces whose values can collide.
  final Map<(int, bool, int), bool> _groupJoinCache = {};

  bool get inAppBannersEnabled => _inAppBannersEnabled;
  InAppNotificationBannerData? get inAppBanner => _inAppBanner;

  Future<void> start(SharedPreferences preferences) async {
    if (_ready) return;
    _preferences = preferences;
    _notificationPreferences.initialize(preferences);
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
        macOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
          defaultPresentBanner: false,
          defaultPresentList: false,
          defaultPresentSound: false,
          defaultPresentBadge: false,
        ),
        windows: WindowsInitializationSettings(
          appName: 'Mithka',
          appUserModelId: 'Iebb.Mithka.Desktop',
          guid: '19a46b98-1781-4d9e-92ed-bd0576e48e2d',
        ),
      ),
      onDidReceiveNotificationResponse: _openNotification,
    );

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _notificationTapChannel.setMethodCallHandler(_handleNativeTap);
      try {
        final initial = await _notificationTapChannel
            .invokeMapMethod<String, dynamic>('getInitialNotification');
        if (initial != null) await _openRemoteNotification(initial);
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
    _sub = _client.subscribeAll().listen(_handle);
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
      final macosGranted = await _plugin
          .resolvePlatformSpecificImplementation<
            MacOSFlutterLocalNotificationsPlugin
          >()
          ?.requestPermissions(alert: true, badge: true, sound: true);
      if (androidGranted == false ||
          iosGranted == false ||
          macosGranted == false) {
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
    final clientId = update.integer('@client_id') ?? _client.activeClientId;
    final isActiveAccount = clientId == _client.activeClientId;
    if (update.type == 'updateConnectionState') {
      _applyConnectionStateUpdate(update, clientId: clientId);
      return;
    }
    if (update.type == 'updateChatReadInbox') {
      _applyChatReadInboxUpdate(update, clientId: clientId);
      return;
    }
    if (update.type == 'updateChatNotificationSettings') {
      _applyChatNotificationSettingsUpdate(update, clientId: clientId);
      return;
    }
    if (update.type == 'updateScopeNotificationSettings') {
      final scope = update.obj('scope')?.type;
      final settings = update.obj('notification_settings');
      if (isActiveAccount && scope != null && settings != null) {
        ScopeNotificationSettings.shared.update(
          scope,
          settings.integer('mute_for') ?? 0,
        );
        ScopeNotificationSettings.shared.updateShowPreview(
          scope,
          settings.boolean('show_preview') ?? true,
        );
        ScopeNotificationSettings.shared.updateSoundId(
          scope,
          settings.int64('sound_id') ?? -1,
        );
        await _dismissBannerIfMuted(clientId: clientId);
      }
      return;
    }
    if (update.type == 'updateBasicGroup' ||
        update.type == 'updateSupergroup') {
      final isSupergroupUpdate = update.type == 'updateSupergroup';
      final group = update.obj(
        isSupergroupUpdate ? 'supergroup' : 'basic_group',
      );
      final joined = isJoinedMemberStatus(group?.obj('status'));
      // The update already carries the whole group, so membership never has to
      // be re-queried per incoming message once the group has been seen once.
      final groupId = group?.int64('id');
      if (groupId != null) {
        _groupJoinCache[(clientId, isSupergroupUpdate, groupId)] = joined;
      }
      if (isActiveAccount && !joined) {
        unawaited(_dismissBannerIfNoLongerJoined(clientId: clientId));
      }
      return;
    }
    if (update.type != 'updateNewMessage') return;

    final raw = update.obj('message');
    if (raw == null || (raw.boolean('is_outgoing') ?? false)) return;

    // TDLib replays everything that arrived while the app was offline as fresh
    // `updateNewMessage` events, before it has caught up on where the other
    // devices left off. Hold that backlog until the account finishes syncing
    // so read conversations stay silent instead of flooding the launch.
    if (!_syncedClients.contains(clientId)) {
      _holdBacklogMessage(raw, update, clientId: clientId);
      return;
    }

    await _announceNewMessage(update, clientId: clientId);
  }

  Future<void> _announceNewMessage(
    Map<String, dynamic> update, {
    required int clientId,
  }) async {
    final raw = update.obj('message');
    if (raw == null) return;
    final isActiveAccount = clientId == _client.activeClientId;

    if (!await _receivesNotificationsFrom(
      clientId,
      isActiveAccount: isActiveAccount,
    )) {
      return;
    }

    if (await CountryChatBlocker.shared.handleIncomingMessage(
      raw,
      clientId: clientId,
    )) {
      return;
    }

    final chatId = raw.int64('chat_id');
    final messageId = raw.int64('id');
    final content = raw.obj('content');
    if (chatId == null || messageId == null || content == null) return;

    final chat = await _chat(chatId, clientId: clientId);
    if (_isReadMessage(
      clientId: clientId,
      chatId: chatId,
      messageId: messageId,
      chat: chat,
    )) {
      return;
    }
    final effective = chat == null
        ? null
        : await _effectiveSettings(chat, clientId);
    if (chat == null ||
        effective == null ||
        effective.muted ||
        !await _isJoinedChat(chatId, chat, clientId: clientId)) {
      return;
    }

    final messageText = _notificationText(content);
    if (KeywordBlocker.shared.matches(messageText)) return;
    final surface = notificationSurfaceFor(
      lifecycleState: _state,
      inAppBannersEnabled: _inAppBannersEnabled,
      systemNotificationsAvailable: _notificationsAvailable,
    );
    // Only the system notification needs the icon in hand. Every other surface
    // still warms the app-group store the service extension reads for remote
    // pushes — it just no longer holds the banner behind a file read and a
    // possible avatar download.
    String? preparedIOSChatIconPath;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final prepared = _prepareIOSChatIcon(chat, chatId, clientId);
      if (surface == NotificationSurface.system) {
        preparedIOSChatIconPath = await prepared;
      } else {
        unawaited(prepared);
      }
    }
    if (surface == NotificationSurface.inApp) {
      if (isActiveAccount && _isChatVisible(chatId)) return;
      final showPreview =
          effective.showPreview && _notificationPreferences.inAppPreview;
      final sender = showPreview
          ? await _senderLabel(raw, chat, clientId)
          : null;
      final chatTitle = chat.str('title') ?? 'Mithka';
      final isTargetAccountActive = clientId == _client.activeClientId;
      final accountName = isTargetAccountActive
          ? null
          : await _notificationAccountName(clientId);
      final title = notificationTitleForAccount(
        title: chatTitle,
        isActiveAccount: isTargetAccountActive,
        targetAccountName: accountName,
      );
      final photo = isTargetAccountActive
          ? notificationChatPhotoFromChat(chat)
          : await _notificationChatPhoto(chat, clientId);
      final body = showPreview
          ? messageText
          : AppStrings.t(AppStringKeys.notificationNewMessage);
      _presentInAppBanner(
        InAppNotificationBannerData(
          target: NotificationTarget(
            chatId: chatId,
            messageId: messageId,
            title: chatTitle,
            accountSlot: _client.slotForClient(clientId),
          ),
          title: title,
          body: !showPreview || sender == null || sender.isEmpty
              ? body
              : '$sender: $body',
          photo: photo,
          squarePhoto: switch (TDParse.chatKind(chat)) {
            ChatKind.group || ChatKind.channel => true,
            _ => false,
          },
        ),
      );
      if (_notificationPreferences.inAppSounds) {
        unawaited(SystemSound.play(SystemSoundType.alert));
      }
      if (_notificationPreferences.inAppVibrate) {
        unawaited(HapticFeedback.mediumImpact());
      }
      return;
    }
    if (surface != NotificationSurface.system) return;
    final chatTitle = chat.str('title') ?? 'Mithka';
    final isTargetAccountActive = clientId == _client.activeClientId;
    final accountName = isTargetAccountActive
        ? null
        : await _notificationAccountName(clientId);
    final visibleTitle = _notificationPreferences.namesOnLockScreen
        ? chatTitle
        : 'Mithka';
    final title = notificationTitleForAccount(
      title: visibleTitle,
      isActiveAccount: isTargetAccountActive,
      targetAccountName: accountName,
    );
    final showPreview = effective.showPreview;
    final body = showPreview
        ? messageText
        : AppStrings.t(AppStringKeys.notificationNewMessage);
    final payload = jsonEncode({
      'chat_id': chatId,
      'message_id': messageId,
      'title': chatTitle,
      'account_slot': _client.slotForClient(clientId),
    });
    final chatIconPath =
        preparedIOSChatIconPath ??
        await _notificationChatIconPath(chat, clientId);
    final groupConversation = switch (TDParse.chatKind(chat)) {
      ChatKind.group || ChatKind.channel => true,
      _ => false,
    };
    final senderName =
        groupConversation && _notificationPreferences.namesOnLockScreen
        ? await _senderLabel(raw, chat, clientId) ?? title
        : title;

    _notificationSeed = (_notificationSeed + 1) & 0x7fffffff;
    try {
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        await _iosCommunicationNotifications.show(
          id: _notificationSeed,
          title: title,
          body: body,
          conversationIdentifier: '${_client.slotForClient(clientId)}:$chatId',
          senderName: senderName,
          payload: payload,
          groupConversation: groupConversation,
          playSound: effective.soundEnabled,
          chatId: chatId,
          chatIconPath: chatIconPath,
        );
        return;
      }
      await _plugin.show(
        id: _notificationSeed,
        title: title,
        body: body,
        notificationDetails: systemNotificationDetailsForChatIcon(
          chatIconPath,
          conversationTitle: title,
          messageBody: body,
          groupConversation: groupConversation,
          playSound: effective.soundEnabled,
          showOnLockScreen: _notificationPreferences.namesOnLockScreen,
        ),
        payload: payload,
      );
    } on MissingPluginException catch (error) {
      debugPrint(
        'Native communication notification bridge unavailable: $error',
      );
      await _showFallbackSystemNotification(
        id: _notificationSeed,
        title: title,
        body: body,
        payload: payload,
        chatIconPath: chatIconPath,
        groupConversation: groupConversation,
        playSound: effective.soundEnabled,
      );
    } on PlatformException catch (error) {
      if (_isNotificationAuthorizationError(error)) {
        _notificationsAvailable = false;
      }
      debugPrint('Local notification display failed: $error');
      if (defaultTargetPlatform == TargetPlatform.iOS &&
          !_isNotificationAuthorizationError(error)) {
        await _showFallbackSystemNotification(
          id: _notificationSeed,
          title: title,
          body: body,
          payload: payload,
          chatIconPath: chatIconPath,
          groupConversation: groupConversation,
          playSound: effective.soundEnabled,
        );
      }
    }
  }

  Future<void> _showFallbackSystemNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
    required bool groupConversation,
    required bool playSound,
    String? chatIconPath,
  }) async {
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        notificationDetails: systemNotificationDetailsForChatIcon(
          chatIconPath,
          conversationTitle: title,
          messageBody: body,
          groupConversation: groupConversation,
          playSound: playSound,
          showOnLockScreen: _notificationPreferences.namesOnLockScreen,
        ),
        payload: payload,
      );
    } on PlatformException catch (error) {
      if (_isNotificationAuthorizationError(error)) {
        _notificationsAvailable = false;
      }
      debugPrint('Fallback local notification display failed: $error');
    }
  }

  Future<String?> _prepareIOSChatIcon(
    Map<String, dynamic> chat,
    int chatId,
    int clientId,
  ) async {
    final path = await _notificationChatIconPath(chat, clientId);
    if (path == null) return null;
    unawaited(
      _iosCommunicationNotifications.cacheChatIcon(chatId: chatId, path: path),
    );
    return path;
  }

  Future<String?> _notificationChatIconPath(
    Map<String, dynamic> chat,
    int clientId,
  ) async {
    final photo = await _notificationChatPhoto(chat, clientId);
    if (photo == null) return null;
    return _readableNotificationIconPath(photo.localPath);
  }

  Future<TdFileRef?> _notificationChatPhoto(
    Map<String, dynamic> chat,
    int clientId,
  ) async {
    final photo = notificationChatPhotoFromChat(chat);
    if (photo == null) return null;
    final existing = await _readableNotificationIconPath(photo.localPath);
    if (existing != null) return photo;
    try {
      final downloaded = await _query({
        '@type': 'downloadFile',
        'file_id': photo.id,
        'priority': 16,
        'offset': 0,
        'limit': 0,
        'synchronous': true,
      }, clientId).timeout(const Duration(seconds: 2));
      final path = await _readableNotificationIconPath(
        downloaded.obj('local')?.str('path'),
      );
      if (path == null) return _notificationPhotoPlaceholder(photo);
      return TdFileRef(
        id: photo.id,
        localPath: path,
        miniThumb: photo.miniThumb,
        thumbnail: photo.thumbnail,
        hasAnimation: photo.hasAnimation,
        photoId: photo.photoId,
      );
    } catch (_) {
      return _notificationPhotoPlaceholder(photo);
    }
  }

  TdFileRef _notificationPhotoPlaceholder(TdFileRef photo) => TdFileRef(
    // TDLib file ids are account-local. Avoid resolving this id through a
    // newly active account if the originating account download failed.
    id: 0,
    miniThumb: photo.miniThumb,
    photoId: photo.photoId,
  );

  Future<String?> _notificationAccountName(int clientId) async {
    try {
      final user = await _query({'@type': 'getMe'}, clientId);
      final name = TDParse.userName(user).trim();
      return name.isEmpty ? null : name;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _receivesNotificationsFrom(
    int clientId, {
    required bool isActiveAccount,
  }) async {
    final mode = _notificationPreferences.accountMode;
    if (mode == NotificationAccountMode.all) return true;
    if (mode == NotificationAccountMode.current) return isActiveAccount;
    final cachedUserId = _accountUserIdsByClient[clientId];
    if (cachedUserId != null) {
      return _notificationPreferences.receivesNotificationsFrom(
        userId: cachedUserId,
        isActiveAccount: isActiveAccount,
      );
    }
    try {
      final user = await _query({'@type': 'getMe'}, clientId);
      final userId = user.int64('id');
      if (userId == null) return false;
      _accountUserIdsByClient[clientId] = userId;
      return _notificationPreferences.receivesNotificationsFrom(
        userId: userId,
        isActiveAccount: isActiveAccount,
      );
    } catch (_) {
      return false;
    }
  }

  Future<String?> _readableNotificationIconPath(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      final file = File(path);
      if (!await file.exists() || await file.length() <= 0) return null;
      return path;
    } catch (_) {
      return null;
    }
  }

  bool _isNotificationAuthorizationError(PlatformException error) {
    final text = '${error.code} ${error.message} ${error.details}';
    return text.contains('not authorized') ||
        text.contains('UNErrorDomain') ||
        text.contains('Error 2003');
  }

  void _applyConnectionStateUpdate(
    Map<String, dynamic> update, {
    required int clientId,
  }) {
    final state = update.obj('state')?.type;
    if (state == null) return;
    if (state == 'connectionStateReady') {
      unawaited(_finishSync(clientId));
      return;
    }
    // `connectionStateUpdating` is TDLib downloading what arrived while the
    // app was offline. Every state short of ready can still deliver a backlog,
    // so a dropped connection re-arms the hold for the next reconnect.
    _syncedClients.remove(clientId);
  }

  /// Keeps only the newest held message per chat: a backlog is a summary of
  /// what was missed, not a replay of every message one notification at a time.
  void _holdBacklogMessage(
    Map<String, dynamic> message,
    Map<String, dynamic> update, {
    required int clientId,
  }) {
    final chatId = message.int64('chat_id');
    final messageId = message.int64('id');
    if (chatId == null || messageId == null) return;
    final key = (clientId, chatId);
    if (notificationMessageIsRead(
      messageId: messageId,
      lastReadInboxMessageId: _lastReadInboxMessageIds[key] ?? 0,
    )) {
      return;
    }
    final held = _backlogMessages[key]?.obj('message')?.int64('id') ?? 0;
    if (messageId >= held) _backlogMessages[key] = update;
    _backlogTimers[clientId] ??= Timer(
      _backlogSettleTimeout,
      () => unawaited(_finishSync(clientId)),
    );
  }

  Future<void> _finishSync(int clientId) async {
    _backlogTimers.remove(clientId)?.cancel();
    _syncedClients.add(clientId);
    final backlog = <Map<String, dynamic>>[];
    _backlogMessages.removeWhere((key, update) {
      if (key.$1 != clientId) return false;
      backlog.add(update);
      return true;
    });
    for (final update in backlog) {
      await _announceNewMessage(update, clientId: clientId);
    }
  }

  void _applyChatReadInboxUpdate(
    Map<String, dynamic> update, {
    required int clientId,
  }) {
    final chatId = update.int64('chat_id');
    final lastReadMessageId = update.int64('last_read_inbox_message_id');
    if (chatId == null || lastReadMessageId == null) return;
    final key = (clientId, chatId);
    if (lastReadMessageId > (_lastReadInboxMessageIds[key] ?? 0)) {
      _lastReadInboxMessageIds[key] = lastReadMessageId;
    }

    final held = _backlogMessages[key]?.obj('message')?.int64('id');
    if (held != null &&
        notificationMessageIsRead(
          messageId: held,
          lastReadInboxMessageId: lastReadMessageId,
        )) {
      _backlogMessages.remove(key);
    }

    // Reading on another device should also retire what is already on screen.
    final banner = _inAppBanner;
    final bannerMessageId = banner?.target.messageId;
    if (banner != null &&
        bannerMessageId != null &&
        banner.target.chatId == chatId &&
        _targetClientId(banner.target) == clientId &&
        notificationMessageIsRead(
          messageId: bannerMessageId,
          lastReadInboxMessageId: lastReadMessageId,
        )) {
      dismissInAppBanner();
    }
  }

  bool _isReadMessage({
    required int clientId,
    required int chatId,
    required int messageId,
    Map<String, dynamic>? chat,
  }) {
    final tracked = _lastReadInboxMessageIds[(clientId, chatId)] ?? 0;
    final reported = chat?.int64('last_read_inbox_message_id') ?? 0;
    return notificationMessageIsRead(
      messageId: messageId,
      lastReadInboxMessageId: tracked > reported ? tracked : reported,
    );
  }

  void _applyChatNotificationSettingsUpdate(
    Map<String, dynamic> update, {
    required int clientId,
  }) {
    final chatId = update.int64('chat_id');
    final settings = update.obj('notification_settings');
    if (chatId == null || settings == null) return;
    _chatNotificationSettings[(clientId, chatId)] = Map<String, dynamic>.from(
      settings,
    );
    final useDefault = settings.boolean('use_default_mute_for') ?? false;
    if (!useDefault) {
      if ((settings.integer('mute_for') ?? 0) > 0 &&
          _inAppBanner?.target.chatId == chatId &&
          _targetClientId(_inAppBanner!.target) == clientId) {
        dismissInAppBanner();
      }
      return;
    }
    unawaited(_dismissBannerIfMuted(chatId: chatId, clientId: clientId));
  }

  Future<void> _dismissBannerIfMuted({int? chatId, int? clientId}) async {
    final target = _inAppBanner?.target;
    final targetChatId = target?.chatId;
    if (targetChatId == null || chatId != null && targetChatId != chatId) {
      return;
    }
    final targetClientId = target == null
        ? _client.activeClientId
        : _targetClientId(target);
    if (clientId != null && clientId != targetClientId) return;
    final chat = await _chat(targetChatId, clientId: targetClientId);
    if (chat != null &&
        (await _effectiveSettings(chat, targetClientId)).muted) {
      dismissInAppBanner();
    }
  }

  Future<void> _dismissBannerIfNoLongerJoined({required int clientId}) async {
    final target = _inAppBanner?.target;
    final chatId = target?.chatId;
    if (chatId == null) return;
    final targetClientId = target == null
        ? _client.activeClientId
        : _targetClientId(target);
    if (targetClientId != clientId) return;
    final chat = await _chat(chatId, clientId: clientId);
    if (chat != null &&
        !await isJoinedGroupOrChannelChat(
          chatId,
          chat: chat,
          clientId: clientId,
        )) {
      dismissInAppBanner();
    }
  }

  @visibleForTesting
  void applyChatNotificationSettingsUpdateForTesting(
    Map<String, dynamic> update,
  ) {
    _applyChatNotificationSettingsUpdate(
      update,
      clientId: update.integer('@client_id') ?? _client.activeClientId,
    );
  }

  @visibleForTesting
  void applyChatReadInboxUpdateForTesting(Map<String, dynamic> update) {
    _applyChatReadInboxUpdate(
      update,
      clientId: update.integer('@client_id') ?? _client.activeClientId,
    );
  }

  @visibleForTesting
  void applyConnectionStateUpdateForTesting(Map<String, dynamic> update) {
    _applyConnectionStateUpdate(
      update,
      clientId: update.integer('@client_id') ?? _client.activeClientId,
    );
  }

  /// Holds a `updateNewMessage` the way [_handle] would while an account is
  /// still syncing, and reports the chats still queued for announcement.
  @visibleForTesting
  List<int> holdBacklogMessageForTesting(Map<String, dynamic> update) {
    final clientId = update.integer('@client_id') ?? _client.activeClientId;
    final message = update.obj('message');
    if (message != null) {
      _holdBacklogMessage(message, update, clientId: clientId);
    }
    return heldBacklogChatIdsForTesting(clientId);
  }

  @visibleForTesting
  List<int> heldBacklogChatIdsForTesting(int clientId) => [
    for (final key in _backlogMessages.keys)
      if (key.$1 == clientId) key.$2,
  ];

  @visibleForTesting
  bool isSyncedForTesting(int clientId) => _syncedClients.contains(clientId);

  @visibleForTesting
  bool isMessageReadForTesting({
    required int chatId,
    required int messageId,
    Map<String, dynamic>? chat,
    int? clientId,
  }) => _isReadMessage(
    clientId: clientId ?? _client.activeClientId,
    chatId: chatId,
    messageId: messageId,
    chat: chat,
  );

  @visibleForTesting
  void resetSyncStateForTesting() => _resetSyncState();

  void _resetSyncState() {
    for (final timer in _backlogTimers.values) {
      timer.cancel();
    }
    _backlogTimers.clear();
    _backlogMessages.clear();
    _lastReadInboxMessageIds.clear();
    _syncedClients.clear();
  }

  Future<Map<String, dynamic>?> _chat(
    int chatId, {
    required int clientId,
  }) async {
    try {
      return await _query({'@type': 'getChat', 'chat_id': chatId}, clientId);
    } catch (_) {
      return null;
    }
  }

  /// Membership, answered from [_groupJoinCache] when the group's status has
  /// already been delivered — otherwise every incoming group message pays a
  /// getSupergroup/getBasicGroup round trip that the update stream repeats.
  Future<bool> _isJoinedChat(
    int chatId,
    Map<String, dynamic> chat, {
    required int clientId,
  }) async {
    final type = chat.obj('type');
    final isSupergroup = type?.type == 'chatTypeSupergroup';
    final groupId = switch (type?.type) {
      'chatTypeBasicGroup' => type?.int64('basic_group_id'),
      'chatTypeSupergroup' => type?.int64('supergroup_id'),
      _ => null,
    };
    if (groupId == null) {
      return isJoinedGroupOrChannelChat(chatId, chat: chat, clientId: clientId);
    }
    final key = (clientId, isSupergroup, groupId);
    final cached = _groupJoinCache[key];
    if (cached != null) return cached;
    final joined = await isJoinedGroupOrChannelChat(
      chatId,
      chat: chat,
      clientId: clientId,
    );
    _groupJoinCache[key] = joined;
    return joined;
  }

  Future<Map<String, dynamic>> _query(
    Map<String, dynamic> request,
    int clientId,
  ) {
    return clientId == _client.activeClientId
        ? _client.query(request)
        : _client.queryTo(request, clientId);
  }

  int _targetClientId(NotificationTarget target) {
    final slot = target.accountSlot;
    return slot == null
        ? _client.activeClientId
        : (_client.clientId(slot) ?? _client.activeClientId);
  }

  bool _isMuted(Map<String, dynamic> chat) {
    final chatId = chat.int64('id');
    final latestSettings = chatId == null
        ? null
        : _chatNotificationSettings[(_client.activeClientId, chatId)];
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

  Future<_EffectiveNotificationSettings> _effectiveSettings(
    Map<String, dynamic> chat,
    int clientId,
  ) async {
    final chatId = chat.int64('id');
    final latest = chatId == null
        ? null
        : _chatNotificationSettings[(clientId, chatId)];
    final settings = latest ?? chat.obj('notification_settings');
    final useDefaultMute = settings?.boolean('use_default_mute_for') ?? false;
    final useDefaultPreview =
        settings?.boolean('use_default_show_preview') ?? true;
    final useDefaultSound = settings?.boolean('use_default_sound') ?? true;

    if (clientId == _client.activeClientId) {
      final effectiveChat = latest == null
          ? chat
          : {...chat, 'notification_settings': latest};
      return _EffectiveNotificationSettings(
        muted: ScopeNotificationSettings.shared.isMuted(effectiveChat),
        showPreview: ScopeNotificationSettings.shared.showPreview(
          effectiveChat,
        ),
        soundEnabled: ScopeNotificationSettings.shared.soundEnabled(
          effectiveChat,
        ),
      );
    }

    Map<String, dynamic>? scopeSettings;
    if (useDefaultMute || useDefaultPreview || useDefaultSound) {
      try {
        scopeSettings = await _query({
          '@type': 'getScopeNotificationSettings',
          'scope': {
            '@type': ScopeNotificationSettings.shared.scopeTagForChat(chat),
          },
        }, clientId);
      } catch (_) {}
    }
    final muteFor = useDefaultMute
        ? (scopeSettings?.integer('mute_for') ?? 0)
        : (settings?.integer('mute_for') ?? 0);
    final showPreview = useDefaultPreview
        ? (scopeSettings?.boolean('show_preview') ?? true)
        : (settings?.boolean('show_preview') ?? true);
    final soundId = useDefaultSound
        ? (scopeSettings?.int64('sound_id') ?? -1)
        : (settings?.int64('sound_id') ?? -1);
    return _EffectiveNotificationSettings(
      muted: muteFor > 0,
      showPreview: showPreview,
      soundEnabled: soundId != 0,
    );
  }

  String _notificationText(Map<String, dynamic> content) {
    final text = TDParse.messageText(content).replaceAll('\n', ' ').trim();
    return text.isEmpty
        ? AppStrings.t(AppStringKeys.chatSearchMessageResultLabel)
        : text;
  }

  Future<String?> _senderLabel(
    Map<String, dynamic> message,
    Map<String, dynamic> chat,
    int clientId,
  ) async {
    final kind = TDParse.chatKind(chat);
    if (kind != ChatKind.group && kind != ChatKind.channel) return null;
    final sender = message.obj('sender_id');
    try {
      switch (sender?.type) {
        case 'messageSenderUser':
          final userId = sender?.int64('user_id');
          if (userId == null) return null;
          final user = await _query({
            '@type': 'getUser',
            'user_id': userId,
          }, clientId);
          return TDParse.userName(user);
        case 'messageSenderChat':
          final senderChatId = sender?.int64('chat_id');
          if (senderChatId == null) return null;
          return (await _chat(senderChatId, clientId: clientId))?.str('title');
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
    await _openRemoteNotification(call.arguments);
  }

  Future<void> _openRemoteNotification(Object? userInfo) async {
    final target = NotificationTarget.fromRemoteUserInfo(userInfo);
    if (target == null) return;
    _openTarget(await _withAccountSlot(target));
  }

  /// Tags a remote target with the slot its account occupies.
  ///
  /// Telegram's push payload names the account by user id; the slot is
  /// Mithka's own numbering and only resolvable here, where the client
  /// registry lives. Without it the tap reaches navigation carrying a chat id
  /// and no way to say which account it belongs to.
  Future<NotificationTarget> _withAccountSlot(NotificationTarget target) async {
    final userId = target.accountUserId;
    if (target.accountSlot != null || userId == null) return target;
    final slot = await _slotForAccountUserId(userId);
    return slot == null ? target : target.withAccountSlot(slot);
  }

  Future<int?> _slotForAccountUserId(int userId) async {
    for (final entry in _accountUserIdsByClient.entries) {
      if (entry.value == userId) return _client.slotForClient(entry.key);
    }
    // The cache only fills as notifications are filtered, so a tap that wakes
    // the app finds it empty. Ask each signed-in client who it is.
    for (final clientId in _client.registeredClientIds.toList()) {
      if (_accountUserIdsByClient.containsKey(clientId)) continue;
      try {
        final me = await _query({'@type': 'getMe'}, clientId);
        final id = me.int64('id');
        if (id == null) continue;
        _accountUserIdsByClient[clientId] = id;
        if (id == userId) return _client.slotForClient(clientId);
      } catch (_) {
        // An account that cannot answer cannot be the destination either.
      }
    }
    return null;
  }

  void _openTarget(NotificationTarget target) {
    final now = DateTime.now();
    final previous = _lastOpenedTarget;
    if (previous?.chatId == target.chatId &&
        previous?.messageId == target.messageId &&
        previous?.accountUserId == target.accountUserId &&
        previous?.accountSlot == target.accountSlot &&
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
      accountUserId: target.accountUserId,
      accountSlot: target.accountSlot,
    );
  }

  Future<void> stop() async {
    WidgetsBinding.instance.removeObserver(this);
    dismissInAppBanner();
    _visibleChats.clear();
    _resetSyncState();
    await _sub?.cancel();
    _sub = null;
    _ready = false;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      _notificationTapChannel.setMethodCallHandler(null);
    }
  }

  @override
  void dispose() {
    unawaited(stop());
    super.dispose();
  }
}

class _EffectiveNotificationSettings {
  const _EffectiveNotificationSettings({
    required this.muted,
    required this.showPreview,
    required this.soundEnabled,
  });

  final bool muted;
  final bool showPreview;
  final bool soundEnabled;
}

class _VisibleChatRegistration {
  const _VisibleChatRegistration(this.chatId, this.isVisible);

  final int chatId;
  final bool Function() isVisible;
}
