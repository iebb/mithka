//
//  link_handler.dart
//
//  Opens a tapped link. t.me / tg:// links resolve in-app via TDLib
//  (getInternalLinkType → public chat / message / invite / phone) and open the
//  corresponding chat; everything else launches in the external browser.
//

import 'package:flutter/material.dart';
import '../components/confirm_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'chat_view.dart';

Future<void> openLink(BuildContext context, String url) async {
  final nav = Navigator.of(context);
  final lower = url.toLowerCase();
  final isTelegram =
      lower.startsWith('tg:') ||
      lower.contains('t.me/') ||
      lower.contains('telegram.me/');
  if (!isTelegram) {
    await _external(url);
    return;
  }

  try {
    final type = await TdClient.shared.query({
      '@type': 'getInternalLinkType',
      'link': url,
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
          'url': url,
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
        if (context.mounted) await _joinInvite(context, nav, url);
      default:
        await _external(url);
    }
  } catch (_) {
    await _external(url);
  }
}

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
