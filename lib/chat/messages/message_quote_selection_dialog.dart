import 'package:flutter/material.dart';

import '../../components/app_dialog.dart';
import '../../l10n/app_localizations.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_theme.dart';
import 'message_text_quote.dart';

/// Selection offsets address an immutable copy of the original message, not
/// translated text, sender labels, timestamps, or the first matching substring.
class MessageQuoteSelectionDialog extends StatefulWidget {
  const MessageQuoteSelectionDialog({
    super.key,
    required this.message,
    required this.maxLength,
  });

  final ChatMessage message;
  final int maxLength;

  @override
  State<MessageQuoteSelectionDialog> createState() =>
      _MessageQuoteSelectionDialogState();
}

class _MessageQuoteSelectionDialogState
    extends State<MessageQuoteSelectionDialog> {
  late final ChatMessage _source;
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _source = ChatMessage(
      id: widget.message.id,
      isOutgoing: widget.message.isOutgoing,
      date: widget.message.date,
      contentType: widget.message.contentType,
      text: widget.message.quoteSourceText,
      textEntities: List.of(widget.message.quoteSourceEntities),
    );
    _controller = TextEditingController(text: _source.text);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(
    BuildContext context,
  ) => ValueListenableBuilder<TextEditingValue>(
    valueListenable: _controller,
    builder: (context, value, _) {
      final selection = value.selection;
      final quote = quoteMessageRange(
        _source,
        start: selection.start,
        end: selection.end,
        maxLength: widget.maxLength,
      );
      final length = selection.isValid ? selection.end - selection.start : 0;
      final colors = context.colors;
      return AppDialogSurface(
        maxWidth: 560,
        title: AppStringKeys.messageActionQuote.l10n(context),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStringKeys.messageActionSelectText.l10n(context),
              style: AppTextStyle.body(colors.textSecondary),
            ),
            const SizedBox(height: 12),
            TextField(
              key: const ValueKey('message-quote-source'),
              controller: _controller,
              readOnly: true,
              autofocus: true,
              minLines: 3,
              maxLines: 12,
              style: AppTextStyle.bodyLarge(colors.textPrimary),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
              ),
              // The dialog owns its actions; selection handles remain native.
              contextMenuBuilder: (_, _) => const SizedBox.shrink(),
            ),
            const SizedBox(height: 12),
            Text(
              '$length / ${widget.maxLength}',
              key: const ValueKey('message-quote-length'),
              textAlign: TextAlign.end,
              style: AppTextStyle.body(
                length > widget.maxLength
                    ? AppTheme.tagRed
                    : colors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          AppDialogAction(
            label: AppStringKeys.confirmCancel.l10n(context),
            onTap: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Semantics(
              button: true,
              enabled: quote != null,
              child: GestureDetector(
                key: const ValueKey('message-quote-confirm'),
                behavior: HitTestBehavior.opaque,
                onTap: quote == null
                    ? null
                    : () => Navigator.of(context).pop(quote),
                child: Center(
                  child: Text(
                    AppStringKeys.messageActionQuote.l10n(context),
                    style: AppTextStyle.bodyLarge(
                      quote == null ? colors.textTertiary : colors.dialogButton,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    },
  );
}
