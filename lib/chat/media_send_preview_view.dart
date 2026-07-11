import 'dart:io';

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'image_edit_view.dart';
import 'outgoing_attachment.dart';

class MediaSendPreviewResult {
  const MediaSendPreviewResult({
    required this.attachments,
    required this.caption,
  });

  final List<OutgoingAttachment> attachments;
  final String caption;
}

class MediaSendPreviewView extends StatefulWidget {
  const MediaSendPreviewView({
    super.key,
    required this.attachments,
    this.initialCaption = '',
  });

  final List<OutgoingAttachment> attachments;
  final String initialCaption;

  @override
  State<MediaSendPreviewView> createState() => _MediaSendPreviewViewState();
}

class _MediaSendPreviewViewState extends State<MediaSendPreviewView> {
  late final TextEditingController _captionController;
  late final List<OutgoingAttachment> _attachments;
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _captionController = TextEditingController(text: widget.initialCaption);
    _attachments = List.of(widget.attachments);
  }

  @override
  void dispose() {
    _captionController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_attachments.isEmpty) return;
    Navigator.of(context).pop(
      MediaSendPreviewResult(
        attachments: List.unmodifiable(_attachments),
        caption: _captionController.text,
      ),
    );
  }

  Future<void> _editSelected() async {
    if (_attachments.isEmpty) return;
    final attachment = _attachments[_selectedIndex];
    if (attachment.kind != OutgoingAttachmentKind.photo) return;
    final result = await Navigator.of(context).push<ImageEditResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageEditView(sourcePath: attachment.path),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      _attachments[_selectedIndex] = attachment.copyWith(
        path: result.path,
        clearPreviewBytes: true,
      );
      if (result.caption.trim().isNotEmpty) {
        _captionController.text = result.caption;
      }
    });
  }

  void _removeSelected() {
    if (_attachments.isEmpty) return;
    setState(() {
      _attachments.removeAt(_selectedIndex);
      if (_selectedIndex >= _attachments.length) {
        _selectedIndex = (_attachments.length - 1).clamp(0, 1000);
      }
    });
    if (_attachments.isEmpty) Navigator.of(context).pop();
  }

  void _reorderAttachments(int oldIndex, int newIndex) {
    if (oldIndex == newIndex) return;
    final selectedAttachment = _attachments[_selectedIndex];
    setState(() {
      final attachment = _attachments.removeAt(oldIndex);
      _attachments.insert(newIndex, attachment);
      _selectedIndex = _attachments.indexOf(selectedAttachment);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.navBar,
      body: SafeArea(
        bottom: false,
        child: ColoredBox(
          color: c.background,
          child: Column(
            children: [
              _topBar(c),
              Divider(height: 1, color: c.divider),
              Expanded(
                child: _attachments.isEmpty
                    ? const SizedBox.shrink()
                    : _selectedMedia(c),
              ),
              if (_attachments.length > 1) _thumbnailStrip(c),
              _captionBar(c),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selectedMedia(AppColors c) {
    final attachment = _attachments[_selectedIndex];
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: attachment.kind == OutgoingAttachmentKind.photo
                  ? _editSelected
                  : null,
              child: Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _preview(c, attachment, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: _mediaAction(
              key: const ValueKey('mediaPreviewDelete'),
              icon: HeroAppIcons.trash,
              color: const Color(0xFFFF6B63),
              onTap: _removeSelected,
            ),
          ),
          if (attachment.kind == OutgoingAttachmentKind.photo)
            Positioned(
              right: 8,
              top: 8,
              child: _mediaAction(
                key: const ValueKey('mediaPreviewEdit'),
                icon: HeroAppIcons.pen,
                color: Colors.white,
                onTap: _editSelected,
              ),
            ),
        ],
      ),
    );
  }

  Widget _mediaAction({
    required Key key,
    required AppIconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xA6000000),
          borderRadius: BorderRadius.circular(8),
        ),
        child: AppIcon(icon, size: 20, color: color),
      ),
    );
  }

  Widget _topBar(AppColors c) {
    return SizedBox(
      height: 54,
      child: Row(
        children: [
          _textAction(
            AppStringKeys.countryPickerCancel.l10n(context),
            c.textPrimary,
            () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              AppStringKeys.mediaSendPreviewTitle.l10n(context),
              textAlign: TextAlign.center,
              style: AppTextStyle.title(c.textPrimary),
            ),
          ),
          _textAction(
            AppStringKeys.composerSend.l10n(context),
            AppTheme.brand,
            _submit,
          ),
        ],
      ),
    );
  }

  Widget _textAction(String label, Color color, VoidCallback onTap) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Text(
          label,
          style: TextStyle(
            color: color,
            fontSize: 16,
            fontWeight: FontWeight.w600,
            decoration: TextDecoration.none,
          ),
        ),
      ),
    );
  }

  Widget _thumbnailStrip(AppColors c) {
    return SizedBox(
      height: 88,
      child: ReorderableListView.builder(
        scrollDirection: Axis.horizontal,
        buildDefaultDragHandles: false,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        itemCount: _attachments.length,
        onReorderItem: _reorderAttachments,
        proxyDecorator: (child, _, animation) => AnimatedBuilder(
          animation: animation,
          builder: (context, _) => Transform.scale(
            scale: 1 + (animation.value * 0.06),
            child: child,
          ),
        ),
        itemBuilder: (context, index) {
          final selected = index == _selectedIndex;
          final attachment = _attachments[index];
          return ReorderableDelayedDragStartListener(
            key: ObjectKey(attachment),
            index: index,
            child: Padding(
              padding: EdgeInsets.only(
                right: index == _attachments.length - 1 ? 0 : 8,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _selectedIndex = index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 140),
                  width: 72,
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: selected ? AppTheme.brand : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: _preview(c, attachment, fit: BoxFit.cover),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _captionBar(AppColors c) {
    final safeBottom = MediaQuery.paddingOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(12, 8, 12, 10 + safeBottom),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(top: BorderSide(color: c.divider)),
      ),
      child: TextField(
        key: const ValueKey('mediaPreviewCaption'),
        controller: _captionController,
        minLines: 1,
        maxLines: 4,
        style: AppTextStyle.body(c.textPrimary),
        decoration: InputDecoration(
          filled: true,
          fillColor: c.searchFill,
          hintText: AppStringKeys.chatMessageInputPlaceholder.l10n(context),
          hintStyle: AppTextStyle.body(c.textTertiary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 10,
          ),
        ),
      ),
    );
  }

  Widget _preview(
    AppColors c,
    OutgoingAttachment attachment, {
    required BoxFit fit,
  }) {
    final bytes = attachment.previewBytes;
    final image = bytes != null && bytes.isNotEmpty
        ? Image.memory(
            bytes,
            fit: fit,
            width: double.infinity,
            height: double.infinity,
          )
        : Image.file(
            File(attachment.path),
            fit: fit,
            width: double.infinity,
            height: double.infinity,
            errorBuilder: (_, _, _) => _fallback(c, attachment),
          );
    if (attachment.kind != OutgoingAttachmentKind.video) return image;
    return Stack(
      fit: StackFit.expand,
      children: [
        image,
        Center(
          child: Container(
            width: 46,
            height: 46,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0x99000000),
              shape: BoxShape.circle,
            ),
            child: const AppIcon(
              HeroAppIcons.play,
              size: 24,
              color: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _fallback(AppColors c, OutgoingAttachment attachment) {
    return ColoredBox(
      color: c.searchFill,
      child: Center(
        child: AppIcon(
          attachment.kind == OutgoingAttachmentKind.video
              ? HeroAppIcons.video
              : HeroAppIcons.image,
          size: 34,
          color: c.textSecondary,
        ),
      ),
    );
  }
}
