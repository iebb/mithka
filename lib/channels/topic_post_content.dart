import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../chat/file_detail_view.dart';
import '../chat/link_handler.dart';
import '../chat/telegram_rich_text.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../l10n/telegram_language_controller.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

class TopicPostContent extends StatelessWidget {
  const TopicPostContent({
    super.key,
    required this.chatId,
    required this.message,
    required this.text,
    required this.textStyle,
    this.maxTextLines,
    this.textOverflow = TextOverflow.clip,
    this.imageReactions,
  });

  final int chatId;
  final ChatMessage message;
  final String text;
  final TextStyle textStyle;
  final int? maxTextLines;
  final TextOverflow textOverflow;
  final Widget? imageReactions;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    if (text.isNotEmpty) {
      children.add(
        TelegramRichText(
          text: text,
          entities: message.textEntities,
          maxLines: maxTextLines,
          overflow: textOverflow,
          style: textStyle,
        ),
      );
    }
    if (message.image != null) {
      children.add(_TopicContentImage(message: message));
      final reactions = imageReactions;
      if (reactions != null) children.add(reactions);
    }
    if (message.document != null) {
      children.add(_TopicFileCard(document: message.document!));
    }
    if (message.buttonRows.isNotEmpty) {
      children.add(_TopicButtonRows(chatId: chatId, message: message));
    }
    if (children.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 10),
          children[i],
        ],
      ],
    );
  }
}

class _TopicContentImage extends StatelessWidget {
  const _TopicContentImage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width - 28;
    final height = _imageHeight(width);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        width: width,
        height: height,
        child: TDImage(
          photo: message.image,
          cornerRadius: 6,
          cacheWidth: (width * MediaQuery.of(context).devicePixelRatio).round(),
          cacheHeight: (height * MediaQuery.of(context).devicePixelRatio)
              .round(),
        ),
      ),
    );
  }

  double _imageHeight(double width) {
    final w = message.imageWidth;
    final h = message.imageHeight;
    if (w == null || h == null || w <= 0 || h <= 0) return width * 0.62;
    final ratio = (h / w).clamp(0.45, 1.25);
    return width * ratio;
  }
}

class _TopicFileCard extends StatelessWidget {
  const _TopicFileCard({required this.document});

  final MessageDocument document;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(
        context,
      ).push(MaterialPageRoute(builder: (_) => FileDetailView(doc: document))),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: c.divider, width: 0.5),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    document.fileName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 15, color: c.textPrimary),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _byteString(document.size),
                    style: TextStyle(fontSize: 12, color: c.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            _FileGlyph(ext: document.ext),
          ],
        ),
      ),
    );
  }

  String _byteString(int bytes) {
    if (bytes <= 0) {
      return telegramText(AppStringKeys.topicPostContentFile);
    }
    const units = ['B', 'KB', 'MB', 'GB'];
    var value = bytes.toDouble();
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    final number = value >= 10 || unit == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$number ${units[unit]}';
  }
}

class _FileGlyph extends StatelessWidget {
  const _FileGlyph({required this.ext});

  final String ext;

  @override
  Widget build(BuildContext context) {
    final normalized = ext.toUpperCase();
    return SizedBox(
      width: 42,
      height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AppIcon(
            HeroAppIcons.solidFile,
            size: 40,
            color: _fileColor(normalized),
          ),
          Positioned(
            bottom: 8,
            child: Text(
              _fileBadge(normalized),
              style: const TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _fileColor(String ext) {
    return switch (ext) {
      'PDF' => const Color(0xFFFF3B30),
      'DOC' || 'DOCX' => const Color(0xFF2F80ED),
      'XLS' || 'XLSX' => const Color(0xFF22A06B),
      'PPT' || 'PPTX' => const Color(0xFFFF9500),
      'ZIP' || 'RAR' || '7Z' => const Color(0xFF8E8E93),
      _ => AppTheme.brand,
    };
  }

  String _fileBadge(String ext) {
    if (ext.isEmpty) return 'FILE';
    return ext.length > 4 ? ext.substring(0, 4) : ext;
  }
}

class _TopicButtonRows extends StatelessWidget {
  const _TopicButtonRows({required this.chatId, required this.message});

  final int chatId;
  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      children: [
        for (final row in message.buttonRows) ...[
          Row(
            children: [
              for (var i = 0; i < row.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _pressButton(context, row[i]),
                    child: Container(
                      constraints: const BoxConstraints(minHeight: 38),
                      alignment: Alignment.center,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: c.searchFill,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: c.divider, width: 0.5),
                      ),
                      child: Text(
                        row[i].text,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                          color: c.linkBlue,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          if (row != message.buttonRows.last) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Future<void> _pressButton(BuildContext context, MessageButton button) async {
    final url = button.url;
    if (url != null && url.isNotEmpty) {
      await openLink(context, url);
      return;
    }
    final userId = button.userId;
    if (userId != null && userId > 0) {
      await openLink(context, 'tg://user?id=$userId');
      return;
    }
    final copyText = button.copyText;
    if (copyText != null && copyText.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: copyText));
      if (context.mounted) {
        showToast(context, AppStrings.t(AppStringKeys.topicPostContentCopied));
      }
      return;
    }
    if (button.isCallback) {
      try {
        final answer = await TdClient.shared.query({
          '@type': 'getCallbackQueryAnswer',
          'chat_id': chatId,
          'message_id': message.id,
          'payload': {
            '@type': 'callbackQueryPayloadData',
            'data': button.data ?? '',
          },
        });
        if (!context.mounted) return;
        final answerUrl = answer.str('url');
        if (answerUrl != null && answerUrl.isNotEmpty) {
          await openLink(context, answerUrl);
          return;
        }
        final text = answer.str('text');
        if (text != null && text.isNotEmpty) showToast(context, text);
      } catch (_) {
        if (context.mounted) {
          showToast(
            context,
            AppStrings.t(AppStringKeys.topicPostContentActionFailed),
          );
        }
      }
      return;
    }
    final query = button.switchInlineQuery;
    if (query != null && query.isNotEmpty) {
      await Clipboard.setData(ClipboardData(text: query));
      if (context.mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.topicPostContentCopiedQuery),
        );
      }
      return;
    }
  }
}
