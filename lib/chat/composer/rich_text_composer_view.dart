import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../../components/app_icons.dart';
import '../../components/app_text_selection_toolbar.dart';
import '../../components/toast.dart';
import '../../media/app_asset_picker.dart';
import '../../tdlib/td_models.dart';
import '../../theme/app_motion.dart';
import '../../theme/app_theme.dart';
import '../../theme/theme_controller.dart';
import '../media/audio_search_view.dart';
import '../media/image_edit_view.dart';
import '../stickers/emoji_text_controller.dart';
import 'location_picker_view.dart';
import 'outgoing_attachment.dart';
import 'rich_message_source.dart';
import 'rich_text_format.dart';

part 'rich_text_composer_models.dart';
part 'rich_text_composer_menus.dart';

class RichTextComposerResult {
  const RichTextComposerResult({
    required this.text,
    required this.entities,
    required this.attachments,
    required this.segments,
    this.hasRichBlocks = false,
  });

  final String text;
  final List<Map<String, dynamic>> entities;
  final List<OutgoingAttachment> attachments;
  final List<RichMessageSendSegment> segments;

  /// Whether the document holds structure that a plain formatted message
  /// cannot carry: headings, lists, quotes, tables, buttons, math, maps,
  /// dividers or media. `text`/`entities` still hold every piece of text, so a
  /// caller without a rich send path can deliver the text and drop the blocks.
  final bool hasRichBlocks;

  /// Whether an ordinary formatted message carries this document unchanged:
  /// text with inline entities only, within the plain message length. Such a
  /// document is sent inline rather than as a rich message.
  bool get sendsAsFormattedText =>
      !hasRichBlocks &&
      attachments.isEmpty &&
      text.trim().isNotEmpty &&
      telegramMessageLengthTier(text) == TelegramMessageLengthTier.standard;

  FormattedTextPayload get formattedText =>
      FormattedTextPayload(text, entities);
}

Future<RichTextComposerResult?> showRichTextComposerSheet(
  BuildContext context, {
  required String initialText,
  List<Map<String, dynamic>> initialEntities = const [],
  List<XFile> initialMedia = const [],
  List<OutgoingAttachment> initialAttachments = const [],
  String title = AppStringKeys.topicChatShare,
  String submitText = AppStringKeys.topicChatPublish,
  String hintText = AppStringKeys.richTextComposerContentPlaceholder,
  bool allowMedia = true,
}) {
  return showAppAdaptiveSheetDialog<RichTextComposerResult>(
    context: context,
    builder: (dialogContext) => RichTextComposerView(
      initialText: initialText,
      initialEntities: initialEntities,
      initialMedia: initialMedia,
      initialAttachments: initialAttachments,
      title: title,
      submitText: submitText,
      hintText: hintText,
      allowMedia: allowMedia,
      asSheet: true,
    ),
    barrierLabel: title.l10n(context),
    barrierColor: Colors.black.withValues(alpha: 0.36),
    transitionDuration: const Duration(milliseconds: 240),
    centeredBackgroundColor: context.colors.background,
    mobileTransitionBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  );
}

class RichTextComposerView extends StatefulWidget {
  const RichTextComposerView({
    super.key,
    required this.initialText,
    this.initialEntities = const [],
    this.initialMedia = const [],
    this.initialAttachments = const [],
    this.title = AppStringKeys.topicChatShare,
    this.submitText = AppStringKeys.topicChatPublish,
    this.hintText = AppStringKeys.richTextComposerContentPlaceholder,
    this.allowMedia = true,
    this.asSheet = false,
    this.showCloseAction = true,
    this.onClose,
    this.onSubmit,
  });

  final String initialText;
  final List<Map<String, dynamic>> initialEntities;
  final List<XFile> initialMedia;
  final List<OutgoingAttachment> initialAttachments;
  final String title;
  final String submitText;
  final String hintText;
  final bool allowMedia;
  final bool asSheet;
  final bool showCloseAction;
  final FutureOr<void> Function()? onClose;
  final FutureOr<void> Function(RichTextComposerResult result)? onSubmit;

  @override
  State<RichTextComposerView> createState() => _RichTextComposerViewState();
}

enum _RichCellHorizontalAlignment { left, center, right }

enum _RichCellVerticalAlignment { top, middle, bottom }

enum _RichTableMenuAction {
  addRowAbove,
  addRowBelow,
  addColumnLeft,
  addColumnRight,
  removeRow,
  removeColumn,
  removeTable,
}

class _RichTableCellStyle {
  _RichTableCellStyle({this.isHeader = false});

  bool isHeader;
  _RichCellHorizontalAlignment horizontal = _RichCellHorizontalAlignment.left;
  _RichCellVerticalAlignment vertical = _RichCellVerticalAlignment.top;
}

class _RichTextComposerViewState extends State<RichTextComposerView> {
  static const _maxAttachments = 50;
  static const _maxBlocks = 500;
  static const _maxTextCharacters = telegramRichMessageMaxCharacters;

  late final List<_RichContentBlock> _blocks;
  late _RichTextBlock _activeTextBlock;

  @override
  void initState() {
    super.initState();
    final first = _createTextBlock(
      widget.initialText,
      entities: widget.initialEntities,
    );
    _blocks = [_RichContentBlock.text(first)];
    _activeTextBlock = first;
    final initialAttachments = <OutgoingAttachment>[
      ...widget.initialAttachments,
      ...widget.initialMedia.map(_attachmentFromPickedMedia),
    ].take(_maxAttachments);
    _blocks.addAll(initialAttachments.map(_RichContentBlock.attachment));
  }

  @override
  void dispose() {
    for (final block in _blocks) {
      _disposeBlock(block);
    }
    super.dispose();
  }

  _RichTextBlock _createTextBlock(
    String text, {
    List<Map<String, dynamic>> entities = const [],
    _RichBlockKind kind = _RichBlockKind.paragraph,
  }) {
    final controller = EmojiTextEditingController();
    if (entities.isEmpty) {
      controller.text = text;
    } else {
      controller.setFormattedText(text, entities);
    }
    final focusNode = FocusNode();
    late final _RichTextBlock block;
    void onTextChanged() {
      if (controller.text == block.lastText) return;
      final wasEmpty = block.lastText.trim().isEmpty;
      block.lastText = controller.text;
      // The field repaints itself off its controller; the only thing this page
      // builds from block text is `_hasAnyText`, so rebuild it only when this
      // block crosses empty/non-empty instead of on every keystroke.
      if (wasEmpty != controller.text.trim().isEmpty && mounted) {
        setState(() {});
      }
    }

    block = _RichTextBlock(controller, focusNode, onTextChanged, kind: kind);
    controller.addListener(onTextChanged);
    focusNode.addListener(() {
      if (!focusNode.hasFocus) return;
      _activeTextBlock = block;
      // The inline format row reads its enabled state and selection from the
      // active block, so it has to rebuild when focus moves to another one.
      if (mounted) setState(() {});
    });
    return block;
  }

  void _disposeTextBlock(_RichTextBlock block) {
    block.controller.removeListener(block.onTextChanged);
    block.controller.dispose();
    block.focusNode.dispose();
  }

  void _disposeBlock(_RichContentBlock block) {
    final text = block.text;
    if (text != null) _disposeTextBlock(text);
    block.table?.dispose();
    block.math?.dispose();
    block.generic?.dispose();
    block.mediaGroup?.dispose();
    block.buttonRow?.dispose();
  }

  void _submit() {
    if (_blocks.length > _maxBlocks ||
        _documentTextCharacterCount() > _maxTextCharacters ||
        _attachmentCount > _maxAttachments) {
      showToast(
        context,
        AppStringKeys.richTextComposerLimitExceeded.l10n(context),
      );
      return;
    }
    final buffer = StringBuffer();
    final entities = <Map<String, dynamic>>[];
    final attachments = <OutgoingAttachment>[];
    final segments = <RichMessageSendSegment>[];
    final htmlBuffer = StringBuffer();
    final htmlFiles = <RichMessageSendFile>[];
    final inputBlocks = <Map<String, dynamic>>[];
    final pendingAttachments = <OutgoingAttachment>[];
    var hasContent = false;
    var hasRichBlocks = false;

    void flushHtml() {
      final html = htmlBuffer.toString().trim();
      if (html.isNotEmpty || inputBlocks.isNotEmpty) {
        segments.add(
          RichMessageSendSegment.html(
            html,
            richFiles: List<RichMessageSendFile>.unmodifiable(htmlFiles),
            blocks: List<Map<String, dynamic>>.unmodifiable(inputBlocks),
          ),
        );
      }
      htmlBuffer.clear();
      htmlFiles.clear();
      inputBlocks.clear();
    }

    void flushAttachments() {
      if (pendingAttachments.isEmpty) return;
      segments.add(
        RichMessageSendSegment.attachments(
          List<OutgoingAttachment>.unmodifiable(pendingAttachments),
        ),
      );
      pendingAttachments.clear();
    }

    for (final block in _blocks) {
      final mediaGroup = block.mediaGroup;
      if (mediaGroup != null) {
        if (mediaGroup.items.isEmpty) continue;
        hasRichBlocks = true;
        flushAttachments();
        final tag = mediaGroup.kind == _RichBlockKind.collage
            ? 'tg-collage'
            : 'tg-slideshow';
        htmlBuffer.write('<$tag>');
        for (final item in mediaGroup.items) {
          attachments.add(item);
          final id = 'mithka-rich-${segments.length}-${htmlFiles.length}';
          htmlFiles.add(RichMessageSendFile(id: id, attachment: item));
          htmlBuffer.write(_mediaBlockHtml(item, id));
        }
        final caption = mediaGroup.caption.text.trim();
        if (caption.isNotEmpty) {
          htmlBuffer.write(
            '<figcaption>${escapeRichHtml(caption)}</figcaption>',
          );
        }
        htmlBuffer.write('</$tag>');
        inputBlocks.add({
          '@type': mediaGroup.kind == _RichBlockKind.collage
              ? 'inputPageBlockCollage'
              : 'inputPageBlockSlideshow',
          'blocks': mediaGroup.items.map(richMessageMediaBlockPayload).toList(),
          'caption': caption.isEmpty
              ? null
              : {
                  '@type': 'pageBlockCaption',
                  'text': formattedTextToRichText(caption, const []),
                  'credit': null,
                },
        });
        continue;
      }
      final attachment = block.attachment;
      if (attachment != null) {
        hasRichBlocks = true;
        attachments.add(attachment);
        if (attachment.kind == OutgoingAttachmentKind.document) {
          flushHtml();
          pendingAttachments.add(attachment);
          continue;
        }
        flushAttachments();
        final id = 'mithka-rich-${segments.length}-${htmlFiles.length}';
        htmlFiles.add(RichMessageSendFile(id: id, attachment: attachment));
        htmlBuffer.write(_mediaBlockHtml(attachment, id));
        inputBlocks.add(richMessageMediaBlockPayload(attachment));
        continue;
      }
      flushAttachments();
      final buttonRow = block.buttonRow;
      if (buttonRow != null) {
        if (buttonRow.buttons.isEmpty) continue;
        hasRichBlocks = true;
        final buttons = <Map<String, dynamic>>[];
        for (final button in buttonRow.buttons) {
          final label = button.label.text.trim();
          final url = button.url.text.trim();
          if (label.isEmpty || !_isValidRichButtonUrl(url)) {
            showToast(
              context,
              AppStringKeys.richTextComposerButtonInvalid.l10n(context),
            );
            return;
          }
          buttons.add({
            '@type': 'inlineButton',
            'text': formattedTextToRichText(label, const []),
            'type': {'@type': 'inlineKeyboardButtonTypeUrl', 'url': url},
            if (button.style != _RichButtonStyle.standard)
              'style': {'@type': button.style.tdType},
          });
        }
        inputBlocks.add({
          '@type': 'inputPageBlockButtonRow',
          'buttons': buttons,
          'align': {'@type': buttonRow.alignment.tdType},
        });
        continue;
      }
      String text;
      List<Map<String, dynamic>> blockEntities = const [];
      if (block.text != null) {
        final formatted = block.text!.controller.toFormatted();
        text = formatted.$1;
        blockEntities = formatted.$2;
        htmlBuffer.write(_textBlockHtml(block.text!, text, blockEntities));
        final inputBlock = _textInputBlock(block.text!, text, blockEntities);
        if (inputBlock != null) inputBlocks.add(inputBlock);
      } else if (block.math != null) {
        hasRichBlocks = true;
        text = block.math!.controller.text.trim();
        if (text.isNotEmpty) {
          htmlBuffer.write(
            '<tg-math-block>${escapeRichHtml(text)}</tg-math-block>',
          );
          inputBlocks.add({
            '@type': 'inputPageBlockMathematicalExpression',
            'expression': text,
          });
        }
      } else if (block.table != null) {
        hasRichBlocks = true;
        text = block.table?.toMarkdown() ?? '';
        htmlBuffer.write(block.table?.toHtml() ?? '');
        inputBlocks.add(block.table!.toInputPageBlock());
      } else {
        hasRichBlocks = true;
        text = block.generic?.primary.text.trim() ?? '';
        htmlBuffer.write(_genericBlockHtml(block));
        final inputBlock = _genericInputBlock(block);
        if (inputBlock != null) inputBlocks.add(inputBlock);
      }
      if (text.trim().isEmpty) continue;
      final textBlock = block.text;
      if (textBlock != null &&
          textBlock.kind != _RichBlockKind.paragraph &&
          textBlock.kind != _RichBlockKind.thinking) {
        hasRichBlocks = true;
      }
      if (hasContent) buffer.write('\n\n');
      final offset = buffer.length;
      buffer.write(text);
      for (final entity in blockEntities) {
        entities.add(_shiftTextEntity(entity, offset));
      }
      hasContent = true;
    }
    flushAttachments();
    flushHtml();
    final result = RichTextComposerResult(
      text: buffer.toString(),
      entities: entities,
      attachments: List.unmodifiable(attachments),
      segments: List.unmodifiable(segments),
      hasRichBlocks: hasRichBlocks,
    );
    final callback = widget.onSubmit;
    if (callback != null) {
      unawaited(Future<void>.sync(() => callback(result)));
      return;
    }
    Navigator.of(context).pop(result);
  }

  void _close() {
    final callback = widget.onClose;
    if (callback != null) {
      unawaited(Future<void>.sync(callback));
      return;
    }
    Navigator.of(context).pop();
  }

  int _documentTextCharacterCount() {
    final text = StringBuffer();
    for (final block in _blocks) {
      text.write(block.text?.controller.text ?? '');
      text.write(block.math?.controller.text ?? '');
      final generic = block.generic;
      if (generic != null) {
        text
          ..write(generic.primary.text)
          ..write(generic.secondary.text)
          ..write(generic.tertiary.text);
      }
      final group = block.mediaGroup;
      if (group != null) text.write(group.caption.text);
      final buttonRow = block.buttonRow;
      if (buttonRow != null) {
        for (final button in buttonRow.buttons) {
          text
            ..write(button.label.text)
            ..write(button.url.text);
        }
      }
      final table = block.table;
      if (table != null) {
        for (final row in table.cells) {
          for (final cell in row) {
            text.write(cell.text);
          }
        }
      }
    }
    return telegramUtf8CharacterCount(text.toString());
  }

  bool _isValidRichButtonUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasScheme) return false;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      return uri.host.isNotEmpty;
    }
    return uri.scheme == 'tg';
  }

  String _mediaBlockHtml(OutgoingAttachment attachment, String id) {
    return switch (attachment.kind) {
      OutgoingAttachmentKind.photo => '<img src="tg://photo?id=$id"/>',
      OutgoingAttachmentKind.video || OutgoingAttachmentKind.animation =>
        '<video src="tg://video?id=$id"></video>',
      OutgoingAttachmentKind.audio || OutgoingAttachmentKind.voiceNote =>
        '<audio src="tg://audio?id=$id"></audio>',
      OutgoingAttachmentKind.document => '',
    };
  }

  Map<String, dynamic>? _textInputBlock(
    _RichTextBlock block,
    String text,
    List<Map<String, dynamic>> entities,
  ) {
    if (text.trim().isEmpty) return null;
    final richText = formattedTextToRichText(text, entities);
    return switch (block.kind) {
      _RichBlockKind.heading => {
        '@type': 'inputPageBlockSectionHeading',
        'text': richText,
        'size': block.headingLevel.clamp(1, 6),
      },
      _RichBlockKind.preformatted => {
        '@type': 'inputPageBlockPreformatted',
        'text': richText,
        'language': '',
      },
      _RichBlockKind.footer => {
        '@type': 'inputPageBlockFooter',
        'footer': richText,
      },
      _RichBlockKind.list => _listInputBlock(text, entities),
      _RichBlockKind.blockQuotation => {
        '@type': 'inputPageBlockBlockQuote',
        'blocks': [
          {'@type': 'inputPageBlockParagraph', 'text': richText},
        ],
        'credit': null,
      },
      _RichBlockKind.pullQuotation => {
        '@type': 'inputPageBlockPullQuote',
        'text': richText,
        'credit': null,
      },
      // A thinking block is ephemeral and bot-only. Preserve legacy drafts as a
      // normal paragraph when the user sends them so final sends are valid.
      _RichBlockKind.thinking || _RichBlockKind.paragraph => {
        '@type': 'inputPageBlockParagraph',
        'text': richText,
      },
      _ => null,
    };
  }

  Map<String, dynamic> _listInputBlock(
    String text,
    List<Map<String, dynamic>> entities,
  ) {
    final items = <Map<String, dynamic>>[];
    var sourceOffset = 0;
    for (final line in text.split('\n')) {
      final task = RegExp(r'^\s*-\s*\[([ xX])\]\s*(.*)$').firstMatch(line);
      final unordered = RegExp(r'^\s*[-*+]\s+(.*)$').firstMatch(line);
      final ordered = RegExp(r'^\s*(\d+)[.)]\s+(.*)$').firstMatch(line);
      final content =
          task?.group(2) ??
          unordered?.group(1) ??
          ordered?.group(2) ??
          line.trim();
      if (content.isNotEmpty) {
        final localOffset = line.indexOf(content);
        items.add({
          '@type': 'inputPageBlockListItem',
          'blocks': [
            {
              '@type': 'inputPageBlockParagraph',
              'text': formattedTextToRichText(
                content,
                entities,
                sourceOffset: sourceOffset + math.max(0, localOffset),
              ),
            },
          ],
          'has_checkbox': task != null,
          'is_checked': task?.group(1)?.toLowerCase() == 'x',
          'value': int.tryParse(ordered?.group(1) ?? '') ?? 0,
          'type': ordered == null ? '' : '1',
        });
      }
      sourceOffset += line.length + 1;
    }
    return {'@type': 'inputPageBlockList', 'items': items};
  }

  Map<String, dynamic>? _genericInputBlock(_RichContentBlock block) {
    final draft = block.generic;
    if (block.kind == _RichBlockKind.divider) {
      return {'@type': 'inputPageBlockDivider'};
    }
    if (draft == null) return null;
    final primary = draft.primary.text.trim();
    final secondary = draft.secondary.text.trim();
    return switch (block.kind) {
      _RichBlockKind.anchor when primary.isNotEmpty => {
        '@type': 'inputPageBlockAnchor',
        'name': primary,
      },
      _RichBlockKind.details when primary.isNotEmpty || secondary.isNotEmpty =>
        {
          '@type': 'inputPageBlockDetails',
          'header': formattedTextToRichText(primary, const []),
          'blocks': secondary.isEmpty
              ? <Map<String, dynamic>>[]
              : [
                  {
                    '@type': 'inputPageBlockParagraph',
                    'text': formattedTextToRichText(secondary, const []),
                  },
                ],
          'is_open': draft.enabled,
        },
      _RichBlockKind.map => {
        '@type': 'inputPageBlockMap',
        'location': {
          '@type': 'location',
          'latitude': double.tryParse(draft.primary.text.trim()) ?? 0,
          'longitude': double.tryParse(draft.secondary.text.trim()) ?? 0,
          'horizontal_accuracy': 0,
        },
        'zoom': draft.number.clamp(0, 24),
        'width': 320,
        'height': 180,
        'caption': null,
      },
      _ => null,
    };
  }

  String _textBlockHtml(
    _RichTextBlock block,
    String text,
    List<Map<String, dynamic>> entities,
  ) {
    if (text.trim().isEmpty) return '';
    final inline = formattedTextToRichInlineHtml(text, entities);
    return switch (block.kind) {
      _RichBlockKind.heading =>
        '<h${block.headingLevel.clamp(1, 6)}>$inline</h${block.headingLevel.clamp(1, 6)}>',
      _RichBlockKind.preformatted => '<pre>$inline</pre>',
      _RichBlockKind.footer => '<footer>$inline</footer>',
      _RichBlockKind.list => formattedTextToRichHtml(text, entities),
      _RichBlockKind.blockQuotation =>
        '<blockquote><p>$inline</p></blockquote>',
      _RichBlockKind.pullQuotation => '<aside>$inline</aside>',
      // Thinking is valid only in bot drafts. Legacy saved composer state must
      // become a persistent paragraph for both direct and relay final sends.
      _RichBlockKind.thinking => '<p>$inline</p>',
      _ => '<p>$inline</p>',
    };
  }

  String _genericBlockHtml(_RichContentBlock block) {
    final draft = block.generic;
    if (draft == null) {
      return block.kind == _RichBlockKind.divider ? '<hr/>' : '';
    }
    final primary = escapeRichHtml(draft.primary.text.trim());
    final secondary = escapeRichHtml(draft.secondary.text.trim());
    return switch (block.kind) {
      _RichBlockKind.anchor => primary.isEmpty ? '' : '<a name="$primary"></a>',
      _RichBlockKind.details =>
        '<details${draft.enabled ? ' open' : ''}><summary>$primary</summary><p>$secondary</p></details>',
      _RichBlockKind.map =>
        '<tg-map lat="${draft.primary.text.trim()}" long="${draft.secondary.text.trim()}" zoom="${draft.number.clamp(13, 20)}"/>',
      _ => '',
    };
  }

  Map<String, dynamic> _shiftTextEntity(Map<String, dynamic> entity, int by) {
    return {
      ...entity,
      'offset': ((entity['offset'] as int?) ?? 0) + by,
      if (entity['type'] is Map<String, dynamic>)
        'type': Map<String, dynamic>.of(entity['type'] as Map<String, dynamic>),
    };
  }

  void _insertTable() {
    final tableNumber =
        _blocks.where((block) => block.table != null).length + 1;
    _insertStructuredBlock(
      _RichContentBlock.table(
        _RichTableDraft(
          title:
              '${AppStringKeys.richTextComposerInsertTable.l10n(context)} $tableNumber',
        ),
      ),
    );
  }

  void _insertMathBlock() {
    _insertStructuredBlock(_RichContentBlock.math(_RichMathDraft()));
  }

  void _insertStructuredBlock(_RichContentBlock block) {
    if (_blocks.length >= _maxBlocks) {
      _disposeBlock(block);
      return;
    }
    final active = _activeTextBlock;
    final index = _blocks.indexWhere((item) => item.text == active);
    void focusAfterFrame(_RichTextBlock? target) {
      if (target == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) target.focusNode.requestFocus();
      });
    }

    if (index < 0) {
      final insertedText = block.text;
      setState(() {
        _blocks.add(block);
        if (insertedText != null) _activeTextBlock = insertedText;
      });
      focusAfterFrame(insertedText);
      return;
    }
    final controller = active.controller;
    final text = controller.text;
    final selection = controller.selection;
    final start = selection.isValid
        ? math.min(selection.start, selection.end)
        : text.length;
    final end = selection.isValid
        ? math.max(selection.start, selection.end)
        : text.length;
    final before = text.substring(0, start);
    final after = text.substring(end);
    if (before.isEmpty && after.isEmpty) {
      final removed = _blocks[index];
      final insertedText = block.text;
      setState(() {
        _blocks[index] = block;
        if (insertedText != null) _activeTextBlock = insertedText;
      });
      _disposeBlock(removed);
      focusAfterFrame(insertedText);
      return;
    }
    if (start == 0 && end == 0) {
      final insertedText = block.text;
      setState(() {
        _blocks.insert(index, block);
        if (insertedText != null) _activeTextBlock = insertedText;
      });
      focusAfterFrame(insertedText);
      return;
    }
    if (start == text.length && end == text.length) {
      final insertedText = block.text;
      setState(() {
        _blocks.insert(index + 1, block);
        if (insertedText != null) _activeTextBlock = insertedText;
      });
      focusAfterFrame(insertedText);
      return;
    }
    controller.value = TextEditingValue(
      text: before,
      selection: TextSelection.collapsed(offset: before.length),
    );
    final nextText = after.isEmpty ? null : _createTextBlock(after);
    final insertedText = block.text;
    final focusTarget = insertedText ?? nextText;
    setState(() {
      _blocks.insert(index + 1, block);
      if (nextText != null) {
        _blocks.insert(index + 2, _RichContentBlock.text(nextText));
      }
      if (focusTarget != null) _activeTextBlock = focusTarget;
    });
    focusAfterFrame(focusTarget);
  }

  _RichContentBlock _newTextContentBlock(
    _RichBlockKind kind, {
    String text = '',
  }) {
    final block = _createTextBlock(text, kind: kind);
    if (kind == _RichBlockKind.heading) block.headingLevel = 1;
    return _RichContentBlock.text(block, kind: kind);
  }

  Future<void> _insertBlockKind(_RichBlockKind kind) async {
    switch (kind) {
      case _RichBlockKind.paragraph:
      case _RichBlockKind.heading:
      case _RichBlockKind.preformatted:
      case _RichBlockKind.footer:
      case _RichBlockKind.list:
      case _RichBlockKind.blockQuotation:
      case _RichBlockKind.pullQuotation:
      case _RichBlockKind.thinking:
        _insertStructuredBlock(
          _newTextContentBlock(
            kind,
            text: kind == _RichBlockKind.list ? '- ' : '',
          ),
        );
      case _RichBlockKind.divider:
        _insertStructuredBlock(
          _RichContentBlock.generic(kind, _RichGenericDraft()),
        );
      case _RichBlockKind.mathematicalExpression:
        _insertMathBlock();
      case _RichBlockKind.anchor:
        _insertStructuredBlock(
          _RichContentBlock.generic(
            kind,
            _RichGenericDraft(primary: 'section'),
          ),
        );
      case _RichBlockKind.table:
        _insertTable();
      case _RichBlockKind.buttonRow:
        _insertStructuredBlock(
          _RichContentBlock.buttonRow(
            _RichButtonRowDraft(
              defaultLabel: AppStringKeys.richTextComposerButtonDefaultLabel
                  .l10n(context),
            ),
          ),
        );
      case _RichBlockKind.details:
        _insertStructuredBlock(
          _RichContentBlock.generic(
            kind,
            _RichGenericDraft(primary: 'Details'),
          ),
        );
      case _RichBlockKind.map:
        final start = await resolveLocationPickerStart();
        if (!mounted) return;
        _insertStructuredBlock(
          _RichContentBlock.generic(
            kind,
            _RichGenericDraft(
              primary: start.latitude.toStringAsFixed(6),
              secondary: start.longitude.toStringAsFixed(6),
              number: 16,
            ),
          ),
        );
      case _RichBlockKind.collage:
      case _RichBlockKind.slideshow:
        final group = _RichMediaGroupDraft(kind);
        _insertStructuredBlock(_RichContentBlock.mediaGroup(group));
      case _RichBlockKind.photo:
      case _RichBlockKind.video:
        await _pickSingleVisualBlock(kind);
      case _RichBlockKind.animation:
      case _RichBlockKind.audio:
      case _RichBlockKind.voiceNote:
        await _pickSingleFileBlock(kind);
      case _RichBlockKind.document:
        await _pickFiles();
    }
  }

  Future<void> _pickSingleVisualBlock(_RichBlockKind kind) async {
    final picked = await AppAssetPicker.pickDetailed(
      context,
      type: kind == _RichBlockKind.photo
          ? AppAssetPickerType.image
          : AppAssetPickerType.video,
      maxAssets: 1,
    );
    if (!mounted || picked.assets.isEmpty) return;
    final attachment = _attachmentFromAppPickedAsset(picked.assets.first);
    _insertStructuredBlock(
      _RichContentBlock.attachment(attachment, kind: kind),
    );
  }

  Future<void> _pickSingleFileBlock(_RichBlockKind kind) async {
    if (kind == _RichBlockKind.audio) {
      await _pickAudioFromSearch(single: true);
      return;
    }
    final extensions = switch (kind) {
      _RichBlockKind.animation => const ['gif', 'webm', 'mp4'],
      _RichBlockKind.voiceNote => const ['ogg', 'opus', 'm4a'],
      _ => const ['mp3', 'm4a', 'aac', 'flac', 'wav', 'ogg', 'opus'],
    };
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: extensions,
    );
    if (!mounted || result == null || result.files.single.path == null) return;
    final attachmentKind = switch (kind) {
      _RichBlockKind.animation => OutgoingAttachmentKind.animation,
      _RichBlockKind.voiceNote => OutgoingAttachmentKind.voiceNote,
      _ => OutgoingAttachmentKind.audio,
    };
    _insertStructuredBlock(
      _RichContentBlock.attachment(
        OutgoingAttachment(
          path: result.files.single.path!,
          kind: attachmentKind,
        ),
        kind: kind,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final content = SafeArea(
      top: !widget.asSheet,
      child: Column(
        children: [
          SizedBox(
            height: 56,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // The title centres on the sheet, not between the unequal
                // close and send controls.
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 104),
                  child: Text(
                    widget.title.l10n(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: c.textPrimary,
                      decoration: TextDecoration.none,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(
                    children: [
                      Visibility(
                        visible: widget.showCloseAction,
                        maintainSize: true,
                        maintainAnimation: true,
                        maintainState: true,
                        child: _headerCloseButton(c),
                      ),
                      const Spacer(),
                      _headerSubmitButton(),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _toolbar(c),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
                return ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.manual,
                  padding: EdgeInsets.only(bottom: 18 + keyboardInset),
                  itemCount: _blocks.length,
                  onReorderItem: _reorderBlock,
                  proxyDecorator: (child, index, animation) => Material(
                    type: MaterialType.transparency,
                    child: FadeTransition(
                      opacity: Tween<double>(begin: 0.82, end: 1).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                      child: child,
                    ),
                  ),
                  itemBuilder: (context, index) {
                    final block = _blocks[index];
                    return KeyedSubtree(
                      key: ValueKey(block.id),
                      child: _draggableBlock(c, constraints.maxHeight, index),
                    );
                  },
                );
              },
            ),
          ),
          if (widget.allowMedia) _attachmentDock(c),
        ],
      ),
    );
    if (!widget.asSheet) {
      return Scaffold(backgroundColor: c.background, body: content);
    }
    if (appModalUsesCenteredPresentation(MediaQuery.sizeOf(context))) {
      return ColoredBox(color: c.background, child: content);
    }
    return Align(
      alignment: Alignment.bottomCenter,
      child: Material(
        color: Colors.transparent,
        child: FractionallySizedBox(
          heightFactor: 0.94,
          widthFactor: 1,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: ColoredBox(color: c.background, child: content),
          ),
        ),
      ),
    );
  }

  void _reorderBlock(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    setState(() {
      final block = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, block);
    });
  }

  void _moveBlock(int blockId, int offset) {
    final index = _blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) return;
    final target = index + offset;
    if (target < 0 || target >= _blocks.length) return;
    setState(() {
      final block = _blocks.removeAt(index);
      _blocks.insert(target, block);
    });
  }

  void _removeBlockById(int blockId) {
    final index = _blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) return;
    setState(() {
      final removed = _blocks.removeAt(index);
      _disposeBlock(removed);
      final removedText = removed.text;
      if (_blocks.isEmpty || !_blocks.any((block) => block.text != null)) {
        final text = _createTextBlock('');
        final insertionIndex = index.clamp(0, _blocks.length);
        _blocks.insert(insertionIndex, _RichContentBlock.text(text));
        _activeTextBlock = text;
      } else if (removedText != null &&
          identical(removedText, _activeTextBlock)) {
        // Keep the inline format row bound to a live controller.
        for (final block in _blocks) {
          final text = block.text;
          if (text != null) {
            _activeTextBlock = text;
            break;
          }
        }
      }
    });
  }

  Future<void> _showBlockActions(Offset anchor, int blockId) async {
    final index = _blocks.indexWhere((block) => block.id == blockId);
    if (index < 0) return;
    final action = await showGeneralDialog<_RichBlockAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, _) => _RichBlockActionMenu(
        anchor: anchor,
        canMoveUp: index > 0,
        canMoveDown: index < _blocks.length - 1,
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case _RichBlockAction.moveUp:
        _moveBlock(blockId, -1);
      case _RichBlockAction.moveDown:
        _moveBlock(blockId, 1);
      case _RichBlockAction.delete:
        _removeBlockById(blockId);
    }
  }

  Widget _draggableBlock(AppColors c, double availableHeight, int index) {
    final blockId = _blocks[index].id;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReorderableDragStartListener(
          index: index,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (details) =>
                unawaited(_showBlockActions(details.globalPosition, blockId)),
            onLongPressStart: (details) =>
                unawaited(_showBlockActions(details.globalPosition, blockId)),
            child: Container(
              width: 30,
              constraints: const BoxConstraints(minHeight: 40),
              alignment: Alignment.topCenter,
              padding: const EdgeInsets.only(top: 11),
              child: AppIcon(
                HeroAppIcons.ellipsis,
                size: 17,
                color: c.textTertiary,
              ),
            ),
          ),
        ),
        Expanded(child: _contentBlock(c, availableHeight, index)),
      ],
    );
  }

  Widget _contentBlock(AppColors c, double availableHeight, int index) {
    final block = _blocks[index];
    final text = block.text;
    if (text != null) {
      return _textEditor(c, availableHeight, text, index);
    }
    final attachment = block.attachment;
    if (attachment != null) {
      return _inlineAttachmentBlock(c, index, attachment);
    }
    final math = block.math;
    if (math != null) {
      return _mathEditor(c, index, math);
    }
    final table = block.table;
    if (table == null) {
      final buttonRow = block.buttonRow;
      if (buttonRow != null) {
        return _buttonRowEditor(c, index, buttonRow);
      }
      final group = block.mediaGroup;
      if (group != null) return _mediaGroupEditor(c, index, group);
      final generic = block.generic;
      if (generic != null || block.kind == _RichBlockKind.divider) {
        return _genericBlockEditor(c, index, block);
      }
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
      child: _tableEditor(c, table),
    );
  }

  Widget _textEditor(
    AppColors c,
    double availableHeight,
    _RichTextBlock block,
    int index,
  ) {
    final baseStyle = TextStyle(
      fontSize: switch (block.kind) {
        _RichBlockKind.heading => switch (block.headingLevel.clamp(1, 6)) {
          1 => 24,
          2 => 22,
          3 => 20,
          4 => 18,
          5 => 16,
          _ => 15,
        },
        _RichBlockKind.footer => 14,
        _ => 16,
      },
      height: 1.3,
      color: block.kind == _RichBlockKind.footer
          ? c.textSecondary
          : c.textPrimary,
      fontStyle: block.kind == _RichBlockKind.pullQuotation
          ? FontStyle.italic
          : null,
      fontWeight: block.kind == _RichBlockKind.heading ? FontWeight.w600 : null,
    );
    final field = TextField(
      controller: block.controller,
      focusNode: block.focusNode,
      autofocus: block == _blocks.first.text,
      minLines: 1,
      maxLines: null,
      textAlign: block.kind == _RichBlockKind.pullQuotation
          ? TextAlign.center
          : TextAlign.start,
      textAlignVertical: TextAlignVertical.top,
      contextMenuBuilder: (context, editableTextState) =>
          _richTextContextMenu(context, editableTextState, index),
      style: block.kind == _RichBlockKind.preformatted
          ? context.watch<ThemeController>().codeTextStyle(baseStyle)
          : baseStyle,
      decoration: InputDecoration(
        contentPadding: EdgeInsets.fromLTRB(
          block.kind == _RichBlockKind.blockQuotation ? 10 : 4,
          8,
          block.kind == _RichBlockKind.blockQuotation ? 34 : 12,
          6,
        ),
        border: InputBorder.none,
        hintText: block.kind == _RichBlockKind.paragraph && !_hasAnyText
            ? widget.hintText.l10n(context)
            : block.kind.labelKey.l10n(context),
        hintStyle: TextStyle(color: c.textTertiary),
      ),
    );
    final editor = ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 38,
        maxHeight: math.min(260, availableHeight),
      ),
      child: field,
    );
    final decoratedEditor = switch (block.kind) {
      _RichBlockKind.blockQuotation => Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: AppTheme.brand.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(width: 4, color: AppTheme.brand),
                Expanded(
                  child: Stack(
                    children: [
                      editor,
                      Positioned(
                        right: 8,
                        top: 3,
                        child: IgnorePointer(
                          child: Text(
                            '”',
                            style: TextStyle(
                              color: AppTheme.brand,
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              height: 1,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      _RichBlockKind.preformatted => Padding(
        padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: c.searchFill,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: c.divider, width: 0.5),
          ),
          child: editor,
        ),
      ),
      _RichBlockKind.pullQuotation => Padding(
        padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
        child: DecoratedBox(
          decoration: BoxDecoration(
            border: Border.symmetric(
              horizontal: BorderSide(color: c.divider, width: 0.5),
            ),
          ),
          child: editor,
        ),
      ),
      _ => editor,
    };
    if (block.kind != _RichBlockKind.heading) return decoratedEditor;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [_headingLevelSelector(c, block), decoratedEditor],
    );
  }

  Widget _headingLevelSelector(AppColors c, _RichTextBlock block) {
    return SizedBox(
      key: const ValueKey('rich-heading-level-selector'),
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(4, 3, 12, 3),
        itemCount: 6,
        separatorBuilder: (_, _) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final level = index + 1;
          final selected = block.headingLevel == level;
          return GestureDetector(
            key: ValueKey('rich-heading-level-$level'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (block.headingLevel == level) return;
              setState(() => block.headingLevel = level);
              block.focusNode.requestFocus();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOutCubic,
              width: 42,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.brand.withValues(alpha: 0.14)
                    : c.searchFill,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: selected ? AppTheme.brand : c.divider,
                  width: selected ? 1 : 0.5,
                ),
              ),
              child: Text(
                'H$level',
                style: AppTextStyle.caption(
                  selected ? AppTheme.brand : c.textSecondary,
                ).copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _richTextContextMenu(
    BuildContext context,
    EditableTextState editableTextState,
    int blockIndex,
  ) {
    ContextMenuButtonItem? paste;
    final items = <ContextMenuButtonItem>[];
    for (final item in editableTextState.contextMenuButtonItems) {
      if (item.type == ContextMenuButtonType.paste) {
        paste = item;
      } else {
        items.add(item);
      }
    }
    final copyIndex = items.indexWhere(
      (item) => item.type == ContextMenuButtonType.copy,
    );
    var insertAt = copyIndex < 0 ? 0 : copyIndex + 1;
    if (paste != null) items.insert(insertAt++, paste);
    final selection = _blocks[blockIndex].text?.controller.selection;
    if (selection?.isValid == true && selection?.isCollapsed == false) {
      items.insert(
        insertAt++,
        ContextMenuButtonItem(
          label: AppStringKeys.composerFormat.l10n(context),
          onPressed: () => unawaited(
            _showRichInlineFormatMenu(editableTextState, blockIndex),
          ),
        ),
      );
    }
    items.insert(
      insertAt,
      ContextMenuButtonItem(
        label: AppStringKeys.richTextComposerInsert.l10n(context),
        onPressed: () =>
            unawaited(_showRichBlockInsertMenu(editableTextState, blockIndex)),
      ),
    );
    return AppTextSelectionToolbar.fromButtonItems(
      context: context,
      anchors: editableTextState.contextMenuAnchors,
      items: items,
    );
  }

  Future<void> _showRichInlineFormatMenu(
    EditableTextState editableTextState,
    int blockIndex,
  ) async {
    if (blockIndex < 0 || blockIndex >= _blocks.length) return;
    final textBlock = _blocks[blockIndex].text;
    if (textBlock == null) return;
    _activeTextBlock = textBlock;
    final selection = textBlock.controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final anchor = editableTextState.contextMenuAnchors.primaryAnchor;
    final appliedFormats = _RichInlineFormatAction.values
        .where(
          (action) => textBlock.controller.selectionHasFormat(
            action.selectionEntityType,
          ),
        )
        .toSet();
    editableTextState.hideToolbar();
    final action = await showGeneralDialog<_RichInlineFormatAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, _) =>
          _RichInlineFormatMenu(anchor: anchor, appliedFormats: appliedFormats),
    );
    if (!mounted || action == null) return;
    await _applyInlineFormatAction(
      action,
      textBlock.controller,
      textBlock.focusNode,
      start,
      end,
    );
  }

  /// Applies [action] over `start..end` of [controller], asking for the target
  /// URL first when the action is a link. The selection menu and the toolbar
  /// row share this so both act through one implementation.
  Future<void> _applyInlineFormatAction(
    _RichInlineFormatAction action,
    EmojiTextEditingController controller,
    FocusNode focusNode,
    int start,
    int end,
  ) async {
    if (start < 0 || end > controller.text.length || start >= end) return;
    controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    if (action == _RichInlineFormatAction.link) {
      final url = await _showRichValueDialog(
        AppStringKeys.composerFormatLink,
        AppStringKeys.composerFormatLinkPlaceholder,
      );
      if (!mounted || url == null || url.trim().isEmpty) return;
      final parsed = Uri.tryParse(url.trim());
      controller.applyEntityFormat(start, end, {
        '@type': 'textEntityTypeTextUrl',
        'url': parsed?.hasScheme == true ? url.trim() : 'https://${url.trim()}',
      });
    } else {
      controller.toggleFormat(action.entityType);
    }
    controller.selection = TextSelection(baseOffset: start, extentOffset: end);
    focusNode.requestFocus();
  }

  Future<void> _showRichBlockInsertMenu(
    EditableTextState editableTextState,
    int blockIndex,
  ) async {
    if (blockIndex < 0 || blockIndex >= _blocks.length) return;
    final textBlock = _blocks[blockIndex].text;
    if (textBlock != null) _activeTextBlock = textBlock;
    final anchor = editableTextState.contextMenuAnchors.primaryAnchor;
    editableTextState.hideToolbar();
    await _showRichBlockInsertMenuAt(anchor);
  }

  Future<void> _showRichBlockInsertMenuAt(Offset anchor) async {
    final kind = await showGeneralDialog<_RichBlockKind>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.black.withValues(alpha: 0.18),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, _) =>
          _RichBlockInsertMenu(anchor: anchor),
    );
    if (!mounted || kind == null) return;
    await _insertBlockKind(kind);
  }

  Future<String?> _showRichValueDialog(String title, String hint) {
    return showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.black.withValues(alpha: 0.36),
      transitionDuration: const Duration(milliseconds: 160),
      pageBuilder: (dialogContext, _, _) =>
          _RichValueDialog(title: title, hint: hint),
    );
  }

  bool get _hasAnyText => _blocks.any(
    (block) => block.text?.controller.text.trim().isNotEmpty ?? false,
  );

  Widget _buttonRowEditor(
    AppColors c,
    int blockIndex,
    _RichButtonRowDraft row,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 3, 12, 3),
      child: Container(
        key: const ValueKey('rich-button-row-editor'),
        padding: const EdgeInsets.fromLTRB(10, 9, 8, 10),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppStringKeys.richTextBlockButtonRow.l10n(context),
                    style: AppTextStyle.callout(
                      c.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ),
                for (final alignment in _RichButtonAlignment.values)
                  _buttonAlignmentControl(c, row, alignment),
                const SizedBox(width: 2),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.trash,
                  label: AppStringKeys.richTextComposerRemoveBlock.l10n(
                    context,
                  ),
                  destructive: true,
                  onTap: () => _removeStructuredBlock(blockIndex),
                ),
              ],
            ),
            const SizedBox(height: 8),
            for (var index = 0; index < row.buttons.length; index++) ...[
              if (index > 0) const SizedBox(height: 8),
              _buttonDraftEditor(c, row, index),
            ],
            const SizedBox(height: 8),
            GestureDetector(
              key: const ValueKey('rich-button-add'),
              behavior: HitTestBehavior.opaque,
              onTap: row.buttons.length >= 8
                  ? null
                  : () {
                      setState(() {
                        row.buttons.add(_RichButtonDraft());
                      });
                    },
              child: Container(
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: AppTheme.brand.withValues(alpha: 0.24),
                    width: 0.5,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AppIcon(
                      HeroAppIcons.plus,
                      size: 16,
                      color: row.buttons.length >= 8
                          ? c.textTertiary
                          : AppTheme.brand,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      AppStringKeys.richTextComposerButtonAdd.l10n(context),
                      style: AppTextStyle.caption(
                        row.buttons.length >= 8
                            ? c.textTertiary
                            : AppTheme.brand,
                      ).copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buttonAlignmentControl(
    AppColors c,
    _RichButtonRowDraft row,
    _RichButtonAlignment alignment,
  ) {
    final selected = row.alignment == alignment;
    return Tooltip(
      message: alignment.labelKey.l10n(context),
      excludeFromSemantics: true,
      child: GestureDetector(
        key: ValueKey('rich-button-align-${alignment.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => row.alignment = alignment),
        child: Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.brand.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: AppIcon(
            alignment.icon,
            size: 16,
            color: selected ? AppTheme.brand : c.textTertiary,
          ),
        ),
      ),
    );
  }

  Widget _buttonDraftEditor(AppColors c, _RichButtonRowDraft row, int index) {
    final button = row.buttons[index];
    return Container(
      key: ValueKey('rich-button-item-$index'),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: ValueKey('rich-button-label-$index'),
            controller: button.label,
            onChanged: (_) => setState(() {}),
            style: AppTextStyle.callout(c.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              hintText: AppStringKeys.richTextComposerButtonLabel.l10n(context),
              hintStyle: AppTextStyle.callout(c.textTertiary),
            ),
          ),
          Container(height: 0.5, color: c.divider),
          TextField(
            key: ValueKey('rich-button-url-$index'),
            controller: button.url,
            keyboardType: TextInputType.url,
            autocorrect: false,
            enableSuggestions: false,
            onChanged: (_) => setState(() {}),
            style: AppTextStyle.callout(c.textPrimary),
            decoration: InputDecoration(
              isDense: true,
              border: InputBorder.none,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 8,
              ),
              hintText: AppStringKeys.richTextComposerButtonUrl.l10n(context),
              hintStyle: AppTextStyle.callout(c.textTertiary),
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              Expanded(
                child: Wrap(
                  spacing: 5,
                  runSpacing: 5,
                  children: [
                    for (final style in _RichButtonStyle.values)
                      _buttonStyleChip(c, button, style),
                  ],
                ),
              ),
              _miniIconButton(
                c,
                icon: HeroAppIcons.trash,
                label: AppStringKeys.richTextComposerButtonRemove.l10n(context),
                destructive: true,
                onTap: row.buttons.length <= 1
                    ? null
                    : () {
                        setState(() {
                          row.buttons.removeAt(index).dispose();
                        });
                      },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buttonStyleChip(
    AppColors c,
    _RichButtonDraft button,
    _RichButtonStyle style,
  ) {
    final selected = button.style == style;
    final accent = switch (style) {
      _RichButtonStyle.standard => c.textSecondary,
      _RichButtonStyle.primary => AppTheme.brand,
      _RichButtonStyle.success => const Color(0xFF22A559),
      _RichButtonStyle.danger => const Color(0xFFE94B4B),
    };
    return GestureDetector(
      key: ValueKey('rich-button-style-${style.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => button.style = style),
      child: Container(
        constraints: const BoxConstraints(minHeight: 27),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? accent : accent.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: selected ? accent : accent.withValues(alpha: 0.24),
            width: 0.5,
          ),
        ),
        child: Text(
          style.labelKey.l10n(context),
          style: AppTextStyle.caption(
            selected ? Colors.white : accent,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _genericBlockEditor(AppColors c, int index, _RichContentBlock block) {
    if (block.kind == _RichBlockKind.map) {
      return _mapBlockEditor(c, index, block.generic!);
    }
    if (block.kind == _RichBlockKind.divider) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(4, 8, 12, 8),
        child: Row(
          children: [
            Expanded(child: Divider(color: c.divider)),
            _miniIconButton(
              c,
              icon: HeroAppIcons.trash,
              label: AppStringKeys.richTextComposerRemoveBlock.l10n(context),
              destructive: true,
              onTap: () => _removeStructuredBlock(index),
            ),
          ],
        ),
      );
    }
    final draft = block.generic!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
      child: Container(
        padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    block.kind.labelKey.l10n(context),
                    style: AppTextStyle.callout(
                      c.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.trash,
                  label: AppStringKeys.richTextComposerRemoveBlock.l10n(
                    context,
                  ),
                  destructive: true,
                  onTap: () => _removeStructuredBlock(index),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (block.kind == _RichBlockKind.anchor)
              _compactBlockField(
                c,
                draft.primary,
                AppStringKeys.richTextComposerAnchorName,
              ),
            if (block.kind == _RichBlockKind.details) ...[
              _compactBlockField(
                c,
                draft.primary,
                AppStringKeys.richTextComposerDetailsSummary,
              ),
              const SizedBox(height: 6),
              _compactBlockField(
                c,
                draft.secondary,
                AppStringKeys.richTextComposerDetailsContent,
                maxLines: 4,
              ),
              const SizedBox(height: 6),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => draft.enabled = !draft.enabled),
                child: Row(
                  children: [
                    AppIcon(
                      draft.enabled
                          ? HeroAppIcons.circleCheck
                          : HeroAppIcons.circle,
                      size: 19,
                      color: draft.enabled ? AppTheme.brand : c.textTertiary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      AppStringKeys.richTextComposerDetailsOpen.l10n(context),
                      style: AppTextStyle.callout(c.textPrimary),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _editMapBlock(int index, _RichGenericDraft draft) async {
    final latitude =
        double.tryParse(draft.primary.text.trim()) ??
        defaultLocationPickerCenter.latitude;
    final longitude =
        double.tryParse(draft.secondary.text.trim()) ??
        defaultLocationPickerCenter.longitude;
    final picked = await Navigator.of(context).push<LocationPickerResult>(
      MaterialPageRoute(
        builder: (_) => LocationPickerView(
          initial: LatLng(latitude, longitude),
          initialZoom: draft.number.toDouble(),
          returnCamera: true,
        ),
      ),
    );
    if (!mounted || picked == null || index >= _blocks.length) return;
    setState(() {
      draft.primary.text = picked.center.latitude.toStringAsFixed(6);
      draft.secondary.text = picked.center.longitude.toStringAsFixed(6);
      draft.number = picked.zoom.round().clamp(13, 20);
    });
  }

  Widget _mapBlockEditor(AppColors c, int index, _RichGenericDraft draft) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => unawaited(_editMapBlock(index, draft)),
        child: Container(
          constraints: const BoxConstraints(minHeight: 68),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: c.card,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: c.divider, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.brand.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(AppRadius.control),
                ),
                child: AppIcon(
                  HeroAppIcons.locationPin,
                  size: 22,
                  color: AppTheme.brand,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _RichBlockKind.map.labelKey.l10n(context),
                      style: AppTextStyle.callout(
                        c.textPrimary,
                        weight: AppTextWeight.semibold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${draft.primary.text}, ${draft.secondary.text} · '
                      '${AppStringKeys.richTextComposerMapZoom.l10n(context)} ${draft.number}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyle.caption(c.textSecondary),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              AppIcon(
                HeroAppIcons.chevronRight,
                size: 16,
                color: c.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _compactBlockField(
    AppColors c,
    TextEditingController controller,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboardType,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        keyboardType: keyboardType,
        onChanged: (_) => setState(() {}),
        style: AppTextStyle.callout(c.textPrimary),
        decoration: InputDecoration(
          isDense: true,
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 9,
          ),
          hintText: hint.l10n(context),
          hintStyle: AppTextStyle.callout(c.textTertiary),
        ),
      ),
    );
  }

  Widget _mediaGroupEditor(AppColors c, int index, _RichMediaGroupDraft group) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 2, 12, 2),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.kind.labelKey.l10n(context),
                    style: AppTextStyle.callout(
                      c.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ),
                _textMiniButton(
                  c,
                  '+',
                  _attachmentCount >= _maxAttachments
                      ? null
                      : () => unawaited(_pickMediaForGroup(index)),
                ),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.trash,
                  label: AppStringKeys.richTextComposerRemoveBlock.l10n(
                    context,
                  ),
                  destructive: true,
                  onTap: () => _removeStructuredBlock(index),
                ),
              ],
            ),
            if (group.items.isNotEmpty) ...[
              const SizedBox(height: 6),
              SizedBox(
                height: 74,
                child: ReorderableListView.builder(
                  scrollDirection: Axis.horizontal,
                  buildDefaultDragHandles: false,
                  itemCount: group.items.length,
                  onReorderItem: (oldIndex, newIndex) {
                    setState(() {
                      final item = group.items.removeAt(oldIndex);
                      group.items.insert(newIndex, item);
                    });
                  },
                  itemBuilder: (context, mediaIndex) {
                    final item = group.items[mediaIndex];
                    return ReorderableDragStartListener(
                      key: ValueKey('${item.path}-$mediaIndex'),
                      index: mediaIndex,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.md),
                          child: _attachmentPreview(
                            c,
                            item,
                            width: 74,
                            height: 74,
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 6),
            _compactBlockField(
              c,
              group.caption,
              AppStringKeys.imageEditCaptionInputPlaceholder,
              maxLines: 2,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMediaForGroup(int blockIndex) async {
    if (blockIndex < 0 || blockIndex >= _blocks.length) return;
    final group = _blocks[blockIndex].mediaGroup;
    if (group == null) return;
    final remaining = _maxAttachments - _attachmentCount;
    if (remaining <= 0) return;
    final picked = await AppAssetPicker.pickDetailed(
      context,
      type: AppAssetPickerType.imageAndVideo,
      maxAssets: remaining,
    );
    if (!mounted || picked.assets.isEmpty) return;
    setState(() {
      group.items.addAll(picked.assets.map(_attachmentFromAppPickedAsset));
    });
  }

  Widget _mathEditor(AppColors c, int index, _RichMathDraft math) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: c.divider),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  'LaTeX',
                  style: AppTextStyle.callout(
                    c.textPrimary,
                    weight: AppTextWeight.semibold,
                  ),
                ),
                const Spacer(),
                _miniIconButton(
                  c,
                  icon: HeroAppIcons.trash,
                  label: AppStringKeys.richTextComposerRemoveTable.l10n(
                    context,
                  ),
                  destructive: true,
                  onTap: () => _removeStructuredBlock(index),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TextField(
              controller: math.controller,
              maxLines: 3,
              onChanged: (_) => setState(() {}),
              style: AppTextStyle.callout(c.textPrimary),
              decoration: InputDecoration(
                filled: true,
                fillColor: c.searchFill,
                border: InputBorder.none,
                contentPadding: const EdgeInsets.all(10),
              ),
            ),
            if (math.controller.text.trim().isNotEmpty) ...[
              const SizedBox(height: 12),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Math.tex(
                  math.controller.text,
                  textStyle: TextStyle(fontSize: 18, color: c.textPrimary),
                  onErrorFallback: (_) => Text(
                    math.controller.text,
                    style: TextStyle(color: c.textSecondary),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _removeStructuredBlock(int index) {
    if (index < 0 || index >= _blocks.length) return;
    setState(() {
      final removed = _blocks.removeAt(index);
      _disposeBlock(removed);
    });
  }

  void _removeTable(_RichTableDraft table) {
    final index = _blocks.indexWhere((block) => block.table == table);
    if (index < 0) return;
    setState(() {
      _blocks.removeAt(index).table?.dispose();
      if (!_blocks.any((block) => block.text != null)) {
        final text = _createTextBlock('');
        _blocks.add(_RichContentBlock.text(text));
        _activeTextBlock = text;
      }
    });
  }

  Widget _tableEditor(AppColors c, _RichTableDraft table) {
    final tableHeight = (table.rowCount * 54.0 + 18).clamp(102.0, 300.0);
    final activeStyle = table.activeCellStyle;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final titleStyle = AppTextStyle.callout(
                  c.textPrimary,
                  weight: AppTextWeight.semibold,
                );
                final titleText = table.title.text.isEmpty
                    ? AppStringKeys.richTextComposerInsertTable.l10n(context)
                    : table.title.text;
                final titlePainter = TextPainter(
                  text: TextSpan(text: titleText, style: titleStyle),
                  maxLines: 1,
                  textDirection: Directionality.of(context),
                  textScaler: MediaQuery.textScalerOf(context),
                )..layout();
                const fixedHeaderWidth = 26.0 + 4 + 8 + 212;
                final fitsOneRow =
                    fixedHeaderWidth + titlePainter.width + 4 <=
                    constraints.maxWidth;
                final titleRow = <Widget>[
                  _tableLeadingIcon(c),
                  const SizedBox(width: 4),
                  Expanded(child: _tableTitleField(table, titleStyle)),
                ];
                final controls = TextFieldTapRegion(
                  child: _tableControlRow(c, table, activeStyle),
                );
                if (fitsOneRow) {
                  return Row(
                    children: [...titleRow, const SizedBox(width: 8), controls],
                  );
                }
                return Column(
                  children: [
                    Row(children: titleRow),
                    const SizedBox(height: 8),
                    Align(alignment: Alignment.centerRight, child: controls),
                  ],
                );
              },
            ),
          ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: tableHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Column(
                    children: [
                      for (var row = 0; row < table.rowCount; row++)
                        Row(
                          children: [
                            for (
                              var column = 0;
                              column < table.columnCount;
                              column++
                            )
                              _tableCell(c, table, row, column),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _tableLeadingIcon(AppColors c) {
    return SizedBox(
      width: 26,
      height: 30,
      child: Center(
        child: AppIcon(HeroAppIcons.tableCells, size: 18, color: c.textPrimary),
      ),
    );
  }

  Widget _tableTitleField(_RichTableDraft table, TextStyle titleStyle) {
    return TextField(
      key: const ValueKey('rich-table-title'),
      controller: table.title,
      textInputAction: TextInputAction.done,
      onChanged: (_) => setState(() {}),
      style: titleStyle,
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        hintText: AppStringKeys.richTextComposerInsertTable.l10n(context),
      ),
    );
  }

  Widget _tableControlRow(
    AppColors c,
    _RichTableDraft table,
    _RichTableCellStyle? activeStyle,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _tableControlButton(
          c,
          key: const ValueKey('rich-table-add-row'),
          text: '+R',
          label: AppStringKeys.richTextComposerAddRow.l10n(context),
          onTap: () => setState(table.addRow),
        ),
        const SizedBox(width: 4),
        _tableControlButton(
          c,
          key: const ValueKey('rich-table-add-column'),
          text: '+C',
          label: AppStringKeys.richTextComposerAddColumn.l10n(context),
          onTap: table.columnCount >= _RichTableDraft.maxColumns
              ? null
              : () => setState(table.addColumn),
        ),
        const SizedBox(width: 4),
        _tableControlButton(
          c,
          key: const ValueKey('rich-table-toggle-header'),
          icon: HeroAppIcons.hashtag,
          label: AppStringKeys.richTextTableHeader.l10n(context),
          selected: activeStyle?.isHeader == true,
          onTap: activeStyle == null
              ? null
              : () => _toggleActiveTableHeader(table),
        ),
        const SizedBox(width: 4),
        _tableControlButton(
          c,
          key: const ValueKey('rich-table-align-horizontal'),
          icon: switch (activeStyle?.horizontal) {
            _RichCellHorizontalAlignment.center => HeroAppIcons.alignCenter,
            _RichCellHorizontalAlignment.right => HeroAppIcons.alignRight,
            _ => HeroAppIcons.alignLeft,
          },
          label: switch (activeStyle?.horizontal) {
            _RichCellHorizontalAlignment.center =>
              AppStringKeys.richTextTableAlignCenter.l10n(context),
            _RichCellHorizontalAlignment.right =>
              AppStringKeys.richTextTableAlignRight.l10n(context),
            _ => AppStringKeys.richTextTableAlignLeft.l10n(context),
          },
          selected: activeStyle != null,
          onTap: activeStyle == null
              ? null
              : () => _cycleActiveTableHorizontalAlignment(table),
        ),
        const SizedBox(width: 4),
        _tableControlButton(
          c,
          key: const ValueKey('rich-table-align-vertical'),
          icon: switch (activeStyle?.vertical) {
            _RichCellVerticalAlignment.middle => HeroAppIcons.arrowsUpDown,
            _RichCellVerticalAlignment.bottom => HeroAppIcons.alignBottom,
            _ => HeroAppIcons.alignTop,
          },
          label: switch (activeStyle?.vertical) {
            _RichCellVerticalAlignment.middle =>
              AppStringKeys.richTextTableAlignMiddle.l10n(context),
            _RichCellVerticalAlignment.bottom =>
              AppStringKeys.richTextTableAlignBottom.l10n(context),
            _ => AppStringKeys.richTextTableAlignTop.l10n(context),
          },
          selected: activeStyle != null,
          onTap: activeStyle == null
              ? null
              : () => _cycleActiveTableVerticalAlignment(table),
        ),
        const SizedBox(width: 4),
        _tableControlButton(
          c,
          key: const ValueKey('rich-table-toggle-borderless'),
          icon: HeroAppIcons.tableCells,
          label:
              (table.bordered
                      ? AppStringKeys.richTextTableBordered
                      : AppStringKeys.richTextTableBorderless)
                  .l10n(context),
          selected: !table.bordered,
          onTap: () => _toggleTableBorderless(table),
        ),
      ],
    );
  }

  Widget _tableCell(AppColors c, _RichTableDraft table, int row, int column) {
    final cellStyle = table.styles[row][column];
    final isHeader = cellStyle.isHeader;
    final stripedFill = table.striped && row.isOdd;
    final borderSide = table.bordered
        ? BorderSide(color: c.divider)
        : BorderSide.none;
    return Container(
      width: 132,
      height: 54,
      decoration: BoxDecoration(
        color: isHeader
            ? AppTheme.brand.withValues(alpha: 0.1)
            : stripedFill
            ? c.searchFill
            : c.background,
        border: Border(
          right: borderSide,
          bottom: borderSide,
          left: column == 0 ? borderSide : BorderSide.none,
          top: row == 0 ? borderSide : BorderSide.none,
        ),
      ),
      child: Focus(
        onFocusChange: (hasFocus) {
          if (hasFocus) _activateTableCell(table, row, column);
        },
        child: TextField(
          key: ValueKey('rich-table-cell-$row-$column'),
          controller: table.cells[row][column],
          keyboardType: TextInputType.multiline,
          textInputAction: TextInputAction.newline,
          minLines: 1,
          maxLines: null,
          onTap: () => _activateTableCell(table, row, column),
          textAlign: switch (cellStyle.horizontal) {
            _RichCellHorizontalAlignment.left => TextAlign.left,
            _RichCellHorizontalAlignment.center => TextAlign.center,
            _RichCellHorizontalAlignment.right => TextAlign.right,
          },
          textAlignVertical: switch (cellStyle.vertical) {
            _RichCellVerticalAlignment.top => TextAlignVertical.top,
            _RichCellVerticalAlignment.middle => TextAlignVertical.center,
            _RichCellVerticalAlignment.bottom => TextAlignVertical.bottom,
          },
          contextMenuBuilder: (context, editableTextState) {
            final controller = table.cells[row][column];
            final items = <ContextMenuButtonItem>[
              ...editableTextState.contextMenuButtonItems,
            ];
            final selection = controller.selection;
            var customActionIndex = items.indexWhere(
              (item) =>
                  item.type == ContextMenuButtonType.lookUp ||
                  item.type == ContextMenuButtonType.searchWeb,
            );
            if (customActionIndex < 0) {
              final pasteIndex = items.lastIndexWhere(
                (item) => item.type == ContextMenuButtonType.paste,
              );
              customActionIndex = pasteIndex >= 0
                  ? pasteIndex + 1
                  : items.length;
            }
            if (selection.isValid && !selection.isCollapsed) {
              items.insert(
                customActionIndex++,
                ContextMenuButtonItem(
                  label: AppStringKeys.composerFormat.l10n(context),
                  onPressed: () => unawaited(
                    _showTableCellFormatMenu(editableTextState, controller),
                  ),
                ),
              );
            }
            items.insert(
              customActionIndex,
              ContextMenuButtonItem(
                label: AppStringKeys.richTextTableChange.l10n(context),
                onPressed: () => unawaited(
                  _showTableActionsMenu(editableTextState, table, row, column),
                ),
              ),
            );
            return AppTextSelectionToolbar.fromButtonItems(
              context: context,
              anchors: editableTextState.contextMenuAnchors,
              items: items,
            );
          },
          style: AppTextStyle.callout(
            c.textPrimary,
            weight: isHeader ? AppTextWeight.semibold : AppTextWeight.regular,
          ),
          decoration: const InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          ),
        ),
      ),
    );
  }

  void _activateTableCell(_RichTableDraft table, int row, int column) {
    if (table.activeRow == row && table.activeColumn == column) return;
    setState(() => table.activateCell(row, column));
  }

  void _toggleActiveTableHeader(_RichTableDraft table) {
    final style = table.activeCellStyle;
    if (style == null) return;
    setState(() => style.isHeader = !style.isHeader);
  }

  void _cycleActiveTableHorizontalAlignment(_RichTableDraft table) {
    final style = table.activeCellStyle;
    if (style == null) return;
    setState(() {
      style.horizontal = switch (style.horizontal) {
        _RichCellHorizontalAlignment.left =>
          _RichCellHorizontalAlignment.center,
        _RichCellHorizontalAlignment.center =>
          _RichCellHorizontalAlignment.right,
        _RichCellHorizontalAlignment.right => _RichCellHorizontalAlignment.left,
      };
    });
  }

  void _cycleActiveTableVerticalAlignment(_RichTableDraft table) {
    final style = table.activeCellStyle;
    if (style == null) return;
    setState(() {
      style.vertical = switch (style.vertical) {
        _RichCellVerticalAlignment.top => _RichCellVerticalAlignment.middle,
        _RichCellVerticalAlignment.middle => _RichCellVerticalAlignment.bottom,
        _RichCellVerticalAlignment.bottom => _RichCellVerticalAlignment.top,
      };
    });
  }

  Widget _tableControlButton(
    AppColors c, {
    required Key key,
    required String label,
    required VoidCallback? onTap,
    AppIconData? icon,
    String? text,
    bool selected = false,
  }) {
    assert((icon == null) != (text == null));
    final enabled = onTap != null;
    final foreground = !enabled
        ? c.textTertiary.withValues(alpha: 0.48)
        : selected
        ? AppTheme.brand
        : c.textSecondary;
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: label,
      child: GestureDetector(
        key: key,
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 32,
          height: 28,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.brand.withValues(alpha: 0.14)
                : c.searchFill,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(
              color: selected
                  ? AppTheme.brand.withValues(alpha: 0.54)
                  : c.divider,
            ),
          ),
          child: icon != null
              ? AppIcon(icon, size: 16, color: foreground)
              : Text(
                  text!,
                  style: AppTextStyle.caption(
                    foreground,
                  ).copyWith(fontWeight: FontWeight.w600),
                ),
        ),
      ),
    );
  }

  Future<void> _showTableCellFormatMenu(
    EditableTextState editableTextState,
    EmojiTextEditingController controller,
  ) async {
    final selection = controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    final anchor = editableTextState.contextMenuAnchors.primaryAnchor;
    final focusNode = editableTextState.widget.focusNode;
    final appliedFormats = _RichInlineFormatAction.values
        .where(
          (action) => controller.selectionHasFormat(action.selectionEntityType),
        )
        .toSet();
    editableTextState.hideToolbar();
    final action = await showGeneralDialog<_RichInlineFormatAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, _) =>
          _RichInlineFormatMenu(anchor: anchor, appliedFormats: appliedFormats),
    );
    if (!mounted || action == null) return;
    await _applyInlineFormatAction(action, controller, focusNode, start, end);
  }

  Future<void> _showTableActionsMenu(
    EditableTextState editableTextState,
    _RichTableDraft table,
    int row,
    int column,
  ) async {
    final anchor = editableTextState.contextMenuAnchors.primaryAnchor;
    editableTextState.hideToolbar();
    final action = await showGeneralDialog<_RichTableMenuAction>(
      context: context,
      barrierDismissible: true,
      barrierLabel: AppStringKeys.countryPickerCancel.l10n(context),
      barrierColor: Colors.transparent,
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (dialogContext, _, _) => _RichTableActionsMenu(
        anchor: anchor,
        canAddColumn: table.columnCount < _RichTableDraft.maxColumns,
        canRemoveRow: table.rowCount > 1,
        canRemoveColumn: table.columnCount > 1,
        onTableAction: (action) => Navigator.of(dialogContext).pop(action),
      ),
    );
    if (!mounted || action == null) return;
    _applyTableMenuAction(action, editableTextState, table, row, column);
  }

  void _applyTableMenuAction(
    _RichTableMenuAction action,
    EditableTextState editableTextState,
    _RichTableDraft table,
    int row,
    int column,
  ) {
    editableTextState.hideToolbar();
    switch (action) {
      case _RichTableMenuAction.addRowAbove:
        setState(() => table.insertRow(row));
      case _RichTableMenuAction.addRowBelow:
        setState(() => table.insertRow(row + 1));
      case _RichTableMenuAction.addColumnLeft:
        setState(() => table.insertColumn(column));
      case _RichTableMenuAction.addColumnRight:
        setState(() => table.insertColumn(column + 1));
      case _RichTableMenuAction.removeRow:
        setState(() => table.removeRowAt(row));
      case _RichTableMenuAction.removeColumn:
        setState(() => table.removeColumnAt(column));
      case _RichTableMenuAction.removeTable:
        _removeTable(table);
    }
  }

  void _toggleTableBorderless(_RichTableDraft table) {
    setState(() {
      table.bordered = !table.bordered;
      table.striped = table.bordered;
    });
  }

  Widget _miniIconButton(
    AppColors c, {
    required AppIconData icon,
    required String label,
    required VoidCallback? onTap,
    bool destructive = false,
  }) {
    final enabled = onTap != null;
    final color = destructive
        ? const Color(0xFFFF5A52)
        : enabled
        ? c.textPrimary
        : c.textTertiary.withValues(alpha: 0.48);
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: AppIcon(icon, size: 17, color: color),
        ),
      ),
    );
  }

  Widget _textMiniButton(AppColors c, String label, VoidCallback? onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 32, minHeight: 30),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 7),
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Text(
          label,
          style: AppTextStyle.caption(
            onTap == null ? c.textTertiary : c.textPrimary,
          ).copyWith(fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  static const _inlineFormatBarActions = [
    _RichInlineFormatAction.bold,
    _RichInlineFormatAction.italic,
    _RichInlineFormatAction.underline,
    _RichInlineFormatAction.strikethrough,
    _RichInlineFormatAction.monospace,
    _RichInlineFormatAction.link,
    _RichInlineFormatAction.spoiler,
  ];

  /// Blocks one tap away in the toolbar; every other kind sits in the insert
  /// menu pinned at its right edge.
  static const _quickBlockKinds = [
    _RichBlockKind.heading,
    _RichBlockKind.list,
    _RichBlockKind.blockQuotation,
    _RichBlockKind.table,
  ];

  Widget _headerCloseButton(AppColors c) {
    return Semantics(
      button: true,
      label: AppStringKeys.countryPickerCancel.l10n(context),
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('richTextComposerClose'),
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.searchFill,
                shape: BoxShape.circle,
              ),
              child: AppIcon(
                HeroAppIcons.xmark,
                size: 16,
                color: c.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _headerSubmitButton() {
    return Semantics(
      button: true,
      label: widget.submitText.l10n(context),
      excludeSemantics: true,
      child: GestureDetector(
        key: const ValueKey('richTextComposerSubmit'),
        behavior: HitTestBehavior.opaque,
        onTap: _submit,
        child: SizedBox(
          height: 44,
          child: Center(
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Text(
                widget.submitText.l10n(context),
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  decoration: TextDecoration.none,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// One row: inline formats for the selection, then the common blocks, with
  /// the full insert menu pinned at the right so it never scrolls away.
  ///
  /// The controller only formats a non-collapsed selection, so the inline
  /// toggles stay dimmed until text is selected.
  Widget _toolbar(AppColors c) {
    final textBlock = _activeTextBlock;
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: c.background,
        border: Border.symmetric(horizontal: BorderSide(color: c.divider)),
      ),
      child: Row(
        children: [
          Expanded(
            child: ValueListenableBuilder<TextEditingValue>(
              valueListenable: textBlock.controller,
              builder: (context, value, _) {
                final selection = value.selection;
                final hasSelection =
                    selection.isValid && !selection.isCollapsed;
                return ListView(
                  key: const ValueKey('richTextComposerToolbar'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.fromLTRB(10, 7, 4, 7),
                  children: [
                    for (final action in _inlineFormatBarActions)
                      Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: _inlineFormatButton(
                          c,
                          action: action,
                          enabled: hasSelection,
                          selected:
                              hasSelection &&
                              textBlock.controller.selectionHasFormat(
                                action.selectionEntityType,
                              ),
                          onTap: () => _applyInlineFormatToActiveBlock(action),
                        ),
                      ),
                    Center(
                      child: Container(
                        width: 1,
                        height: 20,
                        margin: const EdgeInsets.symmetric(horizontal: 6),
                        color: c.divider,
                      ),
                    ),
                    for (final kind in _quickBlockKinds)
                      _iconButton(
                        c,
                        key: ValueKey('rich-quick-${kind.name}'),
                        icon: kind.icon,
                        label: kind.labelKey.l10n(context),
                        onTap: () => unawaited(_insertBlockKind(kind)),
                      ),
                  ],
                );
              },
            ),
          ),
          _toolbarInsertButton(c),
        ],
      ),
    );
  }

  void _applyInlineFormatToActiveBlock(_RichInlineFormatAction action) {
    final textBlock = _activeTextBlock;
    final selection = textBlock.controller.selection;
    if (!selection.isValid || selection.isCollapsed) return;
    final start = math.min(selection.start, selection.end);
    final end = math.max(selection.start, selection.end);
    unawaited(
      _applyInlineFormatAction(
        action,
        textBlock.controller,
        textBlock.focusNode,
        start,
        end,
      ),
    );
  }

  Widget _inlineFormatButton(
    AppColors c, {
    required _RichInlineFormatAction action,
    required bool enabled,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final foreground = !enabled
        ? c.textTertiary.withValues(alpha: 0.48)
        : selected
        ? AppTheme.brand
        : c.textSecondary;
    final icon = switch (action) {
      _RichInlineFormatAction.link => HeroAppIcons.link,
      _RichInlineFormatAction.spoiler => HeroAppIcons.eyeSlash,
      _ => null,
    };
    return Semantics(
      button: true,
      enabled: enabled,
      selected: selected,
      label: action.labelKey.l10n(context),
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey('rich-inline-${action.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: enabled ? onTap : null,
        child: Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? AppTheme.brand.withValues(alpha: 0.14)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: icon != null
              ? AppIcon(icon, size: 18, color: foreground)
              : Text(
                  _inlineFormatMark(action),
                  style: AppTextStyle.caption(foreground).copyWith(
                    fontWeight: action == _RichInlineFormatAction.bold
                        ? FontWeight.w600
                        : FontWeight.w500,
                    fontStyle: action == _RichInlineFormatAction.italic
                        ? FontStyle.italic
                        : null,
                    decoration: switch (action) {
                      _RichInlineFormatAction.underline =>
                        TextDecoration.underline,
                      _RichInlineFormatAction.strikethrough =>
                        TextDecoration.lineThrough,
                      _ => null,
                    },
                  ),
                ),
        ),
      ),
    );
  }

  String _inlineFormatMark(_RichInlineFormatAction action) {
    return switch (action) {
      _RichInlineFormatAction.bold =>
        AppStringKeys.richTextComposerFormatBoldMark.l10n(context),
      _RichInlineFormatAction.italic =>
        AppStringKeys.richTextComposerFormatItalicMark.l10n(context),
      _RichInlineFormatAction.underline =>
        AppStringKeys.richTextComposerFormatUnderlineMark.l10n(context),
      _RichInlineFormatAction.strikethrough =>
        AppStringKeys.richTextComposerFormatStrikethroughMark.l10n(context),
      _ => '</>',
    };
  }

  Widget _toolbarInsertButton(AppColors c) {
    return Builder(
      builder: (buttonContext) => Semantics(
        button: true,
        label: AppStringKeys.richTextComposerInsert.l10n(context),
        excludeSemantics: true,
        child: GestureDetector(
          key: const ValueKey('richTextComposerInsertButton'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            final box = buttonContext.findRenderObject() as RenderBox?;
            if (box == null) return;
            final anchor = box.localToGlobal(
              Offset(box.size.width / 2, box.size.height),
            );
            unawaited(_showRichBlockInsertMenuAt(anchor));
          },
          child: Container(
            width: 48,
            height: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: c.divider)),
            ),
            child: AppIcon(
              HeroAppIcons.circlePlus,
              size: 24,
              color: AppTheme.brand,
            ),
          ),
        ),
      ),
    );
  }

  Widget _attachmentDock(AppColors c) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.background,
        border: Border(top: BorderSide(color: c.divider)),
      ),
      child: SizedBox(
        height: 52,
        child: Row(
          children: [
            Expanded(
              child: _attachmentAction(
                c,
                icon: HeroAppIcons.image,
                label: AppStringKeys.richTextComposerPhotoVideo.l10n(context),
                onTap: _pickMedia,
              ),
            ),
            Expanded(
              child: _attachmentAction(
                c,
                icon: HeroAppIcons.file,
                label: AppStringKeys.topicPostContentFile.l10n(context),
                onTap: _pickFiles,
              ),
            ),
            Expanded(
              child: _attachmentAction(
                c,
                icon: HeroAppIcons.music,
                label: AppStringKeys.composerAudio.l10n(context),
                onTap: _pickMusic,
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(right: 14),
              child: Text(
                '$_attachmentCount/$_maxAttachments',
                style: AppTextStyle.caption(c.textTertiary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  int get _attachmentCount => _blocks.fold<int>(0, (count, block) {
    if (block.attachment != null) return count + 1;
    return count + (block.mediaGroup?.items.length ?? 0);
  });

  Widget _attachmentAction(
    AppColors c, {
    required AppIconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final enabled = _attachmentCount < _maxAttachments;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AppIcon(
              icon,
              size: 20,
              color: enabled ? c.textPrimary : c.textTertiary,
            ),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.caption(
                  enabled ? c.textPrimary : c.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _inlineAttachmentBlock(
    AppColors c,
    int blockIndex,
    OutgoingAttachment item,
  ) {
    final isPhoto = item.kind == OutgoingAttachmentKind.photo;
    final isVisual = isPhoto || item.kind == OutgoingAttachmentKind.video;
    if (isVisual) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        child: Container(
          height: 190,
          decoration: BoxDecoration(
            color: c.searchFill,
            borderRadius: BorderRadius.circular(AppRadius.control),
            border: Border.all(color: c.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: isPhoto ? () => _editAttachment(blockIndex) : null,
                child: _attachmentPreview(
                  c,
                  item,
                  width: double.infinity,
                  height: 190,
                  fit: BoxFit.contain,
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: const Color(0xB8000000),
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _mediaOverlayAction(
                        HeroAppIcons.trash,
                        () => _removeStructuredBlock(blockIndex),
                        destructive: true,
                      ),
                    ],
                  ),
                ),
              ),
              if (item.kind == OutgoingAttachmentKind.video)
                const Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color(0x99000000),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: AppIcon(
                        HeroAppIcons.play,
                        size: 24,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: Container(
        constraints: const BoxConstraints(minHeight: 86),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(AppRadius.control),
          border: Border.all(color: c.divider),
        ),
        child: Row(
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: isPhoto ? () => _editAttachment(blockIndex) : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: _attachmentIcon(c, item, size: 70),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _attachmentFileName(item),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.callout(
                      c.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _attachmentLabel(item.kind),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.caption(c.textTertiary),
                  ),
                ],
              ),
            ),
            _miniIconButton(
              c,
              icon: HeroAppIcons.trash,
              label: AppStringKeys.richTextComposerRemoveBlock.l10n(context),
              destructive: true,
              onTap: () => _removeStructuredBlock(blockIndex),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mediaOverlayAction(
    AppIconData icon,
    VoidCallback? onTap, {
    bool destructive = false,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 36,
        child: Center(
          child: AppIcon(
            icon,
            size: 17,
            color: onTap == null
                ? Colors.white38
                : destructive
                ? const Color(0xFFFF706A)
                : Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _attachmentPreview(
    AppColors c,
    OutgoingAttachment attachment, {
    required double width,
    required double height,
    BoxFit fit = BoxFit.cover,
  }) {
    // A camera-roll original otherwise decodes at full resolution into a
    // thumbnail box; the oversized allocation evicts the rest of the image
    // cache. One axis only, so the aspect ratio survives.
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = width.isFinite ? (width * dpr).ceil() : null;
    final cacheHeight = width.isFinite ? null : (height * dpr).ceil();
    final previewBytes = attachment.previewBytes;
    if (previewBytes != null && previewBytes.isNotEmpty) {
      return Image.memory(
        previewBytes,
        width: width,
        height: height,
        fit: fit,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        errorBuilder: (_, _, _) => _attachmentIcon(c, attachment, size: height),
      );
    }
    return Image.file(
      File(attachment.path),
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      errorBuilder: (_, _, _) => _attachmentIcon(c, attachment, size: height),
    );
  }

  Widget _attachmentIcon(
    AppColors c,
    OutgoingAttachment attachment, {
    double size = 52,
  }) {
    return Container(
      width: size,
      height: size,
      color: c.card,
      alignment: Alignment.center,
      child: AppIcon(
        switch (attachment.kind) {
          OutgoingAttachmentKind.photo => HeroAppIcons.image,
          OutgoingAttachmentKind.video ||
          OutgoingAttachmentKind.animation => HeroAppIcons.solidFileVideo,
          OutgoingAttachmentKind.document => HeroAppIcons.file,
          OutgoingAttachmentKind.audio => HeroAppIcons.music,
          OutgoingAttachmentKind.voiceNote => HeroAppIcons.microphone,
        },
        size: 23,
        color: c.textSecondary,
      ),
    );
  }

  String _attachmentLabel(OutgoingAttachmentKind kind) {
    return switch (kind) {
      OutgoingAttachmentKind.photo ||
      OutgoingAttachmentKind.video ||
      OutgoingAttachmentKind.animation =>
        AppStringKeys.richTextComposerPhotoVideo.l10n(context),
      OutgoingAttachmentKind.document =>
        AppStringKeys.topicPostContentFile.l10n(context),
      OutgoingAttachmentKind.audio => AppStringKeys.composerAudio.l10n(context),
      OutgoingAttachmentKind.voiceNote =>
        AppStringKeys.richTextBlockVoiceNote.l10n(context),
    };
  }

  String _fileName(String path) {
    final segments = File(path).uri.pathSegments;
    return segments.isEmpty ? path : segments.last;
  }

  String _attachmentFileName(OutgoingAttachment attachment) {
    final explicit = attachment.fileName?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    if (attachment.title.trim().isNotEmpty) return attachment.title.trim();
    if (attachment.path.trim().isNotEmpty) return _fileName(attachment.path);
    return attachment.kind.name;
  }

  Future<void> _editAttachment(int index) async {
    if (index < 0 || index >= _blocks.length) return;
    final item = _blocks[index].attachment;
    if (item == null) return;
    if (item.kind != OutgoingAttachmentKind.photo) return;
    final result = await Navigator.of(context).push<ImageEditResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageEditView(sourcePath: item.path),
      ),
    );
    if (!mounted || result == null || index >= _blocks.length) return;
    final edited = await resolveAttachmentDimensions(
      item.copyWith(
        path: result.path,
        clearPreviewBytes: true,
        clearDimensions: true,
      ),
    );
    if (!mounted || index >= _blocks.length) return;
    setState(() {
      _blocks[index] = _RichContentBlock.attachment(
        edited,
        kind: _blocks[index].kind,
      );
    });
    if (result.caption.trim().isNotEmpty) {
      _activeTextBlock.controller.insertText(result.caption);
    }
  }

  OutgoingAttachment _attachmentFromPickedMedia(XFile file) {
    final kind = isPickedAssetVideo(file)
        ? OutgoingAttachmentKind.video
        : isPickedAssetGif(file)
        ? OutgoingAttachmentKind.animation
        : OutgoingAttachmentKind.photo;
    return OutgoingAttachment(path: file.path, kind: kind);
  }

  OutgoingAttachment _attachmentFromAppPickedAsset(AppPickedAsset asset) {
    return _attachmentFromPickedMedia(asset.file).copyWith(
      previewBytes: asset.thumbnailBytes,
      width: asset.width,
      height: asset.height,
    );
  }

  void _insertAttachmentsAfterActive(Iterable<OutgoingAttachment> attachments) {
    final items = attachments.take(_maxAttachments - _attachmentCount).toList();
    if (items.isEmpty) return;
    var index = _blocks.indexWhere((block) => block.text == _activeTextBlock);
    if (index < 0) index = _blocks.length - 1;
    final trailingText = _createTextBlock('');
    setState(() {
      _blocks.insertAll(index + 1, [
        ...items.map(_RichContentBlock.attachment),
        _RichContentBlock.text(trailingText),
      ]);
      _activeTextBlock = trailingText;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) trailingText.focusNode.requestFocus();
    });
  }

  Future<void> _pickMedia() async {
    final remaining = _maxAttachments - _attachmentCount;
    if (remaining <= 0) return;
    try {
      final picked = await AppAssetPicker.pickDetailed(
        context,
        type: AppAssetPickerType.imageAndVideo,
        maxAssets: remaining,
      );
      if (picked.assets.isEmpty || !mounted) return;
      _insertAttachmentsAfterActive(
        picked.assets.map(_attachmentFromAppPickedAsset),
      );
    } catch (_) {}
  }

  Future<void> _pickFiles() async {
    final remaining = _maxAttachments - _attachmentCount;
    if (remaining <= 0) return;
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (!mounted || result == null) return;
      final paths = result.files.map((file) => file.path).whereType<String>();
      _insertAttachmentsAfterActive(
        paths
            .take(remaining)
            .map(
              (path) => OutgoingAttachment(
                path: path,
                kind: OutgoingAttachmentKind.document,
              ),
            ),
      );
    } catch (_) {}
  }

  Future<void> _pickMusic() => _pickAudioFromSearch(single: false);

  Future<void> _pickAudioFromSearch({required bool single}) async {
    final selected = await Navigator.of(context).push<(int, ChatMessage)>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => AudioSearchView(
          selectOnly: true,
          onPickLocal: () =>
              single ? _pickLocalSingleAudio() : _pickLocalMusicFiles(),
        ),
      ),
    );
    if (!mounted || selected == null) return;
    final music = selected.$2.music;
    final file = music?.file;
    if (music == null || file == null || file.id <= 0) return;
    final attachment = OutgoingAttachment(
      path: file.localPath ?? '',
      kind: OutgoingAttachmentKind.audio,
      fileId: file.id,
      duration: music.duration,
      title: music.title,
      performer: music.performer ?? '',
      fileName: music.title,
    );
    if (single) {
      _insertStructuredBlock(
        _RichContentBlock.attachment(attachment, kind: _RichBlockKind.audio),
      );
    } else {
      _insertAttachmentsAfterActive([attachment]);
    }
  }

  Future<void> _pickLocalSingleAudio() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const [
        'mp3',
        'm4a',
        'aac',
        'flac',
        'wav',
        'ogg',
        'opus',
      ],
    );
    if (!mounted || result == null || result.files.single.path == null) return;
    _insertStructuredBlock(
      _RichContentBlock.attachment(
        OutgoingAttachment(
          path: result.files.single.path!,
          kind: OutgoingAttachmentKind.audio,
          fileName: result.files.single.name,
        ),
        kind: _RichBlockKind.audio,
      ),
    );
  }

  Future<void> _pickLocalMusicFiles() async {
    final remaining = _maxAttachments - _attachmentCount;
    if (remaining <= 0) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.custom,
        allowedExtensions: const [
          'mp3',
          'm4a',
          'aac',
          'flac',
          'wav',
          'ogg',
          'opus',
          'amr',
        ],
      );
      if (!mounted || result == null) return;
      _insertAttachmentsAfterActive(
        result.files
            .where((file) => file.path != null)
            .take(remaining)
            .map(
              (file) => OutgoingAttachment(
                path: file.path!,
                kind: OutgoingAttachmentKind.audio,
                fileName: file.name,
              ),
            ),
      );
    } catch (_) {}
  }

  Widget _iconButton(
    AppColors c, {
    Key? key,
    required AppIconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: GestureDetector(
          key: key,
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.md),
            ),
            child: AppIcon(icon, size: 18, color: c.textSecondary),
          ),
        ),
      ),
    );
  }
}
