import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../auth/account_store.dart';
import '../auth/auth_manager.dart';
import '../security/local_app_lock_controller.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'active_conversation.dart';
import 'chat_deep_link_controller.dart';

/// The non-secret state carried in Mithka's NSUserActivity payload.
///
/// Telegram authorization material is deliberately excluded. When the target
/// device does not already have [accountUserId], the native bridge requests it
/// through an ephemeral Handoff continuation stream instead.
@immutable
class HandoffChatActivity {
  const HandoffChatActivity({
    required this.activityId,
    required this.accountUserId,
    required this.chatId,
    this.messageId,
  });

  static const version = 1;

  final String activityId;
  final int accountUserId;
  final int chatId;
  final int? messageId;

  Map<String, Object> toJson() => <String, Object>{
    'version': version,
    'activityId': activityId,
    'accountUserId': accountUserId,
    'chatId': chatId,
    'messageId': ?messageId,
  };

  static HandoffChatActivity? tryParse(Object? source) {
    if (source is! Map) return null;
    final payloadVersion = _strictInt(source['version']);
    final activityId = source['activityId'];
    final accountUserId = _strictInt(source['accountUserId']);
    final chatId = _strictInt(source['chatId']);
    final rawMessageId = source['messageId'];
    final messageId = rawMessageId == null ? null : _strictInt(rawMessageId);
    if (payloadVersion != version ||
        activityId is! String ||
        activityId.isEmpty ||
        activityId.length > 128 ||
        accountUserId == null ||
        accountUserId <= 0 ||
        chatId == null ||
        chatId == 0 ||
        (rawMessageId != null && (messageId == null || messageId <= 0))) {
      return null;
    }
    return HandoffChatActivity(
      activityId: activityId,
      accountUserId: accountUserId,
      chatId: chatId,
      messageId: messageId,
    );
  }
}

int? _strictInt(Object? value) => value is int ? value : null;

/// Publishes the visible chat to Apple's Handoff service and resumes incoming
/// chat activities on iOS and macOS.
///
/// If the receiving device lacks the source Telegram account, the two Mithka
/// apps establish a continuation stream. The source exports its small TDLib
/// session string only into that point-to-point stream; the target immediately
/// uses it to create a fresh Telegram authorization and removes the temporary
/// imported session when the fresh authorization is ready.
class HandoffService {
  HandoffService._();

  static final HandoffService shared = HandoffService._();

  static const _channel = MethodChannel('mithka/handoff');

  AccountStore? _accounts;
  AuthManager? _auth;
  LocalAppLockController? _appLock;
  bool _started = false;
  int _advertisementGeneration = 0;
  Future<void> _incomingQueue = Future<void>.value();
  final Set<String> _queuedActivityIds = <String>{};
  final Set<String> _completedActivityIds = <String>{};

  bool get _isSupportedApplePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  void start({
    required AccountStore accounts,
    required AuthManager auth,
    required LocalAppLockController appLock,
  }) {
    if (_started || !_isSupportedApplePlatform) return;
    _started = true;
    _accounts = accounts;
    _auth = auth;
    _appLock = appLock;
    ActiveConversation.shared.addListener(_activityStateChanged);
    accounts.addListener(_activityStateChanged);
    appLock.addListener(_activityStateChanged);
    _channel.setMethodCallHandler(_handleNativeCall);
    _activityStateChanged();
    unawaited(_takePendingActivity());
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    ActiveConversation.shared.removeListener(_activityStateChanged);
    _accounts?.removeListener(_activityStateChanged);
    _appLock?.removeListener(_activityStateChanged);
    _accounts = null;
    _auth = null;
    _appLock = null;
    _advertisementGeneration += 1;
    _channel.setMethodCallHandler(null);
    try {
      await _channel.invokeMethod<void>('clearActivity');
    } on MissingPluginException {
      // The bridge is absent on non-Apple test hosts.
    }
  }

  void _activityStateChanged() {
    if (!_started) return;
    unawaited(_publishCurrentActivity());
  }

  Future<void> _publishCurrentActivity() async {
    final generation = ++_advertisementGeneration;
    final lock = _appLock;
    final scope = ActiveConversation.shared.current;
    if (lock == null || lock.locked || scope?.accountSlot == null) {
      await _clearAdvertisedActivity(generation);
      return;
    }

    final clientId = TdClient.shared.clientId(scope!.accountSlot!);
    if (clientId == null) {
      await _clearAdvertisedActivity(generation);
      return;
    }
    try {
      final state = await TdClient.shared
          .queryTo({'@type': 'getAuthorizationState'}, clientId)
          .timeout(const Duration(seconds: 3));
      if (state.type != 'authorizationStateReady') {
        await _clearAdvertisedActivity(generation);
        return;
      }
      final me = await TdClient.shared
          .queryTo({'@type': 'getMe'}, clientId)
          .timeout(const Duration(seconds: 3));
      final userId = me.int64('id');
      if (!_started ||
          generation != _advertisementGeneration ||
          _appLock?.locked == true ||
          userId == null ||
          userId <= 0) {
        return;
      }
      await _channel.invokeMethod<void>('updateActivity', <String, Object>{
        'version': HandoffChatActivity.version,
        'accountUserId': userId,
        'chatId': scope.chatId,
        if (scope.messageId != null && scope.messageId != 0)
          'messageId': scope.messageId!,
      });
    } on MissingPluginException {
      // A desktop child engine or unit-test host does not own Handoff.
    } catch (_) {
      await _clearAdvertisedActivity(generation);
    }
  }

  Future<void> _clearAdvertisedActivity(int generation) async {
    if (!_started || generation != _advertisementGeneration) return;
    try {
      await _channel.invokeMethod<void>('clearActivity');
    } on MissingPluginException {
      // A desktop child engine or unit-test host does not own Handoff.
    }
  }

  Future<Object?> _handleNativeCall(MethodCall call) async {
    switch (call.method) {
      case 'continueActivity':
        final activity = HandoffChatActivity.tryParse(call.arguments);
        if (activity == null) return false;
        _enqueueIncoming(activity);
        return true;
      case 'exportSession':
        final activity = HandoffChatActivity.tryParse(call.arguments);
        if (activity == null || _appLock?.locked == true) return null;
        return _exportSession(activity);
      default:
        throw MissingPluginException('Unknown Handoff method ${call.method}');
    }
  }

  Future<Map<String, Object>?> _exportSession(
    HandoffChatActivity activity,
  ) async {
    try {
      final slot = await TdClient.shared.readySlotForUserId(
        activity.accountUserId,
      );
      if (slot == null || _appLock?.locked == true) return null;
      final sessionString = await TdClient.shared.exportSessionStringForSlot(
        slot,
        userId: activity.accountUserId,
      );
      return <String, Object>{'sessionString': sessionString};
    } catch (_) {
      // Never include authorization material or native error details in logs.
      return null;
    }
  }

  Future<void> _takePendingActivity() async {
    try {
      final raw = await _channel.invokeMethod<Object?>('takePendingActivity');
      final activity = HandoffChatActivity.tryParse(raw);
      if (activity != null) _enqueueIncoming(activity);
    } on MissingPluginException {
      // The bridge is absent on non-Apple test hosts.
    }
  }

  void _enqueueIncoming(HandoffChatActivity activity) {
    if (_completedActivityIds.contains(activity.activityId) ||
        !_queuedActivityIds.add(activity.activityId)) {
      return;
    }
    _incomingQueue = _incomingQueue
        .then((_) => _continue(activity))
        .whenComplete(() => _queuedActivityIds.remove(activity.activityId));
  }

  Future<void> _continue(HandoffChatActivity activity) async {
    final accounts = _accounts;
    final auth = _auth;
    final lock = _appLock;
    if (!_started || accounts == null || auth == null || lock == null) return;

    await _waitUntilUnlocked(lock);
    if (!_started) return;

    try {
      var slot = await TdClient.shared.readySlotForUserId(
        activity.accountUserId,
      );
      if (slot == null) {
        final response = await _channel.invokeMethod<Object?>(
          'requestSession',
          activity.toJson(),
        );
        if (response is! Map || response['sessionString'] is! String) {
          throw StateError('Handoff session was unavailable');
        }
        final sessionString = response['sessionString'] as String;
        TdClient.shared.validateSessionString(
          sessionString,
          expectedUserId: activity.accountUserId,
        );
        final restoredSlot = await TdClient.shared.restoreSessionSlot(
          sessionString,
        );
        auth.reloadAuthState();
        await accounts.refresh();

        // The transferred authorization is a short-lived bootstrap. Prefer a
        // new Telegram session on this device so the two devices do not keep
        // sharing one auth key. If Telegram cannot mint it immediately, the
        // valid restored authorization still completes the user's Handoff.
        try {
          final fresh = await accounts.createFreshSessionFromRestoredSlot(
            restoredSlot,
            auth,
          );
          slot = fresh.slot;
        } catch (_) {
          slot = restoredSlot;
          if (accounts.activeSlot != restoredSlot) {
            accounts.switchTo(restoredSlot, auth);
          } else {
            auth.reloadAuthState();
          }
          await accounts.refresh();
        }
      } else if (slot != accounts.activeSlot) {
        accounts.switchTo(slot, auth);
      }

      final title = await _chatTitle(slot: slot, chatId: activity.chatId);
      ChatDeepLinkController.shared.openChat(
        chatId: activity.chatId,
        title: title,
        messageId: activity.messageId,
        accountUserId: activity.accountUserId,
        accountSlot: slot,
      );
      _completedActivityIds.add(activity.activityId);
      await _channel.invokeMethod<void>('completeActivity', <String, Object>{
        'activityId': activity.activityId,
      });
    } catch (error) {
      // The error type is useful in development; its message may contain
      // account/session details and must never be printed.
      debugPrint('Handoff continuation failed (${error.runtimeType})');
    }
  }

  Future<String> _chatTitle({required int slot, required int chatId}) async {
    final clientId = TdClient.shared.clientId(slot);
    if (clientId == null) return 'Mithka';
    try {
      final chat = await TdClient.shared
          .queryTo({'@type': 'getChat', 'chat_id': chatId}, clientId)
          .timeout(const Duration(seconds: 5));
      final title = chat
          .str('title')
          ?.replaceAll(RegExp(r'[\r\n]+'), ' ')
          .trim();
      if (title == null || title.isEmpty) return 'Mithka';
      return title.length <= 256 ? title : title.substring(0, 256);
    } catch (_) {
      return 'Mithka';
    }
  }

  Future<void> _waitUntilUnlocked(LocalAppLockController lock) {
    if (!lock.locked) return Future<void>.value();
    final completer = Completer<void>();
    void listener() {
      if (lock.locked || completer.isCompleted) return;
      lock.removeListener(listener);
      completer.complete();
    }

    lock.addListener(listener);
    return completer.future;
  }
}
