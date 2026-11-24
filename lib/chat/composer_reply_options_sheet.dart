import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'messages/message_text_quote.dart';
import 'quote_selection_area.dart';

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

/// The reply-options panel opened by tapping the composer's reply banner.
/// Follows the reference client's message-preview layout: a titled header
/// ("Reply to message" / "you can select a specific part of the quote"), the
/// reply target rendered as a preview whose text can be selected to build a
/// quote, and a menu with quote / another-chat / apply / drop entries.
class ComposerReplyOptionsSheet extends StatefulWidget {
  const ComposerReplyOptionsSheet({
    super.key,
    required this.message,
    required this.canQuote,
    required this.canReplyInAnotherChat,
    required this.quoteLengthLimit,
    this.initialQuote,
  });

  final ChatMessage message;

  /// Whether text quoting is offered (target chat permits it).
  final bool canQuote;

  /// Whether the "reply in another chat" entry is offered. The message must
  /// allow it (`messageProperties.can_be_replied_in_another_chat`) and the
  /// current chat must not be a secret chat.
  final bool canReplyInAnotherChat;

  /// Server-side quote length limit for this chat.
  final int quoteLengthLimit;

  /// The quote already attached to the pending reply, if any.
  final MessageTextQuote? initialQuote;

  @override
  State<ComposerReplyOptionsSheet> createState() =>
      ComposerReplyOptionsSheetState();
}

/// Whether the banner still alternates its preview line with the
/// "tap for reply options" hint. Cleared after the first panel session.
Future<bool> composerReplyOptionsHintSeen() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_replyOptionsHintSeenKey) ?? false;
}

Future<void> _markReplyOptionsHintSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_replyOptionsHintSeenKey, true);
}

const _replyOptionsHintSeenKey = 'composer.replyOptionsHintSeen.v1';

/// Public state handle so tests can drive selection callbacks.
class ComposerReplyOptionsSheetState extends State<ComposerReplyOptionsSheet> {
  MessageTextQuote? _quote;

  /// Live selection length for the counter row. The row keeps its height
  /// whenever a quote CAN exist (initial quote or any selection), so the
  /// layout below it never shifts while the finger crosses the counter row.
  int _selectionLength = 0;
  bool _counterRowActive = false;

  final GlobalKey<QuoteSelectionAreaState> _previewKey =
      GlobalKey<QuoteSelectionAreaState>();

  @override
  void initState() {
    super.initState();
    _quote = widget.initialQuote;
    if (_quote != null) {
      _selectionLength = _quote!.text.length;
      _counterRowActive = true;
    }
  }

  void _popWith(ComposerReplyOptionsResult result) {
    Navigator.of(context).pop(result);
  }

  /// A live preview selection becomes the quote immediately (reference
  /// parity: the reference client's selection callback attaches the quote
  /// the moment a selection exists).
  @visibleForTesting
  void debugSimulateSelection(MessageTextQuote? quote, int selectedLength) =>
      _onPreviewSelectionChanged(quote, selectedLength);

  void _onPreviewSelectionChanged(MessageTextQuote? quote, int selectedLength) {
    if (!mounted) return;
    setState(() {
      _selectionLength = selectedLength;
      // Once any selection has existed the counter row stays laid out —
      // toggling its height mid-drag makes the menu jump up/down when the
      // finger passes over the row.
      if (selectedLength > 0) _counterRowActive = true;
      if (quote != null) _quote = quote;
    });
  }

  void _toggleQuote() {
    final quote = _quote;
    if (quote != null) {
      setState(() {
        _quote = null;
        _selectionLength = 0;
      });
      _previewKey.currentState?.markRange(null);
      return;
    }
    // No quote yet: the reference client auto-selects the full text (up to
    // the quote limit); the selection listener then attaches the quote
    // exactly like a touch selection.
    final text = widget.message.quoteSourceText;
    if (text.isEmpty) return;
    if (text.length <= widget.quoteLengthLimit) {
      _previewKey.currentState?.selectFullText();
      return;
    }
    final clipped = quoteMessageRange(
      widget.message,
      start: 0,
      end: widget.quoteLengthLimit,
      maxLength: widget.quoteLengthLimit,
    );
    if (clipped == null) return;
    _previewKey.currentState?.markRange((
      clipped.position,
      clipped.position + clipped.text.length,
    ));
    setState(() {
      _quote = clipped;
      _selectionLength = clipped.text.length;
      _counterRowActive = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final hasText = widget.message.quoteSourceText.trim().isNotEmpty;
    final quoteSelectable = widget.canQuote && hasText;
    _markReplyOptionsHintSeen();
    return Material(
      key: const ValueKey('composerReplyOptionsSheet'),
      color: colors.panelBackground,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.xl),
      ),
      clipBehavior: Clip.antiAlias,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _quote != null
                        ? AppStringKeys.composerReplyOptionsUpdateTitle.l10n(
                            context,
                          )
                        : AppStringKeys.composerReplyOptionsTitle.l10n(context),
                    style: AppTextStyle.title(
                      colors.textPrimary,
                      weight: AppTextWeight.bold,
                    ),
                  ),
                  if (quoteSelectable) ...[
                    const SizedBox(height: 2),
                    Text(
                      _quote != null
                          ? AppStringKeys.composerReplyOptionsUpdateSubtitle
                                .l10n(context)
                          : AppStringKeys.composerReplyOptionsSubtitle.l10n(
                              context,
                            ),
                      style: AppTextStyle.body(colors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (quoteSelectable) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                  decoration: BoxDecoration(
                    color: colors.searchFill,
                    borderRadius: BorderRadius.circular(AppRadius.card),
                  ),
                  child: QuoteSelectionArea(
                    key: _previewKey,
                    message: widget.message,
                    maxLength: widget.quoteLengthLimit,
                    initialQuote: widget.initialQuote,
                    onSelectionChanged: _onPreviewSelectionChanged,
                  ),
                ),
              ),
              // The counter keeps a stable slot once active; only its text
              // changes, so drags near the row cannot oscillate the layout.
              if (_counterRowActive)
                SizedBox(
                  height: 24,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '$_selectionLength / ${widget.quoteLengthLimit}',
                      key: const ValueKey('composerReplyOptionsQuoteLength'),
                      textAlign: TextAlign.end,
                      style: AppTextStyle.body(
                        _selectionLength > widget.quoteLengthLimit
                            ? AppTheme.tagRed
                            : colors.textSecondary,
                      ),
                    ),
                  ),
                ),
            ],
            const SizedBox(height: 6),
            if (quoteSelectable)
              _ReplyOptionMenuRow(
                key: ValueKey(
                  _quote != null
                      ? 'composerReplyOptionClearQuote'
                      : 'composerReplyOptionQuote',
                ),
                icon: _quote != null
                    ? HeroAppIcons.xmark
                    : HeroAppIcons.quoteLeft,
                label: _quote != null
                    ? AppStringKeys.composerReplyOptionClearQuote.l10n(context)
                    : AppStringKeys.composerReplyOptionQuote.l10n(context),
                onTap: _toggleQuote,
              ),
            if (widget.canReplyInAnotherChat)
              _ReplyOptionMenuRow(
                key: const ValueKey('composerReplyOptionAnotherChat'),
                icon: HeroAppIcons.forward,
                label: AppStringKeys.composerReplyOptionAnotherChat.l10n(
                  context,
                ),
                onTap: () =>
                    _popWith(ComposerReplyOptionsAnotherChat(quote: _quote)),
              ),
            const SizedBox(height: 6),
            _ReplyOptionMenuRow(
              key: const ValueKey('composerReplyOptionApply'),
              icon: HeroAppIcons.check,
              label: AppStringKeys.composerReplyOptionApply.l10n(context),
              onTap: () => _popWith(
                _quote == null
                    ? const ComposerReplyOptionsApply()
                    : ComposerReplyOptionsQuote(_quote!),
              ),
            ),
            _ReplyOptionMenuRow(
              key: const ValueKey('composerReplyOptionCancel'),
              icon: HeroAppIcons.trash,
              label: AppStringKeys.composerReplyOptionCancel.l10n(context),
              color: AppTheme.tagRed,
              onTap: () => _popWith(const ComposerReplyOptionsRemove()),
            ),
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
      ),
    );
  }
}

/// One 48dp menu row: icon, label, full-width tap target.
class _ReplyOptionMenuRow extends StatelessWidget {
  const _ReplyOptionMenuRow({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  final AppIconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    return AppInteractiveSurface(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        height: 48,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Row(
            children: [
              AppIcon(icon, size: 19, color: color ?? colors.textSecondary),
              const SizedBox(width: 14),
              Text(
                label,
                style: AppTextStyle.bodyLarge(
                  color ?? colors.textPrimary,
                  weight: AppTextWeight.medium,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
