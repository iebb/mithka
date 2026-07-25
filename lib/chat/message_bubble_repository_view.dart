import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/custom_message_bubble_background.dart';
import '../theme/theme_controller.dart';
import 'chat_view_model.dart';
import 'link_handler.dart';

const messageBubbleRepositoryUsername = 'msgbubble';

bool isEligibleMessageBubbleRepositoryPhoto(ChatMessage message) =>
    message.contentType == 'messagePhoto' &&
    message.image != null &&
    message.imageWidth == MessageBubbleRepositoryFormat.width &&
    message.imageHeight == MessageBubbleRepositoryFormat.height;

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
    showToast(context, 'Bubble images must be exactly 190 × 120 px.');
    return;
  }
  final path = await TdFileCenter.shared.pathFor(message.image!);
  if (path == null || !await File(path).exists()) {
    if (context.mounted) showToast(context, 'Could not download this bubble.');
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
    showToast(context, 'Message bubble applied.');
  } on CustomMessageBubbleImportException catch (error) {
    if (!context.mounted) return;
    final text = switch (error.failure) {
      CustomMessageBubbleImportFailure.wrongRepositorySize =>
        'Bubble images must be exactly 190 × 120 px.',
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
    final selectedLink = context
        .watch<ThemeController>()
        .customMessageBubbleBackground
        ?.sourceMessageLink;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: 'Message bubbles', onBack: widget.onBack),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: c.card,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Repository images are exactly 190 × 120 px. Four compact squares store text colors; color 1 is currently used.',
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                if (selectedLink != null) ...[
                  const SizedBox(height: 7),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => openLink(context, selectedLink),
                    child: Text(
                      selectedLink,
                      style: TextStyle(
                        color: AppTheme.brand,
                        fontSize: 12.5,
                        decoration: TextDecoration.underline,
                      ),
                    ),
                  ),
                ],
              ],
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
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: MediaQuery.sizeOf(context).width >= 700
                            ? 3
                            : 2,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,
                        childAspectRatio: 1.18,
                      ),
                      itemCount: bubbles.length,
                      itemBuilder: (context, index) {
                        final message = bubbles[index];
                        final link = messageBubbleRepositoryLink(message.id);
                        final selected = selectedLink == link;
                        final applying = _applying.contains(message.id);
                        return Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: c.card,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected ? AppTheme.brand : c.divider,
                              width: selected ? 1.5 : 0.5,
                            ),
                          ),
                          child: Column(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(9),
                                  child: TDImage(
                                    photo: message.image,
                                    fit: BoxFit.contain,
                                    cornerRadius: 0,
                                    showProgress: true,
                                  ),
                                ),
                              ),
                              const SizedBox(height: 7),
                              GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: applying ? null : () => _apply(message),
                                child: Container(
                                  height: 34,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: selected
                                        ? AppTheme.brand.withValues(alpha: 0.12)
                                        : AppTheme.brand,
                                    borderRadius: BorderRadius.circular(9),
                                  ),
                                  child: applying
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            AppIcon(
                                              selected
                                                  ? HeroAppIcons.check
                                                  : HeroAppIcons.palette,
                                              size: 15,
                                              color: selected
                                                  ? AppTheme.brand
                                                  : AppTheme.onBrand,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              selected ? 'Applied' : 'Apply',
                                              style: TextStyle(
                                                color: selected
                                                    ? AppTheme.brand
                                                    : AppTheme.onBrand,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ],
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
