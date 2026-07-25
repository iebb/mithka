import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/chat_view.dart';
import '../chat/link_handler.dart';
import '../chat/message_bubble_repository_view.dart';
import '../chat/stretchable_message_bubble_background.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../theme/app_theme.dart';
import '../theme/custom_message_bubble_background.dart';
import '../theme/message_bubble_background.dart';
import '../theme/theme_controller.dart';

typedef CustomMessageBubblePngPicker = Future<Uint8List?> Function();

class MessageBubbleSettingsView extends StatefulWidget {
  const MessageBubbleSettingsView({
    super.key,
    this.importer,
    this.pickCustomPng,
  });

  // Retained for source compatibility with embedders while the public channel
  // replaces the old local file picker.
  final CustomMessageBubbleImporter? importer;
  final CustomMessageBubblePngPicker? pickCustomPng;

  @override
  State<MessageBubbleSettingsView> createState() =>
      _MessageBubbleSettingsViewState();
}

class _MessageBubbleSettingsViewState extends State<MessageBubbleSettingsView> {
  bool _opening = false;

  Future<void> _openRepository() async {
    if (_opening) return;
    setState(() => _opening = true);
    try {
      final chat = await TdClient.shared.query({
        '@type': 'searchPublicChat',
        'username': messageBubbleRepositoryUsername,
      });
      final chatId = chat.int64('id');
      if (chatId == null || chatId == 0) throw StateError('Channel not found');
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatView(
            chatId: chatId,
            title: chat.str('title') ?? 'Message bubbles',
          ),
        ),
      );
    } catch (_) {
      if (mounted) showToast(context, 'Could not open @msgbubble.');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final custom = theme.customMessageBubbleBackground;
    final sourceLink =
        custom?.sourceMessageLink ??
        theme.messageBubbleBackground.repositoryLink;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceMessageBubbles),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 28),
              children: [
                _preview(context, theme.messageBubbleBackgroundSpec),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: c.divider, width: 0.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SettingsIconTile(
                            icon: HeroAppIcons.palette,
                            backgroundColor: AppTheme.brand,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '@msgbubble repository',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Browse the public channel as a bubble grid. Repository PNGs are exactly 160 × 120 px and contain four fixed text-color swatches.',
                        style: TextStyle(
                          color: c.textSecondary,
                          fontSize: 13.5,
                          height: 1.4,
                        ),
                      ),
                      if (sourceLink != null) ...[
                        const SizedBox(height: 10),
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => openLink(context, sourceLink),
                          child: Text(
                            sourceLink,
                            style: TextStyle(
                              color: AppTheme.brand,
                              fontSize: 13,
                              decoration: TextDecoration.underline,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 15),
                      GestureDetector(
                        key: const ValueKey('messageBubbleOpenRepository'),
                        behavior: HitTestBehavior.opaque,
                        onTap: _opening ? null : _openRepository,
                        child: Container(
                          height: 46,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.brand,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: _opening
                              ? SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppTheme.onBrand,
                                  ),
                                )
                              : Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppIcon(
                                      HeroAppIcons.share,
                                      size: 17,
                                      color: AppTheme.onBrand,
                                    ),
                                    const SizedBox(width: 7),
                                    Text(
                                      'Open bubble repository',
                                      style: TextStyle(
                                        color: AppTheme.onBrand,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(
    BuildContext context,
    MessageBubbleBackgroundSpec background,
  ) {
    final c = context.colors;
    return Container(
      height: 220,
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 20),
      decoration: BoxDecoration(
        color: c.chatBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.divider.withValues(alpha: 0.7)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PhotoAvatar(title: 'M', size: 34),
              const SizedBox(width: 8),
              Flexible(
                child: _previewBubble(
                  context,
                  background: background,
                  outgoing: false,
                  text: 'Repository bubble preview',
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: _previewBubble(
              context,
              background: background,
              outgoing: true,
              text: 'The center stretches with longer messages.',
            ),
          ),
        ],
      ),
    );
  }

  Widget _previewBubble(
    BuildContext context, {
    required MessageBubbleBackgroundSpec background,
    required bool outgoing,
    required String text,
  }) {
    final c = context.colors;
    return StretchableMessageBubbleBackground(
      background: background,
      constraints: const BoxConstraints(maxWidth: 250),
      fallbackColor: outgoing ? AppTheme.bubbleOutgoing : c.bubbleIncoming,
      fallbackBorderRadius: BorderRadius.circular(12),
      fallbackBorder: outgoing
          ? null
          : Border.all(color: c.divider, width: 0.5),
      fallbackPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Text(
        text,
        style: TextStyle(
          color:
              background.foregroundColor ??
              (outgoing ? AppTheme.bubbleOutgoingText : c.bubbleIncomingText),
          fontSize: 15,
          height: 1.25,
        ),
      ),
    );
  }
}
