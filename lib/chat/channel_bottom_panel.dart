//
//  channel_bottom_panel.dart
//
//  The bottom panel of a channel you subscribe to but cannot post in. The
//  stock client only offers mute/unmute there; Mithka lets the panel carry
//  the channel's discussion group and direct messages instead, or stay
//  hidden entirely — the reference client's "channel bottom button" trio.
//

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

/// The actions a channel bottom panel can offer besides mute/unmute.
enum ChannelBottomPanelAction { discussion, directMessages }

/// Which actions the panel can open for this channel, in display order.
///
/// A channel with neither a discussion group nor a direct-messages group
/// yields an empty list: its panel then shows nothing at all.
List<ChannelBottomPanelAction> channelBottomPanelActions({
  required bool hasDiscussion,
  required bool hasDirectMessages,
}) => [
  if (hasDiscussion) ChannelBottomPanelAction.discussion,
  if (hasDirectMessages) ChannelBottomPanelAction.directMessages,
];

/// Renders the channel bottom panel for [mode].
///
/// * [ChannelBottomBarMode.mute] — the stock mute/unmute bar.
/// * [ChannelBottomBarMode.actions] — one button per available action, or
///   nothing when the channel has neither.
/// * [ChannelBottomBarMode.hidden] — nothing.
class ChannelBottomPanel extends StatelessWidget {
  const ChannelBottomPanel({
    super.key,
    required this.mode,
    required this.muted,
    required this.hasDiscussion,
    required this.hasDirectMessages,
    required this.onToggleMute,
    required this.onOpenDiscussion,
    required this.onOpenDirectMessages,
  });

  final ChannelBottomBarMode mode;
  final bool muted;
  final bool hasDiscussion;
  final bool hasDirectMessages;
  final VoidCallback onToggleMute;
  final VoidCallback onOpenDiscussion;
  final VoidCallback onOpenDirectMessages;

  static const muteKey = ValueKey('channelBottomPanel-mute');
  static const emptyKey = ValueKey('channelBottomPanel-empty');
  static const discussionKey = ValueKey('channelBottomPanel-discussion');
  static const directMessagesKey = ValueKey(
    'channelBottomPanel-directMessages',
  );

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    switch (mode) {
      case ChannelBottomBarMode.hidden:
        return const SizedBox.shrink();
      case ChannelBottomBarMode.mute:
        return _bar(
          context,
          key: muteKey,
          bottomInset: bottomInset,
          child: _button(
            context,
            icon: HeroAppIcons.solidBell,
            label: (muted ? AppStringKeys.chatUnmute : AppStringKeys.callMute)
                .l10n(context),
            onTap: onToggleMute,
          ),
        );
      case ChannelBottomBarMode.actions:
        final actions = channelBottomPanelActions(
          hasDiscussion: hasDiscussion,
          hasDirectMessages: hasDirectMessages,
        );
        if (actions.isEmpty) return const SizedBox(key: emptyKey);
        final c = context.colors;
        return _bar(
          context,
          bottomInset: bottomInset,
          child: Row(
            children: [
              for (var i = 0; i < actions.length; i++) ...[
                if (i > 0) Container(width: 0.5, height: 22, color: c.divider),
                Expanded(
                  child: switch (actions[i]) {
                    ChannelBottomPanelAction.discussion => _button(
                      context,
                      key: discussionKey,
                      icon: HeroAppIcons.comments,
                      label: AppStringKeys.channelPanelDiscussion.l10n(context),
                      onTap: onOpenDiscussion,
                    ),
                    ChannelBottomPanelAction.directMessages => _button(
                      context,
                      key: directMessagesKey,
                      icon: HeroAppIcons.paperPlane,
                      label: AppStringKeys.channelPanelDirect.l10n(context),
                      onTap: onOpenDirectMessages,
                    ),
                  },
                ),
              ],
            ],
          ),
        );
    }
  }

  Widget _bar(
    BuildContext context, {
    Key? key,
    required double bottomInset,
    required Widget child,
  }) {
    final c = context.colors;
    return Container(
      key: key ?? const ValueKey('channelBottomPanel'),
      width: double.infinity,
      padding: EdgeInsets.only(bottom: bottomInset),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: child,
    );
  }

  Widget _button(
    BuildContext context, {
    Key? key,
    required AppIconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return AppInteractiveSurface(
      key: key,
      onTap: onTap,
      semanticLabel: label,
      // The whole bar is the target: in the stock mode this is the only
      // button, and a tap anywhere on it must toggle mute.
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(icon, size: 18, color: AppTheme.brand),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 16, color: AppTheme.brand),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
