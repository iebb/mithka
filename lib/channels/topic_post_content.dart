import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../app/primary_chat_launcher.dart';
import '../chat/bot_button_presentation.dart';
import '../chat/chat_picker_view.dart';
import '../chat/file_detail_view.dart';
import '../chat/link_handler.dart';
import '../chat/telegram_rich_text.dart';
import '../components/app_icons.dart';
import '../components/document_file_icon.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../profile/adaptive_profile_launcher.dart';
import '../tdlib/display_text.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../tdlib/td_requests.dart';
import '../theme/app_theme.dart';

class TopicPostContent extends StatelessWidget {
  const TopicPostContent({
    super.key,
    required this.chatId,
    required this.message,
    required this.text,
    required this.textStyle,
    this.maxTextLines,
    this.textOverflow = TextOverflow.clip,
    this.imageReactions,
    this.onOpenCurrentChat,
  });

  final int chatId;
  final ChatMessage message;
  final String text;
  final TextStyle textStyle;
  final int? maxTextLines;
  final TextOverflow textOverflow;
  final Widget? imageReactions;
  final VoidCallback? onOpenCurrentChat;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    // The post text and the file caption arrive trimmed; re-address their
    // entities to the displayed string so formatting stays on its characters.
    final body = trimTextForDisplay(text, message.textEntities);
    final documentCaption = message.document == null ? '' : body.text;
    if (body.text.isNotEmpty && message.document == null) {
      children.add(
        TelegramRichText(
          text: body.text,
          entities: body.entities,
          maxLines: maxTextLines,
          overflow: textOverflow,
          style: textStyle,
          onMentionTap: (userId, name) {
            unawaited(
              openAdaptiveUserProfile(context, userId: userId, name: name),
            );
          },
        ),
      );
    }
    if (message.image != null) {
      children.add(_TopicContentImage(message: message));
      final reactions = imageReactions;
      if (reactions != null) children.add(reactions);
    }
    if (message.document != null) {
      children.add(
        _TopicFileCard(
          chatId: chatId,
          messageId: message.id,
          document: message.document!,
          caption: documentCaption,
          captionEntities: body.entities,
          captionStyle: textStyle.copyWith(
            fontSize: (textStyle.fontSize ?? 15) * (14 / 15),
            decoration: TextDecoration.none,
          ),
        ),
      );
    }
    if (message.buttonRows.isNotEmpty) {
      children.add(
        _TopicButtonRows(
          chatId: chatId,
          message: message,
          onOpenCurrentChat: onOpenCurrentChat,
        ),
      );
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          children[i],
        ],
      ],
    );
  }
}

class _TopicContentImage extends StatelessWidget {
  const _TopicContentImage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width - 28;
    final height = _imageHeight(width);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: width,
        height: height,
        child: TDImage(
          photo: message.image,
          cornerRadius: 6,
          cacheWidth: (width * MediaQuery.devicePixelRatioOf(context)).round(),
          cacheHeight: (height * MediaQuery.devicePixelRatioOf(context))
              .round(),
        ),
      ),
    );
  }

  double _imageHeight(double width) {
    final w = message.imageWidth;
    final h = message.imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return width * 0.62;
    final ratio = (h / w).clamp(0.45, 1.25);
    return width * ratio;
  }
}

class _TopicFileCard extends StatelessWidget {
  const _TopicFileCard({
    required this.chatId,
    required this.messageId,
    required this.document,
    required this.caption,
    required this.captionEntities,
    required this.captionStyle,
  });

  final MessageDocument document;
  final int chatId;
  final int messageId;
  final String caption;
  final List<MessageTextEntity> captionEntities;
  final TextStyle captionStyle;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => FileDetailView(
            doc: document,
            chatId: chatId,
            messageId: messageId,
          ),
        ),
      ),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        document.fileName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, color: c.textPrimary),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _byteString(document.size),
                        style: TextStyle(fontSize: 12, color: c.textSecondary),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                DocumentFileIcon(
                  fileName: document.fileName,
                  extension: document.ext,
                ),
              ],
            ),
            if (caption.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(height: 0.5, color: c.divider),
              const SizedBox(height: 8),
              TelegramRichText(
                text: caption,
                entities: captionEntities,
                style: captionStyle,
                onMentionTap: (userId, name) {
                  unawaited(
                    openAdaptiveUserProfile(
                      context,
                      userId: userId,
                      name: name,
                    ),
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _byteString(int bytes) {
    if (bytes <= 0) {
      return AppStrings.t(AppStringKeys.topicPostContentFile);
    }
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final number = value >= 10 || unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$number ${units[unit]}';
  }
}

class _TopicButtonRows extends StatelessWidget {
  const _TopicButtonRows({
    required this.chatId,
    required this.message,
    this.onOpenCurrentChat,
  });

  final int chatId;
  final ChatMessage message;
  final VoidCallback? onOpenCurrentChat;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        for (final row in message.buttonRows) ...[
          Row(
            children: [
              for (var i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _pressButton(context, row[i]),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 38),
                      decoration: BoxDecoration(
                        color: c.searchFill,
                        borderRadius: BorderRadius.circular(AppRadius.control),
                        border: Border.all(color: c.divider, width: 0.5),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: botButtonBadgeIcon(row[i]) != null
                                  ? 18
                                  : 10,
                              vertical: 8,
                            ),
                            child: BotButtonLabel(
                              button: row[i],
                              color: c.linkBlue,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (botButtonBadgeIcon(row[i]) case final badgeIcon?)
                            Positioned(
                              top: 4,
                              right: 5,
                              child: AppIcon(
                                badgeIcon,
                                size: 11,
                                color: c.linkBlue.withValues(alpha: 0.72),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (row != message.buttonRows.last) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Future<void> _pressButton(BuildContext context, MessageButton button) async {
    final url = button.url;
    if (url != null && url.isNotEmpty) {
      await openLink(context, url);
      return;
    }
    final userId = button.userId;
    if (userId != null && userId > 0) {
      await openLink(context, 'tg://user?id=$userId');
      return;
    }
    final copyText = button.copyText;
    if (copyText != null && copyText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: copyText));
      if (context.mounted) {
        showToast(context, AppStrings.t(AppStringKeys.topicPostContentCopied));
      }
      return;
    }
    if (button.isCallback) {
      try {
        final answer = await TdClient.shared.query({
          '@type': 'getCallbackQueryAnswer',
          'chat_id': chatId,
          'message_id': message.id,
          'payload': {
            '@type': 'callbackQueryPayloadData',
            'data': button.data ?? '',
          },
        });
        if (!context.mounted) return;
        final answerUrl = answer.str('url');
        if (answerUrl != null && answerUrl.isNotEmpty) {
          await openLink(context, answerUrl);
          return;
        }
        final text = answer.str('text');
        if (text != null && text.isNotEmpty) showToast(context, text);
      } catch (_) {
        if (context.mounted) {
          showToast(
            context,
            AppStrings.t(AppStringKeys.topicPostContentActionFailed),
          );
        }
      }
      return;
    }
    if (button.isSwitchInline) {
      await _activateSwitchInline(context, button);
      return;
    }
  }

  Future<void> _activateSwitchInline(
    BuildContext context,
    MessageButton button,
  ) async {
    final query = button.switchInlineQuery ?? '';
    final target =
        button.switchInlineTarget ?? const SwitchInlineTarget.chooseChat();
    // Chat ids and draft writes are account-scoped, and this transcript can
    // outlive the tap: capture the owning account and treat a disposed element
    // or a switched active account as the end of the flow, checked after every
    // await so a late response can never write into a topic view the user
    // already left (or into the replacement account's ids).
    final accountSlot = TdClient.shared.activeSlot;
    final accountClientId = TdClient.shared.activeClientId;
    // Account-only half of the staleness guard: the mounted half stays inline
    // at each call site so the analyzer can see it guard every context use.
    bool accountChanged() =>
        TdClient.shared.activeSlot != accountSlot ||
        TdClient.shared.activeClientId != accountClientId;
    Future<Map<String, dynamic>> queryOwned(Map<String, dynamic> request) =>
        TdClient.shared.queryForSlot(request, accountSlot);
    final username = await _resolveBotUsername(accountSlot);
    if (!context.mounted || accountChanged()) return;
    if (target.kind == SwitchInlineTargetKind.internalLink &&
        target.internalLink != null) {
      final link = Map<String, dynamic>.from(target.internalLink!);
      if (username != null &&
          username.isNotEmpty &&
          link.type == 'internalLinkTypePublicChat' &&
          (link.str('draft_text') ?? '').trim().isEmpty) {
        link['draft_text'] = '@$username $query';
      }
      await openInternalLinkType(context, link);
      return;
    }
    if (username != null && username.isNotEmpty) {
      if (target.isCurrentChat) {
        var currentTitle = '';
        var canSend = true;
        try {
          final chat = await queryOwned({
            '@type': 'getChat',
            'chat_id': chatId,
          });
          if (!context.mounted || accountChanged()) return;
          currentTitle = chat.str('title') ?? '';
          canSend =
              chat.obj('permissions')?.boolean('can_send_basic_messages') ??
              true;
          final type = chat.obj('type');
          if (type?.type == 'chatTypeSupergroup' &&
              (type?.boolean('is_channel') ?? false)) {
            final sgId = type?.int64('supergroup_id');
            if (sgId != null && sgId != 0) {
              final sg = await queryOwned({
                '@type': 'getSupergroup',
                'supergroup_id': sgId,
              });
              if (!context.mounted || accountChanged()) return;
              final status = sg.obj('status');
              final statusType = status?.type;
              if (statusType != 'chatMemberStatusCreator' &&
                  statusType != 'chatMemberStatusAdministrator') {
                canSend = false;
              } else if (statusType == 'chatMemberStatusAdministrator') {
                final rights = status?.obj('rights');
                canSend = rights?.boolean('can_post_messages') ?? false;
              }
            }
          }
        } catch (_) {
          if (!context.mounted || accountChanged()) return;
        }
        if (canSend) {
          // Re-check immediately before the write: permission lookups can
          // resolve long after the tap, and the mounted check below used to be
          // the first guard after the draft had already been sent.
          if (!context.mounted || accountChanged()) return;
          final forumTopicId = message.forumTopicId;
          try {
            await queryOwned(
              setTextChatDraftRequest(
                chatId: chatId,
                topicId: forumTopicId != null && forumTopicId > 0
                    ? {
                        '@type': 'messageTopicForum',
                        'forum_topic_id': forumTopicId,
                      }
                    : null,
                date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
                formattedText: {
                  '@type': 'formattedText',
                  'text': '@$username $query',
                  'entities': const <Map<String, dynamic>>[],
                },
              ),
            );
          } catch (_) {}
          if (!context.mounted || accountChanged()) return;
          if (onOpenCurrentChat != null) {
            onOpenCurrentChat!();
            return;
          }
          await openChatFromCurrentWindow(
            context,
            chatId: chatId,
            title: currentTitle,
          );
          return;
        }
        // The current chat cannot receive the draft (a channel the viewer
        // cannot post in): current-chat targets must never fall through to
        // the picker — copy the query so it can still be pasted somewhere.
        if (context.mounted && !accountChanged()) {
          if (query.isNotEmpty) {
            await Clipboard.setData(ClipboardData(text: query));
            if (context.mounted && !accountChanged()) {
              showToast(
                context,
                AppStrings.t(AppStringKeys.topicPostContentCopiedQuery),
              );
            }
          }
        }
        return;
      }
      final allowedKinds = target.allowedChatKinds;
      final picked = await Navigator.of(context).push<ChatSummary>(
        MaterialPageRoute(
          builder: (_) => ChatPickerView(
            allowedKinds: allowedKinds,
            allowChannels: allowedKinds.contains(ChatKind.channel),
            // The route is a sibling of this transcript's link scope, so the
            // owning account has to travel with the picker explicitly.
            accountSlot: accountSlot,
          ),
        ),
      );
      if (picked == null || !context.mounted || accountChanged()) return;
      try {
        await queryOwned(
          setTextChatDraftRequest(
            chatId: picked.id,
            date: DateTime.now().millisecondsSinceEpoch ~/ 1000,
            formattedText: {
              '@type': 'formattedText',
              'text': '@$username $query',
              'entities': const <Map<String, dynamic>>[],
            },
          ),
        );
      } catch (_) {}
      if (!context.mounted || accountChanged()) return;
      await openChatFromCurrentWindow(
        context,
        chatId: picked.id,
        title: picked.title,
      );
      return;
    }
    if (query.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: query));
      if (context.mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.topicPostContentCopiedQuery),
        );
      }
    }
  }

  Future<String?> _resolveBotUsername(int accountSlot) async {
    final cachedHandle = message.viaBotUsername?.trim();
    if (cachedHandle != null && cachedHandle.startsWith('@')) {
      final clean = cachedHandle.substring(1).trim();
      if (clean.isNotEmpty) return clean;
    }
    final candidates = <int>[
      if (message.viaBotUserId case final id? when id > 0) id,
      if (message.senderId case final id? when id > 0) id,
      if (message.forwardFromUserId case final id? when id > 0) id,
    ];
    for (final userId in candidates) {
      try {
        // User ids come from this account's message, so the lookup has to stay
        // on it even if the active account changed meanwhile.
        final user = await TdClient.shared.queryForSlot({
          '@type': 'getUser',
          'user_id': userId,
        }, accountSlot);
        if (!TDParse.isBotUser(user)) continue;
        final usernames = user.obj('usernames');
        final active = usernames?['active_usernames'];
        if (active is List) {
          for (final value in active) {
            if (value is String && value.trim().isNotEmpty) {
              return value.trim();
            }
          }
        }
        final editable = usernames?.str('editable_username')?.trim();
        if (editable != null && editable.isNotEmpty) return editable;
      } catch (_) {}
    }
    return null;
  }
}
