import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../platform/adaptive_platform.dart';
import '../tdlib/td_models.dart';
import 'message_text_quote.dart';
import 'pangu_spacing.dart';

typedef DesktopQuoteChanged =
    void Function(ChatMessage message, MessageTextQuote? quote);

/// Tracks only the original body/caption, excluding sender, reply and preview
/// text. Offsets come from Flutter's selection, never a substring search (which
/// would quote the wrong occurrence when a message repeats the same words).
class DesktopMessageQuoteSource extends StatefulWidget {
  const DesktopMessageQuoteSource({
    super.key,
    required this.message,
    required this.displayedText,
    required this.child,
    this.onChanged,
    this.renderedText,
    this.renderedSpacing = const <int>[],
  });

  final ChatMessage message;

  /// The body as stored. A quote range always addresses this text.
  final String displayedText;
  final Widget child;
  final DesktopQuoteChanged? onChanged;

  /// What the paragraphs actually paint, when that differs from
  /// [displayedText] because 盘古之白 spaced the text for display.
  final String? renderedText;

  /// The inserted spaces, as UTF-16 offsets in [displayedText].
  final List<int> renderedSpacing;

  @override
  State<DesktopMessageQuoteSource> createState() =>
      _DesktopMessageQuoteSourceState();
}

class _DesktopMessageQuoteSourceState extends State<DesktopMessageQuoteSource> {
  late final _QuoteSelectionDelegate _delegate = _QuoteSelectionDelegate(
    () => widget,
    () => context.findRenderObject(),
  );

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isDesktopTargetPlatform(Theme.of(context).platform) ||
        widget.onChanged == null ||
        widget.displayedText != widget.message.quoteSourceText ||
        !canQuoteMessageText(widget.message)) {
      return widget.child;
    }
    return SelectionContainer(delegate: _delegate, child: widget.child);
  }
}

class _QuoteSelectionDelegate extends StaticSelectionContainerDelegate {
  _QuoteSelectionDelegate(this.source, this.renderSource);

  final DesktopMessageQuoteSource Function() source;
  final RenderObject? Function() renderSource;
  MessageTextQuote? _lastQuote;

  MessageTextQuote? _selectedQuote() {
    final widget = source();
    if (widget.displayedText != widget.message.quoteSourceText) {
      return null;
    }
    // Flutter's fragment ranges around WidgetSpans use paragraph offsets,
    // whereas the aggregate range adds preceding fragment lengths. Read each
    // paragraph's actual selection and expand inline selectable text in source
    // order so emoji/code widgets cannot shift UTF-16 quote positions.
    final rendered = StringBuffer();
    final selected = <TextRange>[];
    void visit(RenderObject node) {
      if (node is! RenderParagraph) {
        node.visitChildren(visit);
        return;
      }
      if (node.registrar == null) return;
      final text = node.text.toPlainText(includeSemanticsLabels: false);
      final inlineChildren = <RenderObject>[];
      node.visitChildren(inlineChildren.add);
      final ranges = <TextRange>[
        for (final selectable in selectables)
          if (node.selectableBelongsToParagraph(selectable))
            if (selectable.getSelection() case final range?)
              TextRange(
                start: math.min(range.startOffset, range.endOffset),
                end: math.max(range.startOffset, range.endOffset),
              ),
      ];
      // Text widgets (including inline emoji/code fallback text) own a nested
      // selection container. Its public range is local when it contains one
      // unbroken paragraph; verify the selected text before using that range.
      final registrar = node.registrar;
      if (ranges.isEmpty &&
          !identical(registrar, this) &&
          registrar is SelectionContainerDelegate &&
          !text.contains('\uFFFC') &&
          registrar.contentLength == text.length) {
        final range = registrar.getSelection();
        if (range != null) {
          final start = math.min(range.startOffset, range.endOffset);
          final end = math.max(range.startOffset, range.endOffset);
          if (start >= 0 &&
              end <= text.length &&
              text.substring(start, end) ==
                  registrar.getSelectedContent()?.plainText) {
            ranges.add(TextRange(start: start, end: end));
          }
        }
      }
      var childIndex = 0;
      var cursor = 0;
      void appendText(int end) {
        final sourceOffset = rendered.length;
        rendered.write(text.substring(cursor, end));
        for (final selection in ranges) {
          final start = math.max(cursor, selection.start);
          final finish = math.min(end, selection.end);
          if (start < finish) {
            selected.add(
              TextRange(
                start: sourceOffset + start - cursor,
                end: sourceOffset + finish - cursor,
              ),
            );
          }
        }
      }

      for (var offset = 0; offset < text.length; offset++) {
        if (text.codeUnitAt(offset) != 0xfffc) continue;
        appendText(offset);
        if (childIndex < inlineChildren.length) {
          visit(inlineChildren[childIndex++]);
        }
        cursor = offset + 1;
      }
      appendText(text.length);
    }

    final root = renderSource();
    if (root == null || !root.attached) return null;
    visit(root);
    // Transformed source text, non-text widgets, or disjoint selections must
    // fail closed, never quote a guessed occurrence or unseen intervening text.
    final painted = widget.renderedText ?? widget.displayedText;
    if (rendered.toString() != painted || selected.isEmpty) {
      return null;
    }
    selected.sort((a, b) => a.start.compareTo(b.start));
    final start = selected.first.start;
    var end = selected.first.end;
    for (final range in selected.skip(1)) {
      if (range.start > end) return null;
      end = math.max(end, range.end);
    }
    // Selection offsets address the painted text; the quote has to address the
    // stored one, so display spacing is taken back out first.
    final mapped = PanguSpacing.reverseRange(
      start: start,
      end: end,
      insertedOffsets: widget.renderedSpacing,
      sourceLength: widget.displayedText.length,
    );
    return quoteMessageRange(
      widget.message,
      start: mapped.start,
      end: mapped.end,
      // The chat validates the server's current limit before setting a reply.
      maxLength: widget.displayedText.length,
    );
  }

  @override
  void notifyListeners() {
    super.notifyListeners();
    final quote = _selectedQuote();
    if (quote == null && _lastQuote == null) return;
    _lastQuote = quote;
    source().onChanged?.call(source().message, quote);
  }

  @override
  void dispose() {
    if (_lastQuote != null) source().onChanged?.call(source().message, null);
    super.dispose();
  }
}
