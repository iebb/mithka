import 'dart:async';

import 'package:sentry_flutter/sentry_flutter.dart';

import 'telemetry_config.dart';

/// Privacy-safe operational breadcrumbs attached to crashes and feedback.
///
/// Request arguments and TDLib error messages are intentionally excluded: they
/// can contain chat text, usernames, file paths, or authentication material.
abstract final class DiagnosticBreadcrumbs {
  static final _safeType = RegExp(r'^[A-Za-z][A-Za-z0-9_]{0,79}$');
  static const _highValueTdlibOperations = <String>{
    'addMessageReaction',
    'checkAuthenticationCode',
    'checkAuthenticationPasskey',
    'checkAuthenticationPassword',
    'deleteChatHistory',
    'downloadFile',
    'forwardMessages',
    'getChatHistory',
    'getForumTopicHistory',
    'getForumTopics',
    'getMessage',
    'getMessageThreadHistory',
    'getStory',
    'leaveChat',
    'loadActiveStories',
    'logOut',
    'openStory',
    'registerUser',
    'reportStory',
    'requestQrCodeAuthentication',
    'resendAuthenticationCode',
    'searchChatMessages',
    'searchChats',
    'searchContacts',
    'searchMessages',
    'searchPublicChat',
    'searchPublicChats',
    'sendMessage',
    'sendMessageAlbum',
    'setAuthenticationPhoneNumber',
    'setStoryReaction',
  };

  static void tdlibRequestFinished({
    required String requestType,
    required Duration elapsed,
    String? resultType,
    bool failed = false,
    int? errorCode,
  }) {
    if (!sentryEnabled) return;
    final operation = _cleanType(requestType);
    if (!failed && !_highValueTdlibOperations.contains(operation)) return;
    final result = resultType == null ? null : _cleanType(resultType);
    unawaited(
      Sentry.addBreadcrumb(
        Breadcrumb(
          category: 'tdlib.query',
          type: 'debug',
          level: failed ? SentryLevel.warning : SentryLevel.info,
          message: failed ? '$operation failed' : '$operation completed',
          data: <String, Object>{
            'operation': operation,
            'duration_ms': elapsed.inMilliseconds,
            'result': ?result,
            'error_code': ?errorCode,
          },
        ),
      ),
    );
  }

  static String _cleanType(String value) =>
      _safeType.hasMatch(value) ? value : 'unknown';
}
