//
//  link_handler.dart
//
//  Opens a tapped link. t.me / tg:// links resolve in-app via TDLib
//  (getInternalLinkType → public chat / message / invite / phone) and open the
//  corresponding chat; everything else launches in the external browser.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app/app_navigator.dart';
import '../chats/search_view.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/toast.dart';
import '../settings/proxy_config.dart';
import '../settings/proxy_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/telegram_cloud_theme.dart';
import '../theme/telegram_cloud_theme_view.dart';
import '../theme/theme_controller.dart';
import 'chat_picker_view.dart';
import 'chat_view.dart';
import 'sticker_set_detail_view.dart';

Future<void> openLink(BuildContext context, String url) async {
  final nav = Navigator.of(context);
  final link = _normalizeTelegramLink(url);
  final isTelegram = link != null;
  if (!isTelegram) {
    await _external(url);
    return;
  }

  final proxy = ProxyConfig.fromTelegramUrl(link);
  if (proxy != null) {
    if (context.mounted) await _addProxyFromLink(context, proxy);
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
        await _openPublicChat(
          nav,
          username,
          draftText: type.str('draft_text') ?? '',
        );
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
      case 'internalLinkTypeChatFolderInvite':
        if (context.mounted) await _joinFolderInvite(context, nav, link);
      case 'internalLinkTypeBotStart':
        await _openBotStart(nav, type);
      case 'internalLinkTypeBotStartInGroup':
        if (context.mounted) await _openBotStartInGroup(context, nav, type);
      case 'internalLinkTypeMessageDraft':
        if (context.mounted) await _shareDraft(context, nav, type);
      case 'internalLinkTypeSavedMessages':
        await _openSavedMessages(nav);
      case 'internalLinkTypeStickerSet':
        await _openStickerSet(nav, type.str('sticker_set_name') ?? '');
      case 'internalLinkTypeSearch':
        if (nav.mounted) {
          unawaited(
            nav.push(MaterialPageRoute(builder: (_) => const SearchView())),
          );
        }
      case 'internalLinkTypeAuthenticationCode':
        await TdClient.shared.query({
          '@type': 'checkAuthenticationCode',
          'code': type.str('code') ?? '',
        });
      case 'internalLinkTypeUserToken':
        final user = await TdClient.shared.query({
          '@type': 'searchUserByToken',
          'token': type.str('token') ?? '',
        });
        final uid = user.int64('id');
        if (uid != null) await _openUser(nav, uid);
      case 'internalLinkTypeDirectMessagesChat':
        await _openPublicChat(nav, type.str('channel_username') ?? '');
      case 'internalLinkTypeBusinessChat':
        await _openBusinessChat(nav, type.str('link_name') ?? '');
      case 'internalLinkTypeProxy':
        final proxy = type.obj('proxy');
        if (proxy != null && context.mounted) {
          await _addProxyFromLink(context, ProxyConfig.fromTdProxy(proxy));
        } else if (context.mounted) {
          showToast(context, AppStrings.t(AppStringKeys.proxyAddFailed));
        }
      case 'internalLinkTypeSettings':
        if (!context.mounted) return;
        final opened = await _openSettingsLink(context, type.obj('section'));
        if (!context.mounted) return;
        if (!opened) {
          showToast(
            context,
            AppStrings.t(AppStringKeys.linkHandlerUnsupportedTelegramLink),
          );
        }
      case 'internalLinkTypeQrCodeAuthentication':
        if (context.mounted) await _confirmQrAuthentication(context, link);
      case 'internalLinkTypeTheme':
        if (context.mounted) await _openCloudTheme(context, nav, link);
      case 'internalLinkTypeUnknownDeepLink':
        await _showDeepLinkInfoOrExternal(link);
      default:
        if (!await _openTelegramFallback(nav, link) && context.mounted) {
          await _external(link);
        }
    }
  } catch (_) {
    if (!await _openTelegramFallback(nav, link) && context.mounted) {
      await _external(link);
    }
  }
}

Future<void> _openCloudTheme(
  BuildContext context,
  NavigatorState nav,
  String link,
) async {
  if (!await ensureThemingEnabledForThemeLink(context) || !context.mounted) {
    return;
  }
  try {
    final theme = await TelegramCloudThemeService().load(link);
    if (!context.mounted || !nav.mounted) return;
    await nav.push(
      PageRouteBuilder<void>(
        pageBuilder: (_, animation, secondaryAnimation) =>
            TelegramCloudThemePreviewView(theme: theme),
        transitionsBuilder: (_, animation, secondaryAnimation, child) =>
            FadeTransition(opacity: animation, child: child),
      ),
    );
  } catch (_) {
    if (context.mounted) {
      showToast(context, AppStringKeys.cloudThemeLoadFailed);
    }
  }
}

@visibleForTesting
Future<bool> ensureThemingEnabledForThemeLink(BuildContext context) async {
  final themeController = context.read<ThemeController>();
  if (themeController.themingEnabled) return true;
  final enable = await _promptEnableTheming(context);
  if (!context.mounted || !enable) return false;
  themeController.themingEnabled = true;
  return true;
}

Future<bool> _promptEnableTheming(BuildContext context) async {
  final enabled = await showGeneralDialog<bool>(
    context: context,
    barrierDismissible: true,
    barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
    barrierColor: const Color(0x66000000),
    transitionDuration: const Duration(milliseconds: 160),
    pageBuilder: (_, _, _) => const _EnableThemingDialog(),
    transitionBuilder: (_, animation, _, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: ScaleTransition(
        scale: Tween(begin: 0.96, end: 1.0).animate(animation),
        child: child,
      ),
    ),
  );
  return enabled ?? false;
}

class _EnableThemingDialog extends StatelessWidget {
  const _EnableThemingDialog();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return SafeArea(
      child: Center(
        child: Container(
          width: 340,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(18),
            boxShadow: const [
              BoxShadow(
                color: Color(0x30000000),
                blurRadius: 28,
                offset: Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 38,
                    height: 38,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: c.linkBlue.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: AppIcon(
                      HeroAppIcons.palette,
                      size: 20,
                      color: c.linkBlue,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      AppStringKeys.themeEnablePromptTitle.l10n(context),
                      style: AppTextStyle.title(
                        c.textPrimary,
                        weight: AppTextWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                AppStringKeys.themeEnablePromptMessage.l10n(context),
                style: AppTextStyle.body(c.textSecondary).copyWith(height: 1.4),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  _ThemeDialogAction(
                    label: AppStringKeys.countryPickerCancel.l10n(context),
                    foreground: c.textSecondary,
                    onTap: () => Navigator.of(context).pop(false),
                  ),
                  const SizedBox(width: 8),
                  _ThemeDialogAction(
                    label: AppStringKeys.themeEnablePromptAction.l10n(context),
                    foreground: c.onAccent,
                    fill: c.linkBlue,
                    onTap: () => Navigator.of(context).pop(true),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeDialogAction extends StatelessWidget {
  const _ThemeDialogAction({
    required this.label,
    required this.foreground,
    required this.onTap,
    this.fill,
  });

  final String label;
  final Color foreground;
  final Color? fill;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: Container(
      height: 38,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 17),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(19),
      ),
      child: Text(
        label,
        style: AppTextStyle.callout(foreground, weight: AppTextWeight.semibold),
      ),
    ),
  );
}

Future<bool> _openSettingsLink(
  BuildContext context,
  Map<String, dynamic>? section,
) async {
  if (section == null) return false;
  final type = section.type;
  final subsection = (section.str('subsection') ?? '').toLowerCase();
  if (type == 'settingsSectionDataAndStorage' &&
      subsection.startsWith('proxy')) {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => subsection == 'proxy/add-proxy'
            ? const ProxyEditView()
            : const ProxyView(),
      ),
    );
    return true;
  }
  return false;
}

Future<void> _addProxyFromLink(BuildContext context, ProxyConfig config) async {
  final ok = await confirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.proxyAddProxy),
    message: '${config.label} ${config.server}:${config.port}',
    confirmText: AppStrings.t(AppStringKeys.proxyAddProxy),
  );
  if (!ok || !context.mounted) return;
  try {
    await TdClient.shared.applyProxyConfig(config);
    await ProxyConfig.save(config);
  } catch (_) {
    if (context.mounted) {
      showToast(context, AppStrings.t(AppStringKeys.proxyAddFailed));
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
  String draftText = '',
}) async {
  try {
    final chat = await TdClient.shared.query({
      '@type': 'searchPublicChat',
      'username': username,
    });
    final chatId = chat.int64('id');
    if (chatId != null && draftText.trim().isNotEmpty) {
      await _setChatDraft(chatId, {
        '@type': 'formattedText',
        'text': draftText.trim(),
      });
    }
    await _openChat(nav, chatId, initialMessageId: initialMessageId);
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _openBotStart(
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final username = type.str('bot_username') ?? '';
  if (username.isEmpty) return;
  final chat = await TdClient.shared.query({
    '@type': 'searchPublicChat',
    'username': username,
  });
  final chatId = chat.int64('id');
  final botUserId = chat.obj('type')?.int64('user_id');
  final parameter = type.str('start_parameter') ?? '';
  final autostart = type.boolean('autostart') ?? false;
  if (autostart && chatId != null && botUserId != null) {
    await TdClient.shared.query({
      '@type': 'sendBotStartMessage',
      'bot_user_id': botUserId,
      'chat_id': chatId,
      'parameter': parameter,
    });
  }
  await _openChat(nav, chatId);
}

Future<void> _openBotStartInGroup(
  BuildContext context,
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final username = type.str('bot_username') ?? '';
  if (username.isEmpty) return;
  final botChat = await TdClient.shared.query({
    '@type': 'searchPublicChat',
    'username': username,
  });
  final botUserId = botChat.obj('type')?.int64('user_id');
  if (botUserId == null || !context.mounted) return;
  final picked = await nav.push<ChatSummary>(
    MaterialPageRoute(builder: (_) => const ChatPickerView()),
  );
  if (picked == null) return;
  final parameter = type.str('start_parameter') ?? '';
  if (parameter.isNotEmpty) {
    await TdClient.shared.query({
      '@type': 'sendBotStartMessage',
      'bot_user_id': botUserId,
      'chat_id': picked.id,
      'parameter': parameter,
    });
  } else {
    await TdClient.shared.query({
      '@type': 'sendMessage',
      'chat_id': picked.id,
      'input_message_content': {
        '@type': 'inputMessageText',
        'text': {'@type': 'formattedText', 'text': '/start@$username'},
      },
    });
  }
  await _openChat(nav, picked.id);
}

Future<void> _shareDraft(
  BuildContext context,
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final text = type.obj('text');
  final plain = text?.str('text') ?? '';
  if (plain.trim().isEmpty || !context.mounted) return;
  final picked = await nav.push<ChatSummary>(
    MaterialPageRoute(
      builder: (_) => const ChatPickerView(title: AppStringKeys.topicChatShare),
    ),
  );
  if (picked == null) return;
  await _setChatDraft(picked.id, text!);
  await _openChat(nav, picked.id);
}

Future<void> _setChatDraft(
  int chatId,
  Map<String, dynamic> formattedText,
) async {
  await TdClient.shared.query({
    '@type': 'setChatDraftMessage',
    'chat_id': chatId,
    'message_thread_id': 0,
    'draft_message': {
      '@type': 'draftMessage',
      'date': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'input_message_text': {
        '@type': 'inputMessageText',
        'text': formattedText,
      },
    },
  });
}

Future<void> _openSavedMessages(NavigatorState nav) async {
  final option = await TdClient.shared.query({
    '@type': 'getOption',
    'name': 'my_id',
  });
  final userId = option.int64('value');
  if (userId == null) return;
  final chat = await TdClient.shared.query({
    '@type': 'createPrivateChat',
    'user_id': userId,
    'force': false,
  });
  await _openChat(nav, chat.int64('id'));
}

Future<void> _openStickerSet(NavigatorState nav, String name) async {
  if (name.trim().isEmpty) return;
  final set = await TdClient.shared.query({
    '@type': 'searchStickerSet',
    'name': name.trim(),
    'ignore_cache': false,
  });
  final setId = set.int64('id');
  if (setId == null || !nav.mounted) return;
  unawaited(
    nav.push(
      MaterialPageRoute(builder: (_) => StickerSetDetailView(setId: setId)),
    ),
  );
}

Future<void> _openBusinessChat(NavigatorState nav, String linkName) async {
  if (linkName.trim().isEmpty) return;
  final info = await TdClient.shared.query({
    '@type': 'getBusinessChatLinkInfo',
    'link_name': linkName.trim(),
  });
  final chatId = info.int64('chat_id');
  final draft = info.obj('message') ?? info.obj('text');
  if (chatId == null) return;
  if (draft != null && (draft.str('text') ?? '').trim().isNotEmpty) {
    await _setChatDraft(chatId, draft);
  }
  await _openChat(nav, chatId);
}

Future<void> _confirmQrAuthentication(BuildContext context, String link) async {
  final ok = await confirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.loginQrCodeTitle),
    message: AppStrings.t(AppStringKeys.linkHandlerQrLoginWarning),
    confirmText: AppStrings.t(AppStringKeys.confirmOk),
  );
  if (!ok) return;
  await TdClient.shared.query({
    '@type': 'confirmQrCodeAuthentication',
    'link': link,
  });
}

Future<void> _showDeepLinkInfoOrExternal(String link) async {
  try {
    await TdClient.shared.query({'@type': 'getDeepLinkInfo', 'link': link});
  } catch (_) {}
  await _external(link);
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
  final chatNavigator = appNavigatorKey.currentState ?? nav;
  unawaited(
    chatNavigator.push(
      MaterialPageRoute(
        builder: (_) => ChatView(
          chatId: chatId,
          title: title,
          initialMessageId: initialMessageId,
        ),
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
  final title =
      info.str('title') ?? AppStrings.t(AppStringKeys.linkHandlerGroupLabel);
  final ok = await confirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.linkHandlerJoin),
    message: AppStrings.t(AppStringKeys.linkHandlerJoinNamedGroupQuestion, {
      'value1': title,
    }),
    confirmText: AppStrings.t(AppStringKeys.linkHandlerJoin),
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

Future<void> _joinFolderInvite(
  BuildContext context,
  NavigatorState nav,
  String url,
) async {
  final info = await TdClient.shared.query({
    '@type': 'checkChatFolderInviteLink',
    'invite_link': url,
  });
  final folder = info.obj('chat_folder_info');
  final title =
      folder?.str('title') ?? AppStrings.t(AppStringKeys.chatInfoChatFolders);
  if (!context.mounted) return;
  final ok = await confirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.linkHandlerJoin),
    message: AppStrings.t(AppStringKeys.linkHandlerJoinNamedGroupQuestion, {
      'value1': title,
    }),
    confirmText: AppStrings.t(AppStringKeys.linkHandlerJoin),
  );
  if (!ok) return;
  try {
    await TdClient.shared.query({
      '@type': 'addChatFolderByInviteLink',
      'invite_link': url,
    });
  } catch (_) {}
  if (nav.mounted) {
    nav.popUntil((route) => route.isFirst);
  }
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
