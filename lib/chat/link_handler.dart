//
//  link_handler.dart
//
//  Opens a tapped link. t.me / tg:// links resolve in-app via TDLib
//  (getInternalLinkType → public chat / message / invite / phone) and open the
//  corresponding chat; everything else launches in the external browser.
//

import 'package:flutter/material.dart';
import '../components/confirm_dialog.dart';
import '../components/toast.dart';
import 'package:url_launcher/url_launcher.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'chat_view.dart';

Future<void> openLink(BuildContext context, String url) async {
  final nav = Navigator.of(context);
  final link = _normalizeTelegramLink(url);
  final isTelegram = link != null;
  if (!isTelegram) {
    await _external(url);
    return;
  }

  try {
    final type = await TdClient.shared.query({
      '@type': 'getInternalLinkType',
      'link': link,
    });
    switch (type.type) {
      case 'internalLinkTypePublicChat':
        final username = type.str('chat_username') ?? '';
        final chat = await TdClient.shared.query({
          '@type': 'searchPublicChat',
          'username': username,
        });
        await _openChat(nav, chat.int64('id'));
      case 'internalLinkTypeMessage':
        final info = await TdClient.shared.query({
          '@type': 'getMessageLinkInfo',
          'url': link,
        });
        final message = info.obj('message');
        final chatId = info.int64('chat_id') ?? message?.int64('chat_id');
        final messageId =
            info.int64('message_id') ??
            message?.int64('id') ??
            type.int64('message_id');
        await _openChat(nav, chatId, initialMessageId: messageId);
      case 'internalLinkTypeUserPhoneNumber':
        final user = await TdClient.shared.query({
          '@type': 'searchUserByPhoneNumber',
          'phone_number': type.str('phone_number') ?? '',
        });
        final uid = user.int64('id');
        if (uid != null) {
          final chat = await TdClient.shared.query({
            '@type': 'createPrivateChat',
            'user_id': uid,
            'force': false,
          });
          await _openChat(nav, chat.int64('id'));
        }
      case 'internalLinkTypeChatInvite':
        if (context.mounted) await _joinInvite(context, nav, link);
      default:
        if (!await _openTelegramFallback(nav, link) && context.mounted) {
          showToast(context, '暂不支持打开此 Telegram 链接');
        }
    }
  } catch (_) {
    if (!await _openTelegramFallback(nav, link) && context.mounted) {
      showToast(context, '无法打开 Telegram 链接');
    }
  }
}

String? _normalizeTelegramLink(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final lower = trimmed.toLowerCase();
  if (lower.startsWith('tg:')) return trimmed;

  var candidate = trimmed;
  if (!candidate.contains('://')) candidate = 'https://$candidate';
  final uri = Uri.tryParse(candidate);
  if (uri == null) return null;
  final host = uri.host.toLowerCase();
  if (host == 't.me' ||
      host == 'telegram.me' ||
      host == 'telegram.dog' ||
      host == 'www.t.me' ||
      host == 'www.telegram.me' ||
      host == 'www.telegram.dog') {
    return uri.replace(scheme: 'https').toString();
  }
  return null;
}

Future<bool> _openTelegramFallback(NavigatorState nav, String link) async {
  final uri = Uri.tryParse(link);
  if (uri == null) return false;

  if (uri.scheme.toLowerCase() == 'tg') {
    final host = uri.host.toLowerCase();
    final params = uri.queryParameters;
    final userId = int.tryParse(params['id'] ?? '');
    if (host == 'user' && userId != null) {
      return _openUser(nav, userId);
    }
    if (host == 'resolve') {
      final username = params['domain'] ?? params['username'];
      final messageId = int.tryParse(params['post'] ?? '');
      if (username != null && username.trim().isNotEmpty) {
        return _openPublicChat(
          nav,
          username.trim(),
          initialMessageId: messageId,
        );
      }
    }
    return false;
  }

  final host = uri.host.toLowerCase();
  final isTelegramHost =
      host == 't.me' ||
      host == 'telegram.me' ||
      host == 'telegram.dog' ||
      host == 'www.t.me' ||
      host == 'www.telegram.me' ||
      host == 'www.telegram.dog';
  if (!isTelegramHost) return false;

  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return false;

  final first = segments.first;
  final lowerFirst = first.toLowerCase();
  if (first.startsWith('+') || lowerFirst == 'joinchat') return false;
  if (lowerFirst == 'c') {
    return _openPrivateMessageLink(nav, segments);
  }
  if (!_isPublicUsername(first)) return false;

  final messageId = segments.length > 1 ? int.tryParse(segments[1]) : null;
  return _openPublicChat(nav, first, initialMessageId: messageId);
}

Future<bool> _openUser(NavigatorState nav, int userId) async {
  try {
    final chat = await TdClient.shared.query({
      '@type': 'createPrivateChat',
      'user_id': userId,
      'force': false,
    });
    await _openChat(nav, chat.int64('id'));
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _openPublicChat(
  NavigatorState nav,
  String username, {
  int? initialMessageId,
}) async {
  try {
    final chat = await TdClient.shared.query({
      '@type': 'searchPublicChat',
      'username': username,
    });
    await _openChat(nav, chat.int64('id'), initialMessageId: initialMessageId);
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _openPrivateMessageLink(
  NavigatorState nav,
  List<String> segments,
) async {
  if (segments.length < 3) return false;
  final internalId = int.tryParse(segments[1]);
  final messageId = int.tryParse(segments[2]);
  if (internalId == null) return false;
  final chatId = int.tryParse('-100$internalId');
  if (chatId == null) return false;
  await _openChat(nav, chatId, initialMessageId: messageId);
  return true;
}

bool _isPublicUsername(String value) =>
    RegExp(r'^[A-Za-z0-9_]{3,32}$').hasMatch(value);

Future<void> _openChat(
  NavigatorState nav,
  int? chatId, {
  int? initialMessageId,
}) async {
  if (chatId == null) return;
  var title = '';
  try {
    final chat = await TdClient.shared.query({
      '@type': 'getChat',
      'chat_id': chatId,
    });
    title = chat.str('title') ?? '';
  } catch (_) {}
  if (!nav.mounted) return;
  nav.push(
    MaterialPageRoute(
      builder: (_) => ChatView(
        chatId: chatId,
        title: title,
        initialMessageId: initialMessageId,
      ),
    ),
  );
}

Future<void> _joinInvite(
  BuildContext context,
  NavigatorState nav,
  String url,
) async {
  final info = await TdClient.shared.query({
    '@type': 'checkChatInviteLink',
    'invite_link': url,
  });
  final existing = info.int64('chat_id') ?? 0;
  if (existing != 0) {
    await _openChat(nav, existing);
    return;
  }
  if (!context.mounted) return;
  final title = info.str('title') ?? '群组';
  final ok = await confirmDialog(
    context,
    title: '加入',
    message: '加入「$title」？',
    confirmText: '加入',
  );
  if (!ok) return;
  try {
    final chat = await TdClient.shared.query({
      '@type': 'joinChatByInviteLink',
      'invite_link': url,
    });
    await _openChat(nav, chat.int64('id'));
  } catch (_) {}
}

Future<void> _external(String url) async {
  var u = url;
  if (!u.contains('://') && !u.startsWith('tg:')) u = 'https://$u';
  final uri = Uri.tryParse(u);
  if (uri == null) return;
  // Open in the external browser. We deliberately do NOT gate on canLaunchUrl():
  // on Android 11+ it returns false when no browser package is visible to the
  // query filter, silently swallowing perfectly valid non-Telegram links. Try
  // the external app first, then fall back to the platform default.
  for (final mode in const [
    LaunchMode.externalApplication,
    LaunchMode.platformDefault,
  ]) {
    try {
      if (await launchUrl(uri, mode: mode)) return;
    } catch (_) {}
  }
}
