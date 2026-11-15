import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'message_text_quote.dart';

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
      _ComposerReplyOptionsSheetState();
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

class _ComposerReplyOptionsSheetState extends State<ComposerReplyOptionsSheet> {
  MessageTextQuote? _quote;
  late final TextEditingController _previewController;

  @override
  void initState() {
    super.initState();
    _quote = widget.initialQuote;
    _previewController = TextEditingController(
      text: widget.message.quoteSourceText,
    );
    // Mark the quoted range with the selection highlight (reference parity:
    // the preview cell re-selects quoteStart..quoteEnd when the panel opens,
    // so the quoted part of the message is always visible).
    final quote = _quote;
    if (quote != null) {
      _previewController.selection = _selectionForQuote(quote);
    }
    _previewController.addListener(_onPreviewSelectionChanged);
  }

  /// Reference parity (TextSelectionHelper.Callback.onStateChanged): the
  /// first non-collapsed selection in the preview attaches itself as the
  /// quote, switching the panel into quote mode. Later drags keep the live
  /// selection; the quote row / apply commit the current range.
  void _onPreviewSelectionChanged() {
    if (!mounted) return;
    final selection = _previewController.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final quote = _quoteFromSelection();
    if (quote == null) return;
    if (_quote == null || _quote!.text != quote.text) {
      setState(() => _quote = quote);
    }
  }

  /// Selection spanning exactly [quote]'s range inside the preview text.
  TextSelection _selectionForQuote(MessageTextQuote quote) {
    final text = _previewController.text;
    final start = quote.position.clamp(0, text.length);
    final end = (quote.position + quote.text.length).clamp(start, text.length);
    return TextSelection(baseOffset: start, extentOffset: end);
  }

  @override
  void dispose() {
    _previewController.removeListener(_onPreviewSelectionChanged);
    _previewController.dispose();
    super.dispose();
  }

  MessageTextQuote? _quoteFromSelection() {
    final selection = _previewController.selection;
    if (!selection.isValid) return null;
    final length = selection.end - selection.start;
    if (length <= 0 || length > widget.quoteLengthLimit) return null;
    return quoteMessageRange(
      widget.message,
      start: selection.start,
      end: selection.end,
      maxLength: widget.quoteLengthLimit,
    );
  }

  void _popWith(ComposerReplyOptionsResult result) {
    Navigator.of(context).pop(result);
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
                  child: TextField(
                    key: const ValueKey('composerReplyOptionsPreview'),
                    controller: _previewController,
                    readOnly: true,
                    maxLines: 4,
                    minLines: 1,
                    style: AppTextStyle.bodyLarge(colors.textPrimary),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                    ),
                    contextMenuBuilder: (_, _) => const SizedBox.shrink(),
                    onTap: () => setState(() {}),
                  ),
                  // Selection state is read on build; the controller does
                  // not notify listeners for handle drags, so rebuild on
                  // every tap and rely on the quote row reading the live
                  // selection when tapped.
                ),
              ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _previewController,
                builder: (context, value, _) {
                  final selection = value.selection;
                  final length = selection.isValid
                      ? selection.end - selection.start
                      : 0;
                  if (length <= 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 2),
                    child: Text(
                      '$length / ${widget.quoteLengthLimit}',
                      key: const ValueKey('composerReplyOptionsQuoteLength'),
                      textAlign: TextAlign.end,
                      style: AppTextStyle.body(
                        length > widget.quoteLengthLimit
                            ? AppTheme.tagRed
                            : colors.textSecondary,
                      ),
                    ),
                  );
                },
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
                onTap: () {
                  if (_quote != null) {
                    setState(() => _quote = null);
                    _previewController.selection = TextSelection.collapsed(
                      offset: _previewController.text.length,
                    );
                    return;
                  }
                  var quote = _quoteFromSelection();
                  if (quote == null) {
                    // No selection yet: select the full text (up to the quote
                    // limit) so the quote row has something to apply — the
                    // reference client auto-selects 0..min(max, fullLength)
                    // when the preview has no active selection.
                    final text = _previewController.text;
                    final end = math.min(widget.quoteLengthLimit, text.length);
                    if (end <= 0) return;
                    quote = quoteMessageRange(
                      widget.message,
                      start: 0,
                      end: end,
                      maxLength: widget.quoteLengthLimit,
                    );
                    if (quote == null) return;
                    _previewController.selection = TextSelection(
                      baseOffset: 0,
                      extentOffset: end,
                    );
                  }
                  setState(() => _quote = quote!);
                },
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
