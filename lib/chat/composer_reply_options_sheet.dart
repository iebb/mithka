import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

/// The result of a session with [ComposerReplyOptionsSheet].
sealed class ComposerReplyOptionsResult {
  const ComposerReplyOptionsResult();
}

/// Keep the reply exactly as it is.
class ComposerReplyOptionsApply extends ComposerReplyOptionsResult {
  const ComposerReplyOptionsApply();
}

/// Drop the pending reply (banner close equivalent).
class ComposerReplyOptionsRemove extends ComposerReplyOptionsResult {
  const ComposerReplyOptionsRemove();
}

/// Replace the plain reply with a quoted range of the same message.
class ComposerReplyOptionsQuote extends ComposerReplyOptionsResult {
  const ComposerReplyOptionsQuote(this.quote);

  final MessageTextQuote quote;
}

/// Carry the reply into a different chat ("reply in another chat").
class ComposerReplyOptionsAnotherChat extends ComposerReplyOptionsResult {
  const ComposerReplyOptionsAnotherChat({this.quote});

  final MessageTextQuote? quote;
}

/// Reply options presented from the composer's reply banner: pick a quoted
/// range, move the reply to another chat, or drop it. Mirrors the entry the
/// long-press menu's Quote action opens, so both paths share one behavior.
class ComposerReplyOptionsSheet extends StatelessWidget {
  const ComposerReplyOptionsSheet({
    super.key,
    required this.message,
    required this.canQuote,
    required this.canReplyInAnotherChat,
  });

  final ChatMessage message;

  /// Whether text quoting is offered (target chat permits it).
  final bool canQuote;

  /// Whether the "reply in another chat" entry is offered. The message must
  /// allow it (`messageProperties.can_be_replied_in_another_chat`) and the
  /// current chat must not be a secret chat.
  final bool canReplyInAnotherChat;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 8),
          if (canQuote) ...[
            _ComposerReplyOptionRow(
              key: const ValueKey('composerReplyOptionQuote'),
              icon: HeroAppIcons.quoteLeft,
              label: AppStringKeys.composerReplyOptionQuote.l10n(context),
              onTap: () => Navigator.of(context).pop(const _QuotePick()),
            ),
          ],
          if (canReplyInAnotherChat) ...[
            _ComposerReplyOptionRow(
              key: const ValueKey('composerReplyOptionAnotherChat'),
              icon: HeroAppIcons.forward,
              label: AppStringKeys.composerReplyOptionAnotherChat.l10n(context),
              onTap: () => Navigator.of(context).pop(const _AnotherChatPick()),
            ),
          ],
          _ComposerReplyOptionRow(
            key: const ValueKey('composerReplyOptionCancel'),
            icon: HeroAppIcons.xmark,
            label: AppStringKeys.composerReplyOptionCancel.l10n(context),
            onTap: () =>
                Navigator.of(context).pop(const ComposerReplyOptionsRemove()),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Center(
              child: Text(
                AppStringKeys.composerReplyOptionsHint.l10n(context),
                style: AppTextStyle.body(colors.textTertiary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Internal result signaling "open the quote selection dialog next".
class _QuotePick extends ComposerReplyOptionsResult {
  const _QuotePick();
}

/// Internal result signaling "open the chat picker next".
class _AnotherChatPick extends ComposerReplyOptionsResult {
  const _AnotherChatPick();
}

/// True when the sheet result asks the host to open the quote picker.
bool composerReplyOptionsWantsQuotePick(ComposerReplyOptionsResult result) =>
    result is _QuotePick;

/// True when the sheet result asks the host to open the chat picker.
bool composerReplyOptionsWantsAnotherChat(ComposerReplyOptionsResult result) =>
    result is _AnotherChatPick;

class _ComposerReplyOptionRow extends StatelessWidget {
  const _ComposerReplyOptionRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppInteractiveSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            AppIcon(icon, size: 19, color: colors.textSecondary),
            const SizedBox(width: 14),
            Text(
              label,
              style: AppTextStyle.bodyLarge(
                colors.textPrimary,
                weight: AppTextWeight.medium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
