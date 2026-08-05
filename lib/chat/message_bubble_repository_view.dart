import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/custom_message_bubble_background.dart';
import '../theme/theme_controller.dart';
import 'chat_view_model.dart';
import 'message_bubble_chat_preview.dart';

const messageBubbleRepositoryUsername = 'msgbubble';

TdFileRef? messageBubbleRepositoryFile(ChatMessage message) {
  if (message.contentType == 'messagePhoto' &&
      message.imageWidth == MessageBubbleRepositoryFormat.width &&
      message.imageHeight == MessageBubbleRepositoryFormat.height) {
    return message.image;
  }
  final document = message.document;
  if (message.contentType == 'messageDocument' &&
      document != null &&
      document.ext.toLowerCase() == 'png' &&
      RegExp(
        r'(^|\s)#msgbubble(?:\s|$)',
        caseSensitive: false,
      ).hasMatch(message.text)) {
    return document.file;
  }
  return null;
}

bool isEligibleMessageBubbleRepositoryPhoto(ChatMessage message) =>
    messageBubbleRepositoryFile(message) != null;

bool offersMessageBubbleApplyAction(ChatMessage message) =>
    isEligibleMessageBubbleRepositoryPhoto(message) &&
    RegExp(
      r'(^|\s)#msgbubble(?:\s|$)',
      caseSensitive: false,
    ).hasMatch(message.text);

String messageBubbleRepositoryLink(int messageId) =>
    'https://t.me/$messageBubbleRepositoryUsername/$messageId';

Future<void> applyMessageBubbleRepositoryPhoto(
  BuildContext context,
  ChatMessage message, {
  String? sourceMessageLink,
}) async {
  if (!isEligibleMessageBubbleRepositoryPhoto(message)) {
    showToast(context, AppStrings.t(AppStringKeys.messageBubbleRepoSizeRule));
    return;
  }
  final path = await TdFileCenter.shared.pathFor(
    messageBubbleRepositoryFile(message)!,
  );
  if (path == null || !await File(path).exists()) {
    if (context.mounted) {
      showToast(
        context,
        AppStrings.t(AppStringKeys.messageBubbleRepoDownloadFailed),
      );
    }
    return;
  }
  try {
    final custom = await CustomMessageBubbleImporter().importRepositoryBytes(
      await File(path).readAsBytes(),
      sourceMessageLink:
          sourceMessageLink ?? messageBubbleRepositoryLink(message.id),
    );
    if (!context.mounted) return;
    context.read<ThemeController>().installCustomMessageBubbleBackground(
      custom,
    );
    showToast(context, AppStrings.t(AppStringKeys.messageBubbleRepoApplied));
  } on CustomMessageBubbleImportException catch (error) {
    if (!context.mounted) return;
    final text = switch (error.failure) {
      CustomMessageBubbleImportFailure.wrongRepositorySize => AppStrings.t(
        AppStringKeys.messageBubbleRepoSizeRule,
      ),
      CustomMessageBubbleImportFailure.invalidPalette =>
        'The four color swatches must each be one solid color.',
      _ => 'This image is not a valid message bubble.',
    };
    showToast(context, text);
  }
}

class MessageBubbleRepositoryView extends StatefulWidget {
  const MessageBubbleRepositoryView({
    super.key,
    required this.viewModel,
    required this.onBack,
  });

  final ChatViewModel viewModel;
  final VoidCallback onBack;

  @override
  State<MessageBubbleRepositoryView> createState() =>
      _MessageBubbleRepositoryViewState();
}

class _MessageBubbleRepositoryViewState
    extends State<MessageBubbleRepositoryView> {
  final Set<int> _applying = <int>{};

  ChatViewModel get _vm => widget.viewModel;

  Future<void> _apply(ChatMessage message) async {
    if (!_applying.add(message.id)) return;
    setState(() {});
    try {
      await applyMessageBubbleRepositoryPhoto(
        context,
        message,
        sourceMessageLink: messageBubbleRepositoryLink(message.id),
      );
    } finally {
      if (mounted) setState(() => _applying.remove(message.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final bubbles = _vm.messages
        .where(isEligibleMessageBubbleRepositoryPhoto)
        .toList(growable: false)
        .reversed
        .toList(growable: false);
    final theme = context.watch<ThemeController>();
    final selectedLink = theme.customMessageBubbleBackground?.sourceMessageLink;
    ChatMessage? previewMessage;
    for (final message in bubbles) {
      if (messageBubbleRepositoryLink(message.id) == selectedLink) {
        previewMessage = message;
        break;
      }
    }
    previewMessage ??= bubbles.isEmpty ? null : bubbles.first;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.messageBubbleRepoTitle),
            onBack: widget.onBack,
          ),
          if (previewMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: MessageBubbleChatPreview(
                incomingBackground: theme
                    .effectiveMessageBubbleBackgroundSpecFor(outgoing: false),
                outgoingBackground: theme
                    .effectiveMessageBubbleBackgroundSpecFor(outgoing: true),
              ),
            ),
          Expanded(
            child: bubbles.isEmpty && !_vm.initialLoaded
                ? const Center(child: CircularProgressIndicator())
                : NotificationListener<ScrollEndNotification>(
                    onNotification: (notification) {
                      if (notification.metrics.extentAfter < 320 &&
                          _vm.canLoadOlder) {
                        unawaited(_vm.loadOlder());
                      }
                      return false;
                    },
                    child: GridView.builder(
                      padding: const EdgeInsets.all(12),
                      gridDelegate:
                          const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            mainAxisSpacing: 10,
                            crossAxisSpacing: 10,
                            // Leave enough height for the high-resolution
                            // center-slice so it can fill the entire cell width.
                            childAspectRatio: 1.5,
                          ),
                      itemCount: bubbles.length,
                      itemBuilder: (context, index) {
                        final message = bubbles[index];
                        final link = messageBubbleRepositoryLink(message.id);
                        final selected = selectedLink == link;
                        final applying = _applying.contains(message.id);
                        return GestureDetector(
                          key: ValueKey('messageBubbleApply-${message.id}'),
                          behavior: HitTestBehavior.opaque,
                          onTap: applying ? null : () => _apply(message),
                          child: Container(
                            // Keep breathing room around the image: decorations
                            // can reach beyond the visual bubble edge.
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: Colors.transparent,
                              borderRadius: BorderRadius.circular(
                                AppRadius.control,
                              ),
                              border: Border.all(
                                color: selected
                                    ? AppTheme.brand
                                    : Colors.transparent,
                                width: 1.5,
                              ),
                            ),
                            child: applying
                                ? const Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                : _RepositoryBubbleThumbnail(message: message),
                          ),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _RepositoryBubbleThumbnail extends StatefulWidget {
  const _RepositoryBubbleThumbnail({required this.message});

  final ChatMessage message;

  @override
  State<_RepositoryBubbleThumbnail> createState() =>
      _RepositoryBubbleThumbnailState();
}

class _RepositoryBubbleThumbnailState
    extends State<_RepositoryBubbleThumbnail> {
  late final Future<ProcessedMessageBubblePng?> _processed = _load();

  Future<ProcessedMessageBubblePng?> _load() async {
    final file = messageBubbleRepositoryFile(widget.message);
    if (file == null) return null;
    final path = await TdFileCenter.shared.pathFor(file);
    if (path == null || !await File(path).exists()) return null;
    try {
      return const CustomMessageBubblePngProcessor().processRepository(
        Uint8List.fromList(await File(path).readAsBytes()),
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProcessedMessageBubblePng?>(
      future: _processed,
      builder: (context, snapshot) {
        final processed = snapshot.data;
        if (processed == null) {
          return TDImage(
            photo: messageBubbleRepositoryFile(widget.message),
            fit: BoxFit.contain,
            cornerRadius: 0,
            showProgress: snapshot.connectionState != ConnectionState.done,
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final canCenterSlice =
                constraints.maxWidth >=
                    processed.width /
                        MessageBubbleRepositoryFormat.imageScale &&
                constraints.maxHeight >=
                    processed.height / MessageBubbleRepositoryFormat.imageScale;
            return Stack(
              fit: StackFit.expand,
              clipBehavior: Clip.none,
              children: [
                Image.memory(
                  processed.bytes,
                  scale: MessageBubbleRepositoryFormat.imageScale,
                  fit: canCenterSlice ? BoxFit.fill : BoxFit.contain,
                  centerSlice: canCenterSlice
                      ? Rect.fromLTWH(
                          processed.stretchX /
                              MessageBubbleRepositoryFormat.imageScale,
                          processed.stretchY /
                              MessageBubbleRepositoryFormat.imageScale,
                          1 / MessageBubbleRepositoryFormat.imageScale,
                          1 / MessageBubbleRepositoryFormat.imageScale,
                        )
                      : null,
                  filterQuality: FilterQuality.high,
                  gaplessPlayback: true,
                ),
                Center(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 10, 18, 9),
                    child: Text(
                      AppStrings.t(AppStringKeys.messageBubbleRepoPreview),
                      maxLines: 2,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.clip,
                      style: TextStyle(
                        color: Color(processed.foregroundColorValue),
                        fontSize: 10.5,
                        height: 1.08,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
