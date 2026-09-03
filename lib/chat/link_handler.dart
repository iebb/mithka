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

import '../app/primary_chat_launcher.dart';
import '../call/call_manager.dart';
import '../call/calls_view.dart';
import '../chats/search_view.dart';
import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../contacts/add_people_view.dart';
import '../contacts/contacts_view.dart';
import '../contacts/create_group_view.dart';
import '../moments/story_authoring_view.dart';
import '../moments/story_viewer_view.dart';
import '../profile/profile_view.dart';
import '../profile/qr_code_view.dart';
import '../settings/appearance_view.dart';
import '../settings/auto_download_settings_view.dart';
import '../settings/business_settings_view.dart';
import '../settings/chat_folder_management_view.dart';
import '../settings/edit_field_view.dart';
import '../settings/edit_profile_view.dart';
import '../settings/general_settings_view.dart';
import '../settings/language_settings_view.dart';
import '../settings/network_usage_view.dart';
import '../settings/notification_settings_view.dart';
import '../settings/privacy_detail_views.dart';
import '../settings/privacy_security_view.dart';
import '../settings/proxy_config.dart';
import '../settings/proxy_view.dart';
import '../settings/settings_view.dart';
import '../settings/storage_usage_view.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../tdlib/td_requests.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/telegram_cloud_theme.dart';
import '../theme/telegram_cloud_theme_view.dart';
import '../theme/theme_controller.dart';
import 'chat_appearance_message_preview.dart';
import 'chat_picker_view.dart';
import 'chat_wallpaper.dart';
import 'internal_browser_view.dart';
import 'internal_chat_link_router.dart';
import 'link_browser.dart';
import 'sticker_set_detail_view.dart';
import 'telegram_ai_service.dart';
import 'telegram_invoice_checkout_view.dart';
import 'telegram_link.dart';
import 'telegram_link_details_view.dart';
import 'telegram_mini_app_view.dart';
import 'telegram_payment_service.dart';
import 'telegram_premium_features.dart';
import 'telegram_store_purchase_view.dart';

export 'telegram_premium_features.dart';

typedef _TdLinkQuery =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> request);

Future<void> openLink(BuildContext context, String url) async {
  final nav = Navigator.of(context);
  final sourceChat = InternalChatLinkScope.targetOf(context);
  final query = sourceChat == null
      ? TdClient.shared.query
      : (Map<String, dynamic> request) =>
            TdClient.shared.queryForSlot(request, sourceChat.accountSlot);
  final link = normalizeTelegramLink(url);
  final isTelegram = link != null;
  if (!isTelegram) {
    await _openBrowserLink(context, url);
    return;
  }

  final proxy = ProxyConfig.fromTelegramUrl(link);
  if (proxy != null) {
    if (context.mounted) await _addProxyFromLink(context, proxy);
    return;
  }

  var fallbackLink = link;
  try {
    final type = await query({'@type': 'getInternalLinkType', 'link': link});
    switch (type.type) {
      case 'internalLinkTypePublicChat':
        final username = type.str('chat_username') ?? '';
        await _openPublicChat(
          nav,
          username,
          draftText: type.str('draft_text') ?? '',
          sourceChat: sourceChat,
          query: query,
        );
      case 'internalLinkTypeMessage':
        // TDLib can canonicalize a message link (notably tg:// variants).
        // Its contract requires getMessageLinkInfo to receive this returned
        // URL, rather than the original spelling that was classified.
        final resolvedUrl = type.str('url')?.trim();
        if (resolvedUrl != null && resolvedUrl.isNotEmpty) {
          fallbackLink = resolvedUrl;
        }
        final info = await query({
          '@type': 'getMessageLinkInfo',
          'url': fallbackLink,
        });
        final message = info.obj('message');
        final chatId = info.int64('chat_id') ?? message?.int64('chat_id');
        final messageId =
            info.int64('message_id') ??
            message?.int64('id') ??
            type.int64('message_id');
        await _openChat(
          nav,
          chatId,
          initialMessageId: messageId,
          sourceChat: sourceChat,
          query: query,
        );
      case 'internalLinkTypeUserPhoneNumber':
        final user = await query({
          '@type': 'searchUserByPhoneNumber',
          'phone_number': type.str('phone_number') ?? '',
        });
        final uid = user.int64('id');
        if (uid != null) {
          final chat = await query({
            '@type': 'createPrivateChat',
            'user_id': uid,
            'force': false,
          });
          await _openChat(
            nav,
            chat.int64('id'),
            sourceChat: sourceChat,
            query: query,
          );
        }
      case 'internalLinkTypeChatInvite':
        if (context.mounted) await _joinInvite(context, nav, link);
      case 'internalLinkTypeChatFolderInvite':
        if (context.mounted) await _joinFolderInvite(context, nav, link);
      case 'internalLinkTypeBotStart':
        await _openBotStart(nav, type, sourceChat: sourceChat, query: query);
      case 'internalLinkTypeBotStartInGroup':
        if (context.mounted) await _openBotStartInGroup(context, nav, type);
      case 'internalLinkTypeAttachmentMenuBot':
        if (context.mounted) {
          await _openMiniAppLink(
            context,
            type,
            query: query,
            sourceChat: sourceChat,
            attachmentMenu: true,
          );
        }
      case 'internalLinkTypeMainWebApp':
        if (context.mounted) {
          await _openMiniAppLink(
            context,
            type,
            query: query,
            sourceChat: sourceChat,
            mainWebApp: true,
          );
        }
      case 'internalLinkTypeWebApp':
        if (context.mounted) {
          await _openMiniAppLink(
            context,
            type,
            query: query,
            sourceChat: sourceChat,
          );
        }
      case 'internalLinkTypeBackground':
        if (context.mounted) await _applyBackgroundLink(context, type);
      case 'internalLinkTypeLanguagePack':
        if (context.mounted) await _applyLanguagePackLink(context, type);
      case 'internalLinkTypeBotAddToChannel':
        if (context.mounted) await _addBotToChannel(context, nav, type);
      case 'internalLinkTypeMessageDraft':
        if (context.mounted) await _shareDraft(context, nav, type);
      case 'internalLinkTypeSavedMessages':
        if (context.mounted) await _openSavedMessages(context, nav);
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
        final user = await query({
          '@type': 'searchUserByToken',
          'token': type.str('token') ?? '',
        });
        final uid = user.int64('id');
        if (uid != null) {
          await _openUser(nav, uid, sourceChat: sourceChat, query: query);
        }
      case 'internalLinkTypeDirectMessagesChat':
        await _openDirectMessagesChat(nav, type.str('channel_username') ?? '');
      case 'internalLinkTypeChatAffiliateProgram':
        await _openAffiliateProgram(nav, type);
      case 'internalLinkTypeChatBoost':
        await _openChatBoost(nav, type);
      case 'internalLinkTypeInstantView':
        if (context.mounted) await _openInstantView(context, type);
      case 'internalLinkTypeBusinessChat':
        await _openBusinessChat(nav, type.str('link_name') ?? '');
      case 'internalLinkTypeCallsPage':
        if (nav.mounted) {
          unawaited(
            nav.push(MaterialPageRoute(builder: (_) => const CallsView())),
          );
        }
      case 'internalLinkTypeStory':
        await _openStory(nav, type);
      case 'internalLinkTypeStoryAlbum':
        await _openStoryAlbum(nav, type);
      case 'internalLinkTypeLiveStory':
        await _openLiveStory(nav, type);
      case 'internalLinkTypeNewStory':
        if (nav.mounted) {
          await nav.push(
            MaterialPageRoute<void>(builder: (_) => const StoryAuthoringView()),
          );
        }
      case 'internalLinkTypeContactsPage':
        if (nav.mounted) {
          await nav.push(
            MaterialPageRoute<void>(builder: (_) => const ContactsView()),
          );
        }
      case 'internalLinkTypeMyProfilePage':
        if (nav.mounted) {
          await nav.push(
            MaterialPageRoute<void>(builder: (_) => const ProfileView()),
          );
        }
      case 'internalLinkTypeNewGroupChat':
        if (nav.mounted) {
          await nav.push(
            MaterialPageRoute<void>(builder: (_) => const CreateGroupView()),
          );
        }
      case 'internalLinkTypeNewChannelChat':
      case 'internalLinkTypeNewPrivateChat':
        if (nav.mounted) {
          await nav.push(
            MaterialPageRoute<void>(builder: (_) => const AddPeopleView()),
          );
        }
      case 'internalLinkTypeChatSelection':
        if (context.mounted) await _selectAndOpenChat(nav);
      case 'internalLinkTypeGame':
        if (context.mounted) await _shareGame(context, nav, type);
      case 'internalLinkTypeInvoice':
        if (context.mounted) {
          await _openInvoice(context, type.str('invoice_name') ?? '');
        }
      case 'internalLinkTypePremiumGiftPurchase':
        if (context.mounted) {
          await _openPremiumGiftPurchase(context, nav, type);
        }
      case 'internalLinkTypeRestorePurchases':
        if (context.mounted) await _restoreStorePurchases(context, nav);
      case 'internalLinkTypeStarPurchase':
        if (context.mounted) {
          await _openStarPurchase(context, nav, type);
        }
      case 'internalLinkTypeVideoChat':
        if (context.mounted) await _openVideoChat(context, type);
      case 'internalLinkTypeGroupCall':
        if (context.mounted) {
          await _openUnboundGroupCall(nav, type.str('invite_link') ?? link);
        }
      case 'internalLinkTypeGiftCollection':
        await _openGiftCollection(nav, type);
      case 'internalLinkTypeGiftAuction':
        await _openGiftAuction(nav, type.str('auction_id') ?? '');
      case 'internalLinkTypeUpgradedGift':
        await _openUpgradedGift(nav, type.str('name') ?? '');
      case 'internalLinkTypePremiumFeaturesPage':
        await pushTelegramPremiumFeatures(
          nav,
          source: {
            '@type': 'premiumSourceLink',
            'referrer': type.str('referrer') ?? '',
          },
        );
      case 'internalLinkTypePremiumGiftCode':
        if (context.mounted) {
          await _applyPremiumGiftCode(context, type.str('code') ?? '');
        }
      case 'internalLinkTypeOauth':
        if (context.mounted) await _processOauthLink(context, nav, type);
      case 'internalLinkTypePassportDataRequest':
        await _openPassportRequest(nav, type);
      case 'internalLinkTypePhoneNumberConfirmation':
        if (context.mounted) {
          await _confirmPhoneOwnership(context, nav, type);
        }
      case 'internalLinkTypeRequestManagedBot':
        if (context.mounted) {
          await _createManagedBotFromLink(context, nav, type);
        }
      case 'internalLinkTypeTextCompositionStyle':
        if (context.mounted) {
          await _addTextCompositionStyle(context, type.str('style_name') ?? '');
        }
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
        if (context.mounted) {
          await _showDeepLinkInfoOrExternal(context, link);
        }
      default:
        if (!await _openTelegramFallback(
              nav,
              link,
              sourceChat: sourceChat,
              query: query,
            ) &&
            context.mounted) {
          await _openBrowserLink(context, link);
        }
    }
  } catch (_) {
    if (!await _openTelegramFallback(
          nav,
          fallbackLink,
          sourceChat: sourceChat,
          query: query,
        ) &&
        context.mounted) {
      await _openBrowserLink(context, fallbackLink);
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
      AppFadePageRoute<void>(
        pageBuilder: (_, animation, secondaryAnimation) =>
            TelegramCloudThemePreviewView(theme: theme),
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
            borderRadius: BorderRadius.circular(AppRadius.lg),
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
                      borderRadius: BorderRadius.circular(AppRadius.card),
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
  final Widget? destination = switch (type) {
    'settingsSectionAppearance' => const AppearanceView(),
    'settingsSectionBusiness' => const BusinessSettingsView(),
    'settingsSectionChatFolders' => const ChatFolderManagementView(),
    'settingsSectionDataAndStorage' when subsection.startsWith('proxy') =>
      subsection == 'proxy/add-proxy'
          ? const ProxyEditView()
          : const ProxyView(),
    'settingsSectionDataAndStorage' when subsection.startsWith('storage') =>
      const StorageUsageView(),
    'settingsSectionDataAndStorage' when subsection.startsWith('usage') =>
      const NetworkUsageView(),
    'settingsSectionDataAndStorage'
        when subsection.startsWith('auto-download') =>
      const AutoDownloadSettingsView(),
    'settingsSectionDataAndStorage' => const GeneralSettingsView(),
    'settingsSectionDevices' => const ActiveSessionsView(),
    'settingsSectionEditProfile' => const EditProfileView(),
    'settingsSectionLanguage' => const AppLanguageSettingsView(),
    'settingsSectionNotifications' => const NotificationSettingsView(),
    'settingsSectionPrivacyAndSecurity' => const PrivacySecurityView(),
    'settingsSectionQrCode' => const QRCodeView(),
    'settingsSectionSearch' => const SettingsView(focusSearch: true),
    _ => null,
  };
  if (destination == null) return false;
  await Navigator.of(
    context,
  ).push(MaterialPageRoute<void>(builder: (_) => destination));
  return true;
}

Future<void> _addProxyFromLink(BuildContext context, ProxyConfig config) async {
  final ok = await showAppConfirmDialog(
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

/// Converts the server-local post number carried by Telegram link syntax to
/// the TDLib message identifier used by chat/history APIs.
///
/// IDs returned by getMessageLinkInfo are already TDLib IDs and must never be
/// passed through this conversion; this helper is only for the manual fallback
/// grammars parsed below.
@visibleForTesting
int? telegramFallbackMessageId(String link) {
  final uri = Uri.tryParse(link);
  if (uri == null) return null;
  String? post;
  final scheme = uri.scheme.toLowerCase();
  if (scheme == 'tg' || scheme == 'mk' || scheme == 'mithka') {
    final host = uri.host.toLowerCase();
    if (host == 'resolve' || host == 'privatepost') {
      post = uri.queryParameters['post'];
    }
  } else {
    final host = uri.host.toLowerCase();
    final isTelegramHost =
        host == 't.me' ||
        host == 'telegram.me' ||
        host == 'telegram.dog' ||
        host == 'www.t.me' ||
        host == 'www.telegram.me' ||
        host == 'www.telegram.dog';
    if (!isTelegramHost) return null;
    final segments = uri.pathSegments
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (segments.isEmpty) return null;
    post = segments.first.toLowerCase() == 'c'
        ? (segments.length > 2 ? segments[2] : null)
        : (segments.length > 1 ? segments[1] : null);
  }
  final serverPostId = int.tryParse(post ?? '');
  if (serverPostId == null || serverPostId <= 0) return null;
  return serverPostId << 20;
}

Future<bool> _openTelegramFallback(
  NavigatorState nav,
  String link, {
  InternalChatLinkTarget? sourceChat,
  _TdLinkQuery? query,
}) async {
  final uri = Uri.tryParse(link);
  if (uri == null) return false;

  // mk:// and mithka:// are the app's own registered schemes; they carry the
  // same path/query grammar as tg:// links.
  const appSchemes = {'tg', 'mk', 'mithka'};
  if (appSchemes.contains(uri.scheme.toLowerCase())) {
    final host = uri.host.toLowerCase();
    final params = uri.queryParameters;
    final userId = int.tryParse(params['id'] ?? '');
    if (host == 'user' && userId != null) {
      return _openUser(nav, userId, sourceChat: sourceChat, query: query);
    }
    if (host == 'resolve') {
      final username = params['domain'] ?? params['username'];
      final messageId = telegramFallbackMessageId(link);
      if (username != null && username.trim().isNotEmpty) {
        return _openPublicChat(
          nav,
          username.trim(),
          initialMessageId: messageId,
          sourceChat: sourceChat,
          query: query,
        );
      }
    }
    if (host == 'privatepost') {
      final channelId = int.tryParse(params['channel'] ?? '');
      if (channelId == null || channelId <= 0) return false;
      final chatId = int.tryParse('-100$channelId');
      if (chatId == null) return false;
      await _openChat(
        nav,
        chatId,
        initialMessageId: telegramFallbackMessageId(link),
        sourceChat: sourceChat,
        query: query,
      );
      return true;
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
    return _openPrivateMessageLink(
      nav,
      segments,
      messageId: telegramFallbackMessageId(link),
      sourceChat: sourceChat,
      query: query,
    );
  }
  if (!_isPublicUsername(first)) return false;

  return _openPublicChat(
    nav,
    first,
    initialMessageId: telegramFallbackMessageId(link),
    sourceChat: sourceChat,
    query: query,
  );
}

Future<bool> _openUser(
  NavigatorState nav,
  int userId, {
  InternalChatLinkTarget? sourceChat,
  _TdLinkQuery? query,
}) async {
  final queryAccount = query ?? TdClient.shared.query;
  try {
    final chat = await queryAccount({
      '@type': 'createPrivateChat',
      'user_id': userId,
      'force': false,
    });
    await _openChat(
      nav,
      chat.int64('id'),
      sourceChat: sourceChat,
      query: queryAccount,
    );
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
  InternalChatLinkTarget? sourceChat,
  _TdLinkQuery? query,
}) async {
  final queryAccount = query ?? TdClient.shared.query;
  try {
    final chat = await queryAccount({
      '@type': 'searchPublicChat',
      'username': username,
    });
    final chatId = chat.int64('id');
    if (chatId != null && draftText.trim().isNotEmpty) {
      await _setChatDraft(chatId, {
        '@type': 'formattedText',
        'text': draftText.trim(),
      }, query: queryAccount);
    }
    await _openChat(
      nav,
      chatId,
      initialMessageId: initialMessageId,
      sourceChat: sourceChat,
      query: queryAccount,
    );
    return true;
  } catch (_) {
    return false;
  }
}

Future<void> _openBotStart(
  NavigatorState nav,
  Map<String, dynamic> type, {
  InternalChatLinkTarget? sourceChat,
  _TdLinkQuery? query,
}) async {
  final queryAccount = query ?? TdClient.shared.query;
  final username = type.str('bot_username') ?? '';
  if (username.isEmpty) return;
  final chat = await queryAccount({
    '@type': 'searchPublicChat',
    'username': username,
  });
  final chatId = chat.int64('id');
  final botUserId = chat.obj('type')?.int64('user_id');
  final parameter = type.str('start_parameter') ?? '';
  final autostart = type.boolean('autostart') ?? false;
  if (autostart && chatId != null && botUserId != null) {
    await queryAccount({
      '@type': 'sendBotStartMessage',
      'bot_user_id': botUserId,
      'chat_id': chatId,
      'parameter': parameter,
    });
  }
  await _openChat(nav, chatId, sourceChat: sourceChat, query: queryAccount);
}

Future<void> _openMiniAppLink(
  BuildContext context,
  Map<String, dynamic> type, {
  required _TdLinkQuery query,
  InternalChatLinkTarget? sourceChat,
  bool mainWebApp = false,
  bool attachmentMenu = false,
}) async {
  final username = type.str('bot_username')?.trim() ?? '';
  if (username.isEmpty) return;
  final botChat = await query({
    '@type': 'searchPublicChat',
    'username': username,
  });
  final botUserId = botChat.obj('type')?.int64('user_id');
  if (botUserId == null || !context.mounted) return;
  final user = await query({'@type': 'getUser', 'user_id': botUserId});
  final botType = user.obj('type');
  if (botType?.type != 'userTypeBot' || !context.mounted) return;
  if (mainWebApp && !(botType?.boolean('has_main_web_app') ?? false)) return;
  final attachmentMenuConsentRequired =
      mainWebApp &&
      (botType?.boolean('can_be_added_to_attachment_menu') ?? false);

  var chatId = sourceChat?.chatId ?? 0;
  if (attachmentMenu) {
    final target = await Navigator.of(context).push<ChatSummary>(
      MaterialPageRoute(builder: (_) => const ChatPickerView()),
    );
    if (target == null || !context.mounted) return;
    chatId = target.id;
  }
  final title = TDParse.userName(user).trim();
  await openTelegramMiniApp(
    context,
    chatId: chatId,
    botUserId: botUserId,
    url: attachmentMenu ? type.str('url') ?? '' : '',
    title: title.isEmpty ? username : title,
    mainWebApp: mainWebApp,
    attachmentMenuWebApp: attachmentMenu,
    startParameter: type.str('start_parameter') ?? '',
    webAppShortName: type.str('web_app_short_name') ?? '',
    openMode: type.obj('mode'),
    photo: TDParse.smallPhoto(user.obj('profile_photo')),
    accountSlot: sourceChat?.accountSlot,
    attachmentMenuConsentRequired: attachmentMenuConsentRequired,
  );
}

Future<void> _applyBackgroundLink(
  BuildContext context,
  Map<String, dynamic> type,
) async {
  final name = type.str('background_name')?.trim() ?? '';
  if (name.isEmpty) return;
  final background = await TdClient.shared.query({
    '@type': 'searchBackground',
    'name': name,
  });
  final backgroundId = background.int64('id');
  if (backgroundId == null || !context.mounted) return;
  final wallpaperController = ChatWallpaperController.shared;
  final wallpaper = wallpaperController.previewWallpaperFromBackground(
    background,
  );
  if (wallpaper == null) return;
  final dark = Theme.of(context).brightness == Brightness.dark;
  final accepted = await showAppConfirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.appearanceTitle),
    message: name,
    content: AnimatedBuilder(
      animation: wallpaperController,
      builder: (context, _) => ChatAppearancePreviewCard(
        key: const ValueKey('background-link-appearance-preview'),
        wallpaper: wallpaperController.resolvedWallpaper(wallpaper),
        label: AppStrings.t(AppStringKeys.chatWallpaperTitle),
        brightness: dark ? Brightness.dark : Brightness.light,
      ),
    ),
    confirmText: AppStrings.t(AppStringKeys.chatWallpaperApply),
  );
  if (!accepted || !context.mounted) return;
  await wallpaperController.applyDefaultWallpaper(wallpaper, dark: dark);
}

Future<void> _applyLanguagePackLink(
  BuildContext context,
  Map<String, dynamic> type,
) async {
  final id = type.str('language_pack_id')?.trim() ?? '';
  if (id.isEmpty) return;
  final pack = await TdClient.shared.query({
    '@type': 'getLanguagePackInfo',
    'language_pack_id': id,
  });
  if (!context.mounted) return;
  final name = pack.str('native_name') ?? pack.str('name') ?? id;
  final accepted = await showAppConfirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.languageTitle),
    message: name,
    confirmText: AppStrings.t(AppStringKeys.chatWallpaperApply),
  );
  if (!accepted) return;
  await TdClient.shared.query({
    '@type': 'setOption',
    'name': 'language_pack_id',
    'value': {'@type': 'optionValueString', 'value': pack.str('id') ?? id},
  });
}

Future<void> _addBotToChannel(
  BuildContext context,
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final username = type.str('bot_username')?.trim() ?? '';
  final rights = type.obj('administrator_rights');
  if (username.isEmpty || rights == null) return;
  final botChat = await TdClient.shared.query({
    '@type': 'searchPublicChat',
    'username': username,
  });
  final botUserId = botChat.obj('type')?.int64('user_id');
  if (botUserId == null || !context.mounted) return;
  final picked = await nav.push<ChatSummary>(
    MaterialPageRoute(
      builder: (_) => const ChatPickerView(allowedKinds: {ChatKind.channel}),
    ),
  );
  if (picked == null || !context.mounted) return;
  final accepted = await showAppConfirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.chatListCreateChannel),
    message: AppStrings.t(
      AppStringKeys.linkHandlerAddBotAsAdministratorValue1Value2,
      {'value1': username, 'value2': picked.title},
    ),
    confirmText: AppStrings.t(AppStringKeys.confirmContinue),
  );
  if (!accepted) return;
  await TdClient.shared.query({
    '@type': 'setChatMemberStatus',
    'chat_id': picked.id,
    'member_id': {'@type': 'messageSenderUser', 'user_id': botUserId},
    'status': {
      '@type': 'chatMemberStatusAdministrator',
      'custom_title': '',
      'rights': rights,
    },
  });
  await _openChat(nav, picked.id);
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
  final bot = await TdClient.shared.query({
    '@type': 'getUser',
    'user_id': botUserId,
  });
  if (bot.obj('type')?.type != 'userTypeBot' || !context.mounted) return;
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
  Map<String, dynamic> formattedText, {
  _TdLinkQuery? query,
}) async {
  await (query ?? TdClient.shared.query)(
    setTextChatDraftRequest(
      chatId: chatId,
      formattedText: formattedText,
      date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    ),
  );
}

Future<void> _openSavedMessages(
  BuildContext context,
  NavigatorState nav,
) async {
  if (!nav.mounted) return;
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
  final chatId = chat.int64('id');
  if (chatId == null) return;
  if (!nav.mounted) return;
  await _openChat(nav, chatId);
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

Future<void> _openDirectMessagesChat(
  NavigatorState nav,
  String username,
) async {
  if (username.trim().isEmpty) return;
  final chat = await TdClient.shared.query({
    '@type': 'searchPublicChat',
    'username': username.trim(),
  });
  var chatId = chat.int64('id');
  final supergroupId = chat.obj('type')?.int64('supergroup_id');
  if (supergroupId != null) {
    final fullInfo = await TdClient.shared.query({
      '@type': 'getSupergroupFullInfo',
      'supergroup_id': supergroupId,
    });
    final directMessagesChatId = fullInfo.int64('direct_messages_chat_id');
    if (directMessagesChatId != null && directMessagesChatId != 0) {
      chatId = directMessagesChatId;
    }
  }
  await _openChat(nav, chatId);
}

Future<void> _openAffiliateProgram(
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final username = type.str('username')?.trim() ?? '';
  if (username.isEmpty) return;
  final chat = await TdClient.shared.query({
    '@type': 'searchChatAffiliateProgram',
    'username': username,
    'referrer': type.str('referrer') ?? '',
  });
  await _openChat(nav, chat.int64('id'));
}

Future<void> _openChatBoost(
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final url = type.str('url')?.trim() ?? '';
  if (url.isEmpty) return;
  final info = await TdClient.shared.query({
    '@type': 'getChatBoostLinkInfo',
    'url': url,
  });
  final chatId = info.int64('chat_id');
  if (chatId == null || !nav.mounted) return;
  var title = '';
  try {
    title =
        (await TdClient.shared.query({
          '@type': 'getChat',
          'chat_id': chatId,
        })).str('title') ??
        '';
  } catch (_) {}
  await nav.push(
    MaterialPageRoute<void>(
      builder: (_) => TelegramLinkDetailsView(
        title: title.isEmpty
            ? AppStrings.t(AppStringKeys.linkHandlerBoostChat)
            : title,
        icon: HeroAppIcons.arrowUp,
        subtitle: AppStrings.t(
          info.boolean('is_public') == true
              ? AppStringKeys.linkHandlerPublicBoostLink
              : AppStringKeys.linkHandlerPrivateBoostLink,
        ),
        details: [
          TelegramLinkDetail(
            AppStrings.t(AppStringKeys.linkHandlerDetailChat),
            '$chatId',
          ),
        ],
        trailing: Builder(
          builder: (context) => Semantics(
            button: true,
            label: AppStrings.t(AppStringKeys.linkHandlerOpenChat),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Navigator.of(context).pop();
                unawaited(_openChat(nav, chatId));
              },
              child: Container(
                width: double.infinity,
                height: 46,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brand,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(
                  AppStrings.t(AppStringKeys.linkHandlerOpenChat),
                  style: const TextStyle(
                    color: Color(0xFFFFFFFF),
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _selectAndOpenChat(NavigatorState nav) async {
  if (!nav.mounted) return;
  final picked = await nav.push<ChatSummary>(
    MaterialPageRoute(builder: (_) => const ChatPickerView()),
  );
  if (picked != null) await _openChat(nav, picked.id);
}

Future<void> _openInstantView(
  BuildContext context,
  Map<String, dynamic> type,
) async {
  final url = type.str('url')?.trim() ?? '';
  if (url.isEmpty) return;
  // Resolve the page through TDLib first so Telegram can warm/cache the
  // canonical Instant View. Mithka doesn't yet include an owned rich-page
  // renderer, so the canonical page then follows the user's browser choice.
  await TdClient.shared.query({
    '@type': 'getWebPageInstantView',
    'url': url,
    'only_local': false,
  });
  if (context.mounted) await _openBrowserLink(context, url);
}

Future<void> _processOauthLink(
  BuildContext context,
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final url = type.str('url')?.trim() ?? '';
  if (url.isEmpty) return;
  final info = await TdClient.shared.query({
    '@type': 'getOauthLinkInfo',
    'url': url,
    'in_app_origin': '',
  });
  if (!context.mounted) return;
  var matchCode = '';
  if (info.boolean('match_code_first') == true) {
    final value = await nav.push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldView(
          title: AppStrings.t(AppStringKeys.linkHandlerAuthorizationCode),
          initial: '',
          hint: AppStrings.t(AppStringKeys.linkHandlerEnterMatchingCode),
          maxLength: 64,
        ),
      ),
    );
    if (value == null || value.isEmpty) {
      await TdClient.shared.query({'@type': 'declineOauthRequest', 'url': url});
      return;
    }
    matchCode = value;
    await TdClient.shared.query({
      '@type': 'checkOauthRequestMatchCode',
      'url': url,
      'match_code': matchCode,
    });
  }
  if (!context.mounted) return;
  final domain = info.str('domain') ?? '';
  final location = info.str('location') ?? '';
  final asksWrite = info.boolean('request_write_access') ?? false;
  final asksPhone = info.boolean('request_phone_number_access') ?? false;
  final additionalPermission = asksWrite && asksPhone
      ? AppStrings.t(AppStringKeys.linkHandlerAlsoSendMessagesAndAccessPhone)
      : asksWrite
      ? AppStrings.t(AppStringKeys.linkHandlerAlsoSendMessages)
      : asksPhone
      ? AppStrings.t(AppStringKeys.linkHandlerAlsoAccessPhone)
      : '';
  final accepted = await showAppConfirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.linkHandlerAuthorizeDomain, {
      'value1': domain.isEmpty
          ? AppStrings.t(AppStringKeys.linkHandlerTelegramLogin)
          : domain,
    }),
    message: [
      if (location.isNotEmpty) location,
      if (additionalPermission.isNotEmpty) additionalPermission,
    ].join('\n'),
    confirmText: AppStrings.t(AppStringKeys.confirmContinue),
  );
  if (!accepted) {
    await TdClient.shared.query({'@type': 'declineOauthRequest', 'url': url});
    return;
  }
  final result = await TdClient.shared.query({
    '@type': 'acceptOauthRequest',
    'url': url,
    'match_code': matchCode,
    'allow_write_access': asksWrite,
    'allow_phone_number_access': asksPhone,
  });
  final redirect = result.str('url')?.trim() ?? '';
  if (redirect.isNotEmpty) await _launchExternal(redirect);
}

Future<void> _openPassportRequest(
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final botUserId = type.int64('bot_user_id');
  if (botUserId == null) return;
  final form = await TdClient.shared.query({
    '@type': 'getPassportAuthorizationForm',
    'bot_user_id': botUserId,
    'scope': type.str('scope') ?? '',
    'public_key': type.str('public_key') ?? '',
    'nonce': type.str('nonce') ?? '',
  });
  if (!nav.mounted) return;
  final required = form.objects('required_elements') ?? const [];
  await nav.push(
    MaterialPageRoute<void>(
      builder: (_) => TelegramLinkDetailsView(
        title: AppStrings.t(AppStringKeys.linkHandlerTelegramPassportRequest),
        icon: HeroAppIcons.idBadge,
        subtitle: AppStrings.t(AppStringKeys.linkHandlerPassportSubtitle),
        details: [
          TelegramLinkDetail(
            AppStrings.t(AppStringKeys.linkHandlerDetailRequestedGroups),
            '${required.length}',
          ),
          if ((form.str('privacy_policy_url') ?? '').isNotEmpty)
            TelegramLinkDetail(
              AppStrings.t(AppStringKeys.linkHandlerDetailPrivacyPolicy),
              form.str('privacy_policy_url')!,
            ),
        ],
      ),
    ),
  );
}

Future<void> _confirmPhoneOwnership(
  BuildContext context,
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final phone = type.str('phone_number')?.trim() ?? '';
  final hash = type.str('hash') ?? '';
  if (phone.isEmpty || hash.isEmpty) return;
  final accepted = await showAppConfirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.linkHandlerConfirmPhoneOwnership),
    message: phone,
    confirmText: AppStrings.t(AppStringKeys.confirmContinue),
  );
  if (!accepted) return;
  await TdClient.shared.query({
    '@type': 'sendPhoneNumberCode',
    'phone_number': phone,
    'settings': null,
    'type': {'@type': 'phoneNumberCodeTypeConfirmOwnership', 'hash': hash},
  });
  if (!nav.mounted) return;
  final code = await nav.push<String>(
    MaterialPageRoute(
      builder: (_) => EditFieldView(
        title: AppStrings.t(AppStringKeys.loginVerificationCode),
        initial: '',
        hint: AppStrings.t(AppStringKeys.authCodeSent),
        maxLength: 12,
        keyboardType: TextInputType.number,
      ),
    ),
  );
  if (code == null || code.isEmpty) return;
  await TdClient.shared.query({'@type': 'checkPhoneNumberCode', 'code': code});
}

Future<void> _createManagedBotFromLink(
  BuildContext context,
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final managerUsername = type.str('manager_bot_username')?.trim() ?? '';
  final username = type.str('suggested_bot_username')?.trim() ?? '';
  if (managerUsername.isEmpty || username.isEmpty) return;
  final managerChat = await TdClient.shared.query({
    '@type': 'searchPublicChat',
    'username': managerUsername,
  });
  final managerUserId = managerChat.obj('type')?.int64('user_id');
  if (managerUserId == null) return;
  final manager = await TdClient.shared.query({
    '@type': 'getUser',
    'user_id': managerUserId,
  });
  if (manager.obj('type')?.type != 'userTypeBot' ||
      manager.obj('type')?.boolean('can_manage_bots') != true ||
      !context.mounted) {
    return;
  }
  final suggestedName = type.str('suggested_bot_name')?.trim() ?? '';
  final name = suggestedName.isEmpty ? username : suggestedName;
  final accepted = await showAppConfirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.linkHandlerCreateManagedBot),
    message: AppStrings.t(
      AppStringKeys.linkHandlerCreateManagedBotMessageValue1Value2Value3,
      {'value1': name, 'value2': username, 'value3': managerUsername},
    ),
    confirmText: AppStrings.t(AppStringKeys.confirmContinue),
  );
  if (!accepted) return;
  final user = await TdClient.shared.query({
    '@type': 'createBot',
    'manager_bot_user_id': managerUserId,
    'name': name,
    'username': username,
    'via_link': true,
  });
  final userId = user.int64('id');
  if (userId != null) await _openUser(nav, userId);
}

Future<void> _openStory(NavigatorState nav, Map<String, dynamic> type) async {
  final username = type.str('story_poster_username') ?? '';
  final storyId = type.integer('story_id');
  if (username.isEmpty || storyId == null) return;
  final chat = await TdClient.shared.query({
    '@type': 'searchPublicChat',
    'username': username,
  });
  final chatId = chat.int64('id');
  if (chatId == null) return;
  // Resolve before navigation so an expired/private story follows the normal
  // link error path rather than opening a permanently loading viewer.
  await TdClient.shared.query({
    '@type': 'getStory',
    'story_poster_chat_id': chatId,
    'story_id': storyId,
    'only_local': false,
  });
  if (!nav.mounted) return;
  unawaited(
    nav.push(
      MaterialPageRoute(
        builder: (_) => StoryViewerView(chatId: chatId, storyIds: [storyId]),
      ),
    ),
  );
}

Future<void> _openStoryAlbum(
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final username = type.str('story_album_owner_username') ?? '';
  final albumId = type.integer('story_album_id');
  if (username.isEmpty || albumId == null) return;
  final chat = await TdClient.shared.query({
    '@type': 'searchPublicChat',
    'username': username,
  });
  final chatId = chat.int64('id');
  if (chatId == null) return;
  final result = await TdClient.shared.query({
    '@type': 'getStoryAlbumStories',
    'chat_id': chatId,
    'story_album_id': albumId,
    'offset': 0,
    'limit': 100,
  });
  final storyIds = <int>[
    for (final story
        in result.objects('stories') ?? const <Map<String, dynamic>>[])
      if (story.integer('id') case final int id) id,
  ];
  if (storyIds.isEmpty || !nav.mounted) return;
  unawaited(
    nav.push(
      MaterialPageRoute(
        builder: (_) => StoryViewerView(chatId: chatId, storyIds: storyIds),
      ),
    ),
  );
}

Future<void> _openLiveStory(
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final username = type.str('story_poster_username')?.trim() ?? '';
  if (username.isEmpty) return;
  final chat = await TdClient.shared.query({
    '@type': 'searchPublicChat',
    'username': username,
  });
  final chatId = chat.int64('id');
  if (chatId == null) return;
  final active = await TdClient.shared.query({
    '@type': 'getChatActiveStories',
    'chat_id': chatId,
  });
  final liveStories =
      (active.objects('stories') ?? const <Map<String, dynamic>>[])
          .where((story) => story.boolean('is_live') == true)
          .toList(growable: false);
  final storyId = liveStories.isEmpty
      ? null
      : liveStories.last.integer('story_id');
  if (storyId == null || !nav.mounted) return;
  await nav.push(
    MaterialPageRoute<void>(
      builder: (_) => StoryViewerView(chatId: chatId, storyIds: [storyId]),
    ),
  );
}

Future<void> _shareGame(
  BuildContext context,
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final username = type.str('bot_username') ?? '';
  final shortName = type.str('game_short_name') ?? '';
  if (username.isEmpty || shortName.isEmpty) return;
  final botChat = await TdClient.shared.query({
    '@type': 'searchPublicChat',
    'username': username,
  });
  final botUserId = botChat.obj('type')?.int64('user_id');
  if (botUserId == null || !context.mounted) return;
  final picked = await nav.push<ChatSummary>(
    MaterialPageRoute(
      builder: (_) => const ChatPickerView(title: AppStringKeys.topicChatShare),
    ),
  );
  if (picked == null) return;
  await TdClient.shared.query({
    '@type': 'sendMessage',
    'chat_id': picked.id,
    'input_message_content': {
      '@type': 'inputMessageGame',
      'bot_user_id': botUserId,
      'game_short_name': shortName,
    },
  });
  await _openChat(nav, picked.id);
}

Future<TelegramInvoiceOutcome> _openInvoice(
  BuildContext context,
  String name,
) async {
  if (name.trim().isEmpty) {
    return const TelegramInvoiceOutcome(TelegramInvoiceStatus.failed);
  }
  return openTelegramInvoiceCheckout(
    context,
    inputInvoice: {'@type': 'inputInvoiceName', 'name': name.trim()},
  );
}

Future<void> _openPremiumGiftPurchase(
  BuildContext context,
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final picked = await nav.push<ChatSummary>(
    MaterialPageRoute(
      builder: (_) => ChatPickerView(
        title: AppStrings.t(AppStringKeys.linkHandlerChooseAPremiumRecipient),
        allowedKinds: {ChatKind.privateChat},
      ),
    ),
  );
  final userId = picked?.peerUserId;
  if (userId == null || !context.mounted) return;
  final user = await TdClient.shared.query({
    '@type': 'getUser',
    'user_id': userId,
  });
  if (user.obj('type')?.type != 'userTypeRegular') {
    if (context.mounted) {
      showToast(
        context,
        AppStrings.t(
          AppStringKeys.linkHandlerPremiumGiftsCanBeSentOnlyToPeople,
        ),
      );
    }
    return;
  }
  final response = await TdClient.shared.query({
    '@type': 'getPremiumGiftPaymentOptions',
  });
  final products = <TelegramStoreProduct>[
    for (final option
        in response.objects('options') ?? const <Map<String, dynamic>>[])
      if ((option.str('store_product_id') ?? '').isNotEmpty)
        TelegramStoreProduct(
          productId: option.str('store_product_id')!,
          currency: option.str('currency') ?? '',
          amount: option.int64('amount') ?? 0,
          monthCount: option.integer('month_count') ?? 0,
          starCount: option.int64('star_count') ?? 0,
          label: _premiumGiftLabel(option.integer('month_count') ?? 0),
        ),
  ];
  if (!nav.mounted) return;
  final product = await nav.push<TelegramStoreProduct>(
    MaterialPageRoute(
      builder: (_) => TelegramStoreProductPickerView(
        title: AppStrings.t(AppStringKeys.linkHandlerGiftTelegramPremium),
        subtitle: AppStrings.t(
          AppStringKeys.linkHandlerPremiumGiftPickerSubtitleValue1,
          {'value1': TDParse.userName(user)},
        ),
        products: products,
      ),
    ),
  );
  if (product == null || !context.mounted) return;
  final service = TelegramStorePurchaseService();
  if (!await service.isSupported()) {
    if (nav.mounted) {
      await _showStoreDependency(
        nav,
        title: AppStrings.t(AppStringKeys.linkHandlerPremiumGiftUnavailable),
        operation: AppStrings.t(
          AppStringKeys.linkHandlerOperationPremiumGiftPurchase,
        ),
      );
    }
    return;
  }
  final storePurpose = TelegramStorePurchaseService.premiumGiftPurpose(
    currency: product.currency,
    amount: product.amount,
    userId: userId,
  );
  if (!await _preflightStorePurchase(
    nav,
    service: service,
    purpose: storePurpose,
    title: AppStrings.t(AppStringKeys.linkHandlerPremiumGiftUnavailable),
    operation: AppStrings.t(
      AppStringKeys.linkHandlerOperationPremiumGiftPurchase,
    ),
  )) {
    return;
  }
  if (!context.mounted) return;
  final confirmed = await showAppConfirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.linkHandlerConfirmPremiumGift),
    message: AppStrings.t(
      AppStringKeys.linkHandlerConfirmPremiumGiftMessageValue1Value2,
      {'value1': product.label, 'value2': TDParse.userName(user)},
    ),
    confirmText: AppStrings.t(AppStringKeys.confirmContinue),
  );
  if (!confirmed || !nav.mounted) return;
  await nav.push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TelegramStorePurchaseProgressView(
        title: AppStrings.t(AppStringKeys.linkHandlerPremiumGift),
        subtitle: product.label,
        purchase: () => service.purchaseAndAssign(
          productId: product.productId,
          purpose: storePurpose,
        ),
      ),
    ),
  );
}

Future<void> _restoreStorePurchases(
  BuildContext context,
  NavigatorState nav,
) async {
  final service = TelegramStorePurchaseService();
  if (!await service.isSupported()) {
    if (nav.mounted) {
      await _showStoreDependency(
        nav,
        title: AppStrings.t(AppStringKeys.linkHandlerRestoreUnavailable),
        operation: AppStrings.t(
          AppStringKeys.linkHandlerOperationRestorePurchases,
        ),
      );
    }
    return;
  }
  final storePurpose = TelegramStorePurchaseService.premiumSubscriptionPurpose(
    restore: true,
  );
  if (!await _preflightStorePurchase(
    nav,
    service: service,
    purpose: storePurpose,
    title: AppStrings.t(AppStringKeys.linkHandlerRestoreUnavailable),
    operation: AppStrings.t(AppStringKeys.linkHandlerOperationRestorePurchases),
  )) {
    return;
  }
  if (!context.mounted) return;
  final confirmed = await showAppConfirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.linkHandlerRestoreAppStorePurchases),
    message: AppStrings.t(AppStringKeys.linkHandlerRestoreMessage),
    confirmText: AppStrings.t(AppStringKeys.accountBackupRestore),
  );
  if (!confirmed || !nav.mounted) return;
  await nav.push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TelegramStorePurchaseProgressView(
        title: AppStrings.t(AppStringKeys.mithkaProRestore),
        subtitle: AppStrings.t(AppStringKeys.linkHandlerTelegramPremium),
        purchase: service.restorePremiumPurchases,
      ),
    ),
  );
}

Future<void> _openStarPurchase(
  BuildContext context,
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final requested = type.int64('star_count') ?? 0;
  final purposeLabel = type.str('purpose')?.trim() ?? '';
  final response = await TdClient.shared.query({
    '@type': 'getStarPaymentOptions',
  });
  final products = <TelegramStoreProduct>[
    for (final option
        in response.objects('options') ?? const <Map<String, dynamic>>[])
      if ((option.str('store_product_id') ?? '').isNotEmpty)
        TelegramStoreProduct(
          productId: option.str('store_product_id')!,
          currency: option.str('currency') ?? '',
          amount: option.int64('amount') ?? 0,
          starCount: option.int64('star_count') ?? 0,
          label: AppStrings.t(AppStringKeys.linkHandlerTelegramStarsCount, {
            'value1': option.int64('star_count') ?? 0,
          }),
        ),
  ]..sort((a, b) => a.starCount.compareTo(b.starCount));
  if (!nav.mounted) return;
  final product = await nav.push<TelegramStoreProduct>(
    MaterialPageRoute(
      builder: (_) => TelegramStoreProductPickerView(
        title: AppStrings.t(AppStringKeys.linkHandlerBuyTelegramStars),
        subtitle: requested <= 0
            ? AppStrings.t(AppStringKeys.linkHandlerStarsPickerSubtitleAny)
            : purposeLabel.isEmpty
            ? AppStrings.t(AppStringKeys.linkHandlerStarsPickerSubtitleValue1, {
                'value1': requested,
              })
            : AppStrings.t(
                AppStringKeys
                    .linkHandlerStarsPickerSubtitleWithPurposeValue1Value2,
                {'value1': requested, 'value2': purposeLabel},
              ),
        products: products,
        requestedStarCount: requested,
      ),
    ),
  );
  if (product == null || !context.mounted) return;
  final service = TelegramStorePurchaseService();
  if (!await service.isSupported()) {
    if (nav.mounted) {
      await _showStoreDependency(
        nav,
        title: AppStrings.t(AppStringKeys.linkHandlerStarsPurchaseUnavailable),
        operation: AppStrings.t(
          AppStringKeys.linkHandlerOperationStarsPurchase,
        ),
      );
    }
    return;
  }
  final storePurpose = TelegramStorePurchaseService.starsPurpose(
    currency: product.currency,
    amount: product.amount,
    starCount: product.starCount,
  );
  if (!await _preflightStorePurchase(
    nav,
    service: service,
    purpose: storePurpose,
    title: AppStrings.t(AppStringKeys.linkHandlerStarsPurchaseUnavailable),
    operation: AppStrings.t(AppStringKeys.linkHandlerOperationStarsPurchase),
  )) {
    return;
  }
  if (!context.mounted) return;
  final confirmed = await showAppConfirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.linkHandlerConfirmStarsPurchase),
    message: AppStrings.t(AppStringKeys.linkHandlerConfirmStarsMessageValue1, {
      'value1': product.starCount,
    }),
    confirmText: AppStrings.t(AppStringKeys.confirmContinue),
  );
  if (!confirmed || !nav.mounted) return;
  await nav.push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => TelegramStorePurchaseProgressView(
        title: AppStrings.t(AppStringKeys.linkHandlerBuyTelegramStars),
        subtitle: AppStrings.t(AppStringKeys.linkHandlerStarsCountValue1, {
          'value1': product.starCount,
        }),
        purchase: () => service.purchaseAndAssign(
          productId: product.productId,
          purpose: storePurpose,
        ),
      ),
    ),
  );
}

Future<void> _showStoreDependency(
  NavigatorState nav, {
  required String title,
  required String operation,
  String serverError = '',
}) => nav.push(
  MaterialPageRoute<void>(
    builder: (_) => TelegramLinkDetailsView(
      title: title,
      icon: HeroAppIcons.triangleExclamation,
      subtitle: AppStrings.t(
        AppStringKeys.linkHandlerStoreDependencySubtitleValue1,
        {'value1': operation},
      ),
      details: [
        TelegramLinkDetail(
          AppStrings.t(AppStringKeys.linkHandlerDetailChargeState),
          AppStrings.t(AppStringKeys.linkHandlerNoStoreChargeStarted),
        ),
        TelegramLinkDetail(
          AppStrings.t(AppStringKeys.linkHandlerDetailAuthorization),
          'Telegram canPurchaseFromStore required',
        ),
        const TelegramLinkDetail('iOS', 'StoreKit 2 receipt assignment'),
        const TelegramLinkDetail(
          'Android',
          'Google Play Billing adapter required',
        ),
        if (serverError.isNotEmpty)
          TelegramLinkDetail(
            AppStrings.t(AppStringKeys.linkHandlerDetailTelegramResponse),
            serverError,
          ),
      ],
    ),
  ),
);

Future<bool> _preflightStorePurchase(
  NavigatorState nav, {
  required TelegramStorePurchaseService service,
  required Map<String, dynamic> purpose,
  required String title,
  required String operation,
}) async {
  try {
    await service.checkCanPurchase(purpose);
    return true;
  } catch (error) {
    if (nav.mounted) {
      await _showStoreDependency(
        nav,
        title: title,
        operation: operation,
        serverError: error is TdError ? error.message : '',
      );
    }
    return false;
  }
}

String _premiumGiftLabel(int months) => switch (months) {
  1 => '1 month of Telegram Premium',
  _ => '$months months of Telegram Premium',
};

Future<void> _openVideoChat(
  BuildContext context,
  Map<String, dynamic> type,
) async {
  final username = type.str('chat_username') ?? '';
  if (username.isEmpty) return;
  final chat = await TdClient.shared.query({
    '@type': 'searchPublicChat',
    'username': username,
  });
  final chatId = chat.int64('id');
  if (chatId == null || !context.mounted) return;
  await context.read<CallManager>().startGroupCall(
    chatId: chatId,
    title: chat.str('title') ?? username,
    isVideo: true,
    inviteHash: type.str('invite_hash') ?? '',
  );
}

Future<void> _openUnboundGroupCall(
  NavigatorState nav,
  String inviteLink,
) async {
  if (inviteLink.trim().isEmpty) return;
  final participants = await TdClient.shared.query({
    '@type': 'getGroupCallParticipants',
    'input_group_call': {
      '@type': 'inputGroupCallLink',
      'link': inviteLink.trim(),
    },
    'limit': 100,
  });
  if (!nav.mounted) return;
  final count = participants.integer('total_count') ?? 0;
  unawaited(
    nav.push(
      MaterialPageRoute(
        builder: (_) => TelegramLinkDetailsView(
          title: AppStrings.t(AppStringKeys.privacyCalls),
          icon: HeroAppIcons.phone,
          subtitle: AppStrings.t(AppStringKeys.linkHandlerCallSubtitle),
          details: [
            TelegramLinkDetail(
              AppStrings.t(AppStringKeys.linkHandlerDetailParticipants),
              '$count',
            ),
          ],
          trailing: Builder(
            builder: (pageContext) => Semantics(
              button: true,
              label: AppStrings.t(AppStringKeys.linkHandlerJoinCall),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () async {
                  try {
                    await pageContext.read<CallManager>().joinUnboundGroupCall(
                      inviteLink: inviteLink,
                      title: AppStrings.t(AppStringKeys.privacyCalls),
                    );
                    if (pageContext.mounted) Navigator.of(pageContext).pop();
                  } catch (error) {
                    if (pageContext.mounted) {
                      showToast(pageContext, error.toString());
                    }
                  }
                },
                child: Container(
                  width: double.infinity,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: Text(
                    AppStrings.t(AppStringKeys.linkHandlerJoinCall),
                    style: const TextStyle(
                      color: Color(0xFFFFFFFF),
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openGiftCollection(
  NavigatorState nav,
  Map<String, dynamic> type,
) async {
  final username = type.str('gift_owner_username') ?? '';
  final collectionId = type.integer('collection_id');
  if (username.isEmpty || collectionId == null) return;
  final chat = await TdClient.shared.query({
    '@type': 'searchPublicChat',
    'username': username,
  });
  final chatId = chat.int64('id');
  if (chatId == null) return;
  final chatType = chat.obj('type');
  final ownerId = chatType?.type == 'chatTypePrivate'
      ? <String, dynamic>{
          '@type': 'messageSenderUser',
          'user_id': chatType?.int64('user_id'),
        }
      : <String, dynamic>{'@type': 'messageSenderChat', 'chat_id': chatId};
  final result = await TdClient.shared.query({
    '@type': 'getReceivedGifts',
    'business_connection_id': '',
    'owner_id': ownerId,
    'collection_id': collectionId,
    'exclude_unsaved': false,
    'exclude_saved': false,
    'exclude_unlimited': false,
    'exclude_upgradable': false,
    'exclude_non_upgradable': false,
    'exclude_upgraded': false,
    'exclude_without_colors': false,
    'exclude_hosted': false,
    'sort_by_price': false,
    'offset': '',
    'limit': 100,
  });
  final gifts = result.objects('gifts') ?? const <Map<String, dynamic>>[];
  if (!nav.mounted) return;
  unawaited(
    nav.push(
      MaterialPageRoute(
        builder: (_) => TelegramLinkDetailsView(
          title: AppStrings.t(AppStringKeys.profileDetailGifts),
          icon: HeroAppIcons.solidStar,
          subtitle: chat.str('title') ?? username,
          details: [
            TelegramLinkDetail(
              AppStrings.t(AppStringKeys.linkHandlerDetailCollection),
              '#$collectionId',
            ),
            TelegramLinkDetail(
              AppStrings.t(AppStringKeys.linkHandlerDetailGifts),
              '${result.integer('total_count') ?? gifts.length}',
            ),
            for (var index = 0; index < gifts.length; index++)
              TelegramLinkDetail(
                AppStrings.t(AppStringKeys.linkHandlerDetailGiftValue1, {
                  'value1': index + 1,
                }),
                _giftLabel(gifts[index]),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _openUpgradedGift(NavigatorState nav, String name) async {
  if (name.trim().isEmpty) return;
  final gift = await TdClient.shared.query({
    '@type': 'getUpgradedGift',
    'name': name.trim(),
  });
  if (!nav.mounted) return;
  final valueCurrency = gift.str('value_currency') ?? '';
  final valueAmount = gift.int64('value_amount') ?? 0;
  unawaited(
    nav.push(
      MaterialPageRoute(
        builder: (_) => TelegramLinkDetailsView(
          title:
              gift.str('title') ??
              AppStrings.t(AppStringKeys.profileDetailGifts),
          icon: HeroAppIcons.solidStar,
          subtitle: '#${gift.integer('number') ?? 0}',
          details: [
            TelegramLinkDetail(
              AppStrings.t(AppStringKeys.linkHandlerDetailModel),
              gift.obj('model')?.str('name') ?? '',
            ),
            TelegramLinkDetail(
              AppStrings.t(AppStringKeys.linkHandlerDetailSymbol),
              gift.obj('symbol')?.str('name') ?? '',
            ),
            TelegramLinkDetail(
              AppStrings.t(AppStringKeys.linkHandlerDetailBackdrop),
              gift.obj('backdrop')?.str('name') ?? '',
            ),
            if (valueCurrency.isNotEmpty && valueAmount > 0)
              TelegramLinkDetail(
                AppStrings.t(AppStringKeys.linkHandlerDetailEstimatedValue),
                _formatCurrency(valueCurrency, valueAmount),
              ),
          ],
        ),
      ),
    ),
  );
}

Future<void> _openGiftAuction(NavigatorState nav, String auctionId) async {
  if (auctionId.trim().isEmpty) return;
  final result = await TdClient.shared.query({
    '@type': 'getGiftAuctionState',
    'auction_id': auctionId.trim(),
  });
  if (!nav.mounted) return;
  final gift = result.obj('gift');
  final state = result.obj('state');
  await nav.push(
    MaterialPageRoute<void>(
      builder: (_) => TelegramLinkDetailsView(
        title: AppStrings.t(AppStringKeys.linkHandlerGiftAuction),
        icon: HeroAppIcons.solidStar,
        subtitle: auctionId,
        details: [
          TelegramLinkDetail(
            AppStrings.t(AppStringKeys.linkHandlerDetailGift),
            gift?.str('title') ?? gift?.type ?? '—',
          ),
          TelegramLinkDetail(
            AppStrings.t(AppStringKeys.linkHandlerDetailStatus),
            (state?.type ?? 'unknown').replaceFirst('auctionState', ''),
          ),
          if ((state?.int64('minimum_bid_star_count') ?? 0) > 0)
            TelegramLinkDetail(
              AppStrings.t(AppStringKeys.linkHandlerDetailMinimumBid),
              '⭐ ${state?.int64('minimum_bid_star_count')}',
            ),
        ],
      ),
    ),
  );
}

Future<void> _applyPremiumGiftCode(BuildContext context, String code) async {
  if (code.trim().isEmpty) return;
  final info = await TdClient.shared.query({
    '@type': 'checkPremiumGiftCode',
    'code': code.trim(),
  });
  if (!context.mounted) return;
  final months = info.integer('month_count') ?? 0;
  final days = info.integer('day_count') ?? 0;
  final accepted = await showAppConfirmDialog(
    context,
    title: AppStrings.t(AppStringKeys.linkHandlerTelegramPremiumGift),
    message: months > 0
        ? '$months month${months == 1 ? '' : 's'}'
        : '$days day${days == 1 ? '' : 's'}',
    confirmText: AppStrings.t(AppStringKeys.confirmContinue),
  );
  if (!accepted) return;
  await TdClient.shared.query({
    '@type': 'applyPremiumGiftCode',
    'code': code.trim(),
  });
}

Future<void> _addTextCompositionStyle(BuildContext context, String name) async {
  if (name.trim().isEmpty) return;
  final service = TelegramAiService();
  try {
    final style = await service.searchStyle(name.trim());
    if (!context.mounted) return;
    final accepted = await showAppConfirmDialog(
      context,
      title: style.title.isEmpty
          ? AppStrings.t(AppStringKeys.linkHandlerWritingStyle)
          : style.title,
      message: style.prompt,
      confirmText: AppStrings.t(AppStringKeys.confirmContinue),
    );
    if (accepted) await service.addStyle(style.name, style: style);
  } finally {
    service.dispose();
  }
}

String _giftLabel(Map<String, dynamic> received) {
  final sent = received.obj('gift');
  final gift = sent?.obj('gift');
  if (sent?.type == 'sentGiftUpgraded') {
    final title = gift?.str('title') ?? '';
    final number = gift?.integer('number') ?? 0;
    if (title.isNotEmpty) return '$title #$number';
  }
  final stars = gift?.int64('star_count') ?? 0;
  return stars > 0 ? '⭐ $stars' : AppStrings.t(AppStringKeys.tdMessageGift);
}

String _formatCurrency(String currency, int amount) {
  const zeroDecimal = {
    'BIF',
    'CLP',
    'DJF',
    'GNF',
    'ISK',
    'JPY',
    'KRW',
    'PYG',
    'RWF',
    'UGX',
    'VND',
    'VUV',
    'XAF',
    'XOF',
    'XPF',
  };
  const threeDecimal = {'BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND'};
  final decimals = zeroDecimal.contains(currency)
      ? 0
      : threeDecimal.contains(currency)
      ? 3
      : 2;
  if (decimals == 0) return '$currency $amount';
  final negative = amount < 0;
  final absolute = amount.abs().toString().padLeft(decimals + 1, '0');
  final split = absolute.length - decimals;
  return '$currency ${negative ? '-' : ''}${absolute.substring(0, split)}.${absolute.substring(split)}';
}

Future<void> _confirmQrAuthentication(BuildContext context, String link) async {
  final ok = await showAppConfirmDialog(
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

Future<void> _showDeepLinkInfoOrExternal(
  BuildContext context,
  String link,
) async {
  try {
    await TdClient.shared.query({'@type': 'getDeepLinkInfo', 'link': link});
  } catch (_) {}
  if (context.mounted) await _openBrowserLink(context, link);
}

Future<bool> _openPrivateMessageLink(
  NavigatorState nav,
  List<String> segments, {
  required int? messageId,
  InternalChatLinkTarget? sourceChat,
  _TdLinkQuery? query,
}) async {
  if (segments.length < 3) return false;
  final internalId = int.tryParse(segments[1]);
  if (internalId == null) return false;
  final chatId = int.tryParse('-100$internalId');
  if (chatId == null) return false;
  await _openChat(
    nav,
    chatId,
    initialMessageId: messageId,
    sourceChat: sourceChat,
    query: query,
  );
  return true;
}

bool _isPublicUsername(String value) =>
    RegExp(r'^[A-Za-z0-9_]{3,32}$').hasMatch(value);

Future<void> _openChat(
  NavigatorState nav,
  int? chatId, {
  int? initialMessageId,
  InternalChatLinkTarget? sourceChat,
  _TdLinkQuery? query,
}) async {
  if (chatId == null) return;
  if (sourceChat?.chatId == chatId &&
      initialMessageId != null &&
      initialMessageId > 0) {
    await routeResolvedInternalChatLink(
      chatId: chatId,
      title: '',
      messageId: initialMessageId,
      source: sourceChat,
    );
    return;
  }
  var title = '';
  try {
    final chat = await (query ?? TdClient.shared.query)({
      '@type': 'getChat',
      'chat_id': chatId,
    });
    title = chat.str('title') ?? '';
  } catch (_) {}
  if (!nav.mounted) return;
  if (await handoffChatToPrimaryWindow(
    chatId: chatId,
    title: title,
    initialMessageId: initialMessageId,
  )) {
    return;
  }
  await routeResolvedInternalChatLink(
    chatId: chatId,
    title: title,
    messageId: initialMessageId,
    source: sourceChat,
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
  final ok = await showAppConfirmDialog(
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
  final ok = await showAppConfirmDialog(
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

Future<void> _launchExternal(String url) async {
  final uri = parseLinkUri(url);
  if (uri == null) return;
  await launchInDefaultBrowser(uri);
}

Future<void> _openBrowserLink(
  BuildContext context,
  String url, {
  LinkOpenTarget? target,
}) async {
  final uri = parseLinkUri(url);
  if (uri == null) return;
  final platform = Theme.of(context).platform;
  final theme = Provider.of<ThemeController?>(context, listen: false);
  target ??= linkOpenTargetFor(
    mode: theme?.linkOpenMode ?? LinkOpenMode.defaultBrowser,
    uri: uri,
    platform: platform,
  );
  if (target == null) {
    if (!context.mounted) return;
    target = await showLinkBrowserChooser(context);
  }
  if (target == null || !context.mounted) return;

  switch (target) {
    case LinkOpenTarget.internalBrowser:
      if (!internalBrowserCanOpen(uri) ||
          !internalBrowserSupported(platform: platform)) {
        await launchInDefaultBrowser(uri);
        return;
      }
      await Navigator.of(context).push<void>(
        AppPageRoute<void>(
          pageBuilder: (browserContext, _, _) => InternalBrowserView(
            initialUri: uri,
            onOpenInApp: (link) => openLink(browserContext, link),
          ),
        ),
      );
    case LinkOpenTarget.defaultBrowser:
      await launchInDefaultBrowser(uri);
  }
}
