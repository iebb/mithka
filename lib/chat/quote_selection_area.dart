import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;

import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'messages/message_text_quote.dart';

/// A selectable preview of the reply target's text, following the reference
/// client's quote flow: the message itself is the selection surface, the
/// quoted range is visibly marked, and any live selection immediately
/// becomes the quote.
///
/// The mark is painted as a highlighted span (exact offsets, always visible
/// for a programmatic quote), while interaction runs through [SelectionArea]
/// — the same mechanism the transcript uses, so touch handles appear and
/// drag outside the sheet's gesture arena. A bottom sheet's drag-to-dismiss
/// recognizer must stay disabled for handle drags to feel smooth.
class QuoteSelectionArea extends StatefulWidget {
  const QuoteSelectionArea({
    super.key,
    required this.message,
    required this.maxLength,
    this.initialQuote,
    this.onSelectionChanged,
  });

  final ChatMessage message;

  /// Server-side quote length limit for this chat.
  final int maxLength;

  /// The quote already attached to the pending reply, if any; its range is
  /// marked when the area first builds.
  final MessageTextQuote? initialQuote;

  /// Reports the quote built from the current selection and the RAW selected
  /// length: (null, 0) when empty; (null, n) when the selection cannot form
  /// a valid quote (e.g. over the limit); (quote, n) when it can.
  final void Function(MessageTextQuote? quote, int selectedLength)?
  onSelectionChanged;

  @override
  State<QuoteSelectionArea> createState() => QuoteSelectionAreaState();
}

/// Public state handle so the host sheet can drive the mark / select-all.
class QuoteSelectionAreaState extends State<QuoteSelectionArea> {
  final GlobalKey<SelectionAreaState> _selectionKey =
      GlobalKey<SelectionAreaState>();

  /// The currently marked range, or null when nothing is quoted.
  (int, int)? _markedRange;

  @override
  void initState() {
    super.initState();
    final quote = widget.initialQuote;
    if (quote != null) {
      _markedRange = (quote.position, quote.position + quote.text.length);
    }
  }

  void _handleSelectionChanged(SelectedContent? content) {
    final plain = content?.plainText;
    if (plain == null || plain.isEmpty) {
      widget.onSelectionChanged?.call(null, 0);
      return;
    }
    // SelectionArea reports content, not offsets; resolve the selected plain
    // text back onto the source. Identical text quotes identically, so the
    // first occurrence is the quote wherever the source repeats itself.
    final text = widget.message.quoteSourceText;
    final start = text.indexOf(plain);
    if (start < 0) {
      widget.onSelectionChanged?.call(null, plain.length);
      return;
    }
    // Report the raw length even when the range cannot form a quote (over
    // the limit): the counter row must not change SIZE mid-drag or the panel
    // layout oscillates while the finger crosses the counter row.
    widget.onSelectionChanged?.call(
      quoteMessageRange(
        widget.message,
        start: start,
        end: start + plain.length,
        maxLength: widget.maxLength,
      ),
      plain.length,
    );
  }

  /// Marks [range] as the quoted span. The mark replaces any live selection.
  void markRange((int, int)? range) {
    setState(() => _markedRange = range);
    if (range == null) {
      _selectionKey.currentState?.selectableRegion.clearSelection();
    }
  }

  /// Selects the whole text, flowing through the selection listener exactly
  /// like a touch selection (reference parity: the quote row with no active
  /// selection auto-selects the full message up to the quote limit).
  void selectFullText() {
    _selectionKey.currentState?.selectableRegion.selectAll();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final text = widget.message.quoteSourceText;
    final range = _markedRange;
    final span = TextSpan(
      style: AppTextStyle.bodyLarge(colors.textPrimary),
      children: [
        if (range == null)
          TextSpan(text: text)
        else ...[
          TextSpan(text: text.substring(0, range.$1)),
          TextSpan(
            text: text.substring(range.$1, range.$2),
            style: TextStyle(background: _markPaint(context)),
          ),
          TextSpan(text: text.substring(range.$2)),
        ],
      ],
    );
    return SelectionArea(
      key: _selectionKey,
      onSelectionChanged: _handleSelectionChanged,
      child: Text.rich(
        span,
        key: const ValueKey('composerReplyOptionsPreview'),
      ),
    );
  }

  /// The mark uses the theme's selection color so it reads as a selection
  /// highlight in both appearances.
  Paint _markPaint(BuildContext context) {
    final selectionColor = Theme.of(context).colorScheme.primary;
    return Paint()
      ..color = selectionColor.withValues(alpha: 0.28)
      ..style = PaintingStyle.fill;
  }
}
