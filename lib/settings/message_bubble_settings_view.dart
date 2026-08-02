import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/chat_view.dart';
import '../chat/link_handler.dart';
import '../chat/message_bubble_chat_preview.dart';
import '../chat/message_bubble_repository_view.dart';
import '../components/app_icons.dart';
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
    final brightness = Theme.of(context).brightness;
    final cloudTheme = theme.cloudThemeFor(brightness);
    final incomingBackground = theme.effectiveMessageBubbleBackgroundSpecFor(
      outgoing: false,
    );
    final outgoingBackground = theme.effectiveMessageBubbleBackgroundSpecFor(
      outgoing: true,
    );
    final showIncomingSurface = theme.shouldRenderMessageBubbleSurface(
      outgoing: false,
      brightness: brightness,
    );
    final showOutgoingSurface = theme.shouldRenderMessageBubbleSurface(
      outgoing: true,
      brightness: brightness,
    );
    final showBubbleCustomization =
        theme.messageBubblesEnabled ||
        incomingBackground.isDecorative ||
        outgoingBackground.isDecorative;
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
                Container(
                  decoration: BoxDecoration(
                    color: c.card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.divider, width: 0.5),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: SettingsSwitchRow(
                    key: const ValueKey('message-bubbles-enabled'),
                    title: AppStrings.t(
                      AppStringKeys.appearanceShowMessageBubbles,
                    ),
                    value: theme.messageBubblesEnabled,
                    onChanged: (value) => theme.messageBubblesEnabled = value,
                    leading: SettingsIconTile(
                      icon: HeroAppIcons.message,
                      backgroundColor: AppTheme.brand,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    AppStrings.t(
                      AppStringKeys.appearanceShowMessageBubblesDescription,
                    ),
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 13,
                      height: 1.35,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                MessageBubbleChatPreview(
                  incomingBackground: incomingBackground,
                  outgoingBackground: outgoingBackground,
                  showIncomingSurface: showIncomingSurface,
                  showOutgoingSurface: showOutgoingSurface,
                  incomingSurfaceColor: cloudTheme?.incomingColor,
                  outgoingSurfaceColor: cloudTheme?.outgoingColor,
                  incomingTextColor: cloudTheme?.incomingTextColor,
                  outgoingTextColor: cloudTheme?.outgoingTextColor,
                ),
                if (showBubbleCustomization) ...[
                  const SizedBox(height: 16),
                  _applicationScopeCard(context, theme),
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
                          'Browse the public channel as a bubble grid. Repository images are exactly 360 × 180 px, with a 300 × 120 bubble box and 30 px transparent padding on every side.',
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
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _applicationScopeCard(BuildContext context, ThemeController theme) {
    final c = context.colors;
    Widget choice(String label, MessageBubbleApplicationScope scope) {
      final selected = theme.messageBubbleApplicationScope == scope;
      return GestureDetector(
        key: ValueKey('message-bubble-scope-${scope.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => theme.messageBubbleApplicationScope = scope,
        child: SizedBox(
          height: 48,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(fontSize: 15, color: c.textPrimary),
                  ),
                ),
                AppIcon(
                  selected ? HeroAppIcons.circleCheck : HeroAppIcons.circle,
                  size: 19,
                  color: selected ? AppTheme.brand : c.textTertiary,
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: c.divider, width: 0.5),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 5),
            child: Text(
              'Apply bubble to',
              style: TextStyle(
                color: c.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          choice('My messages only', MessageBubbleApplicationScope.ownMessages),
          Divider(height: 0.5, thickness: 0.5, color: c.divider),
          choice('All messages', MessageBubbleApplicationScope.allMessages),
        ],
      ),
    );
  }
}
