import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chat/stretchable_message_bubble_background.dart';
import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/custom_message_bubble_background.dart';
import '../theme/message_bubble_background.dart';
import '../theme/theme_controller.dart';

typedef CustomMessageBubblePngPicker = Future<Uint8List?> Function();

class MessageBubbleSettingsView extends StatefulWidget {
  const MessageBubbleSettingsView({
    super.key,
    this.importer,
    this.pickCustomPng,
  });

  final CustomMessageBubbleImporter? importer;
  final CustomMessageBubblePngPicker? pickCustomPng;

  @override
  State<MessageBubbleSettingsView> createState() =>
      _MessageBubbleSettingsViewState();
}

class _MessageBubbleSettingsViewState extends State<MessageBubbleSettingsView> {
  late final CustomMessageBubbleImporter _importer =
      widget.importer ?? CustomMessageBubbleImporter();
  bool _importing = false;

  Future<Uint8List?> _pickPng() async {
    final injected = widget.pickCustomPng;
    if (injected != null) return injected();
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png'],
      withData: true,
    );
    final picked = result?.files.single;
    if (picked == null) return null;
    final bytes = picked.bytes;
    if (bytes != null) return bytes;
    final path = picked.path;
    return path == null ? null : File(path).readAsBytes();
  }

  Future<void> _importCustomPng() async {
    if (_importing) return;
    setState(() => _importing = true);
    try {
      final bytes = await _pickPng();
      if (bytes == null || !mounted) return;
      final custom = await _importer.importBytes(bytes);
      if (!mounted) return;
      context.read<ThemeController>().installCustomMessageBubbleBackground(
        custom,
      );
    } on CustomMessageBubbleImportException catch (error) {
      if (mounted) showToast(context, _messageFor(error.failure));
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.messageBubbleCustomImportFailed),
        );
      }
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  String _messageFor(CustomMessageBubbleImportFailure failure) =>
      AppStrings.t(switch (failure) {
        CustomMessageBubbleImportFailure.invalidPng =>
          AppStringKeys.messageBubbleCustomInvalidPng,
        CustomMessageBubbleImportFailure.tooSmall =>
          AppStringKeys.messageBubbleCustomTooSmall,
        CustomMessageBubbleImportFailure.tooLarge =>
          AppStringKeys.messageBubbleCustomTooLarge,
        CustomMessageBubbleImportFailure.write =>
          AppStringKeys.messageBubbleCustomImportFailed,
      });

  Future<void> _removeCustomPng() async {
    final confirmed = await showAppConfirmDialog(
      context,
      title: AppStringKeys.messageBubbleCustomRemoveTitle,
      message: AppStringKeys.messageBubbleCustomRemoveMessage,
      confirmText: AppStringKeys.messageBubbleCustomRemove,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    context.read<ThemeController>().clearCustomMessageBubbleBackground();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final selected = theme.messageBubbleBackground;
    final custom = theme.customMessageBubbleBackground;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.appearanceMessageBubbles),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(14, 18, 14, 28),
              children: [
                _preview(context, theme.messageBubbleBackgroundSpec),
                const SizedBox(height: 14),
                Text(
                  AppStrings.t(AppStringKeys.messageBubbleStretchDescription),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 18),
                _choice(
                  context,
                  style: MessageBubbleBackground.standard,
                  background: MessageBubbleBackgroundSpec.standard,
                  label: AppStrings.t(AppStringKeys.messageBubbleDefault),
                  selected: selected == MessageBubbleBackground.standard,
                  onTap: () => theme.messageBubbleBackground =
                      MessageBubbleBackground.standard,
                ),
                const SizedBox(height: 10),
                _choice(
                  context,
                  style: MessageBubbleBackground.purpleFolded,
                  background: MessageBubbleBackgroundSpec.purpleFolded,
                  label: AppStrings.t(AppStringKeys.messageBubblePurpleFolded),
                  selected: selected == MessageBubbleBackground.purpleFolded,
                  onTap: () => theme.messageBubbleBackground =
                      MessageBubbleBackground.purpleFolded,
                ),
                const SizedBox(height: 10),
                _choice(
                  context,
                  style: MessageBubbleBackground.creamCharms,
                  background: MessageBubbleBackgroundSpec.creamCharms,
                  label: AppStrings.t(AppStringKeys.messageBubbleCreamCharms),
                  selected: selected == MessageBubbleBackground.creamCharms,
                  onTap: () => theme.messageBubbleBackground =
                      MessageBubbleBackground.creamCharms,
                ),
                const SizedBox(height: 10),
                _choice(
                  context,
                  style: MessageBubbleBackground.custom,
                  background: theme.messageBubbleBackgroundSpecFor(
                    MessageBubbleBackground.custom,
                  ),
                  label: AppStrings.t(AppStringKeys.messageBubbleCustom),
                  selected: selected == MessageBubbleBackground.custom,
                  emptyCustom: custom == null,
                  onTap: custom == null
                      ? _importCustomPng
                      : () => theme.messageBubbleBackground =
                            MessageBubbleBackground.custom,
                ),
                const SizedBox(height: 14),
                Text(
                  AppStrings.t(AppStringKeys.messageBubbleCustomDescription),
                  style: TextStyle(
                    color: c.textSecondary,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                SettingsCard(
                  children: [
                    SettingsRow(
                      key: ValueKey(
                        custom == null
                            ? 'messageBubbleCustomImport'
                            : 'messageBubbleCustomReplace',
                      ),
                      title: custom == null
                          ? AppStringKeys.messageBubbleCustomImport
                          : AppStringKeys.messageBubbleCustomReplace,
                      showChevron: false,
                      onTap: _importing ? null : _importCustomPng,
                      leading: SettingsIconTile(
                        icon: HeroAppIcons.upload,
                        backgroundColor: AppTheme.brand,
                      ),
                      trailing: _importing
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                    if (custom != null) ...[
                      const InsetDivider(),
                      SettingsRow(
                        key: const ValueKey('messageBubbleCustomRemove'),
                        title: AppStringKeys.messageBubbleCustomRemove,
                        showChevron: false,
                        onTap: _removeCustomPng,
                        leading: SettingsIconTile(
                          icon: HeroAppIcons.trash,
                          backgroundColor: AppTheme.tagRed,
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _preview(
    BuildContext context,
    MessageBubbleBackgroundSpec background,
  ) {
    final c = context.colors;
    return Container(
      height: 244,
      padding: const EdgeInsets.fromLTRB(14, 24, 14, 20),
      decoration: BoxDecoration(
        color: c.chatBackground,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.divider.withValues(alpha: 0.7)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const PhotoAvatar(title: 'M', size: 34),
              const SizedBox(width: 8),
              Flexible(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: _previewBubble(
                    context,
                    background: background,
                    outgoing: false,
                    text: AppStrings.t(AppStringKeys.messageBubblePreviewShort),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: _previewBubble(
                    context,
                    background: background,
                    outgoing: true,
                    text: AppStrings.t(AppStringKeys.messageBubblePreviewLong),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const PhotoAvatar(title: 'K', size: 34),
            ],
          ),
        ],
      ),
    );
  }

  Widget _previewBubble(
    BuildContext context, {
    required MessageBubbleBackgroundSpec background,
    required bool outgoing,
    required String text,
  }) {
    final c = context.colors;
    final foreground =
        background.foregroundColor ??
        (outgoing ? AppTheme.bubbleOutgoingText : c.bubbleIncomingText);
    return StretchableMessageBubbleBackground(
      background: background,
      constraints: const BoxConstraints(maxWidth: 250),
      fallbackColor: outgoing ? AppTheme.bubbleOutgoing : c.bubbleIncoming,
      fallbackBorderRadius: BorderRadius.circular(12),
      fallbackBorder: outgoing
          ? null
          : Border.all(color: c.divider, width: 0.5),
      fallbackPadding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      child: Text(
        text,
        style: TextStyle(color: foreground, fontSize: 15, height: 1.25),
      ),
    );
  }

  Widget _choice(
    BuildContext context, {
    required MessageBubbleBackground style,
    required MessageBubbleBackgroundSpec background,
    required String label,
    required bool selected,
    required VoidCallback onTap,
    bool emptyCustom = false,
  }) {
    final c = context.colors;
    return GestureDetector(
      key: ValueKey('messageBubbleChoice-${style.name}'),
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutCubic,
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: c.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected ? AppTheme.brand : c.divider,
            width: selected ? 1.5 : 0.5,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: c.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            SizedBox(
              width: 112,
              height: 50,
              child: StretchableMessageBubbleBackground(
                background: background,
                constraints: const BoxConstraints.tightFor(
                  width: 112,
                  height: 50,
                ),
                fallbackColor: c.bubbleIncoming,
                fallbackBorderRadius: BorderRadius.circular(12),
                fallbackBorder: Border.all(color: c.divider, width: 0.5),
                fallbackPadding: EdgeInsets.zero,
                child: emptyCustom
                    ? Center(
                        child: AppIcon(
                          HeroAppIcons.image,
                          size: 22,
                          color: c.textTertiary,
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 12),
            AppIcon(
              selected ? HeroAppIcons.circleCheck : HeroAppIcons.circle,
              size: 21,
              color: selected ? AppTheme.brand : c.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
