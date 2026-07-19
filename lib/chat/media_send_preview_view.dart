import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../components/app_icons.dart';
import '../components/toast.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'image_edit_view.dart';
import 'message_send_options.dart';
import 'outgoing_attachment.dart';
import 'video_trim_service.dart';

class MediaSendPreviewResult {
  const MediaSendPreviewResult({
    required this.attachments,
    required this.caption,
    required this.sendConfiguration,
  });

  final List<OutgoingAttachment> attachments;
  final String caption;
  final MessageSendConfiguration sendConfiguration;
}

class MediaSendPreviewView extends StatefulWidget {
  const MediaSendPreviewView({
    super.key,
    required this.attachments,
    this.initialCaption = '',
    this.allowWhenOnline = false,
    this.effects = const [],
  });

  final List<OutgoingAttachment> attachments;
  final String initialCaption;
  final bool allowWhenOnline;
  final List<AvailableMessageEffect> effects;

  @override
  State<MediaSendPreviewView> createState() => _MediaSendPreviewViewState();
}

class _MediaSendPreviewViewState extends State<MediaSendPreviewView> {
  late final TextEditingController _captionController;
  late final List<OutgoingAttachment> _attachments;
  int _selectedIndex = 0;
  bool _sendAsFile = false;
  MessageSendConfiguration _sendConfiguration =
      const MessageSendConfiguration();

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
    final attachments = _sendAsFile
        ? _attachments
              .map(
                (attachment) =>
                    attachment.copyWith(kind: OutgoingAttachmentKind.document),
              )
              .toList(growable: false)
        : List<OutgoingAttachment>.of(_attachments);
    Navigator.of(context).pop(
      MediaSendPreviewResult(
        attachments: List.unmodifiable(attachments),
        caption: _captionController.text,
        sendConfiguration: _sendConfiguration,
      ),
    );
  }

  Future<void> _configureAndSubmit() async {
    final value = await showMessageSendOptionsSheet(
      context,
      initial: _sendConfiguration,
      allowWhenOnline: widget.allowWhenOnline,
      mediaOptions: !_sendAsFile,
      effects: widget.effects,
    );
    if (!mounted || value == null) return;
    _sendConfiguration = value;
    _submit();
  }

  Future<void> _editSelected() async {
    if (_sendAsFile || _attachments.isEmpty) return;
    final attachment = _attachments[_selectedIndex];
    if (attachment.kind != OutgoingAttachmentKind.photo) return;
    final result = await Navigator.of(context).push<ImageEditResult>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ImageEditView(sourcePath: attachment.path),
      ),
    );
    if (!mounted || result == null) return;
    final updated = await resolveAttachmentDimensions(
      attachment.copyWith(
        path: result.path,
        clearPreviewBytes: true,
        clearDimensions: true,
      ),
    );
    if (!mounted) return;
    setState(() {
      _attachments[_selectedIndex] = updated;
      if (result.caption.trim().isNotEmpty) {
        _captionController.text = result.caption;
      }
    });
  }

  Future<void> _editVideoMetadata() async {
    if (_sendAsFile || _attachments.isEmpty) return;
    final attachment = _attachments[_selectedIndex];
    if (attachment.kind != OutgoingAttachmentKind.video) return;
    final startController = TextEditingController(
      text: attachment.startTimestamp.toString(),
    );
    var coverPath = attachment.coverPath;
    final video = VideoPlayerController.file(File(attachment.path));
    try {
      await video.initialize();
    } catch (_) {
      await video.dispose();
      if (mounted) showToast(context, 'Unable to open this video.');
      return;
    }
    if (!mounted) {
      await video.dispose();
      return;
    }
    final totalMs = video.value.duration.inMilliseconds;
    var trim = RangeValues(0, totalMs.toDouble());
    final result = await showModalBottomSheet<(String?, int, RangeValues)>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final c = context.colors;
          return SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: c.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(18),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Video presentation',
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 12),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () async {
                      final image = await ImagePicker().pickImage(
                        source: ImageSource.gallery,
                      );
                      if (image != null) {
                        setSheetState(() => coverPath = image.path);
                      }
                    },
                    child: Container(
                      height: 58,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      decoration: BoxDecoration(
                        color: c.card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          if (coverPath != null)
                            ClipRRect(
                              borderRadius: BorderRadius.circular(7),
                              child: Image.file(
                                File(coverPath!),
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                              ),
                            )
                          else
                            AppIcon(
                              HeroAppIcons.image,
                              size: 21,
                              color: AppTheme.brand,
                            ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              coverPath == null
                                  ? 'Choose video cover'
                                  : 'Change video cover',
                              style: TextStyle(
                                color: c.textPrimary,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (coverPath != null)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () =>
                                  setSheetState(() => coverPath = null),
                              child: AppIcon(
                                HeroAppIcons.circleXmark,
                                size: 19,
                                color: c.textTertiary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: startController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: c.card,
                      labelText: 'Start timestamp (seconds)',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  if (totalMs > 1000) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Text(
                          'Trim video',
                          style: TextStyle(
                            color: c.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${_clock((trim.start / 1000).floor())} – ${_clock((trim.end / 1000).ceil())}',
                          style: TextStyle(
                            color: c.textSecondary,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                    _MediaRangeSelector(
                      values: trim,
                      max: totalMs.toDouble(),
                      divisions: (video.value.duration.inSeconds * 4).clamp(
                        4,
                        600,
                      ),
                      onChanged: (value) => setSheetState(() => trim = value),
                    ),
                  ],
                  const SizedBox(height: 12),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(sheetContext).pop((
                      coverPath,
                      int.tryParse(startController.text.trim()) ?? 0,
                      trim,
                    )),
                    child: Container(
                      height: 48,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppTheme.brand,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        'Apply',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    startController.dispose();
    await video.dispose();
    if (!mounted || result == null) return;
    var path = attachment.path;
    final trimmed = result.$3.start > 1 || result.$3.end < totalMs - 1;
    if (trimmed) {
      try {
        path = await VideoTrimService.trim(
          path: path,
          start: Duration(milliseconds: result.$3.start.round()),
          end: Duration(milliseconds: result.$3.end.round()),
        );
      } catch (error) {
        if (mounted) showToast(context, error.toString());
        return;
      }
    }
    if (!mounted) return;
    setState(() {
      _attachments[_selectedIndex] = attachment.copyWith(
        path: path,
        duration: trimmed
            ? ((result.$3.end - result.$3.start) / 1000).ceil()
            : attachment.duration,
        coverPath: result.$1,
        clearCoverPath: result.$1 == null,
        startTimestamp: result.$2.clamp(0, 86400),
      );
    });
  }

  static String _clock(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

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
              if (_canSendAsFile) _sendAsFileControl(c),
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
              onTap:
                  !_sendAsFile &&
                      attachment.kind == OutgoingAttachmentKind.photo
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
          if (!_sendAsFile && attachment.kind == OutgoingAttachmentKind.photo)
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
          if (!_sendAsFile && attachment.kind == OutgoingAttachmentKind.video)
            Positioned(
              right: 8,
              top: 8,
              child: _mediaAction(
                key: const ValueKey('mediaPreviewVideoMetadata'),
                icon: HeroAppIcons.solidFileVideo,
                color: Colors.white,
                onTap: _editVideoMetadata,
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
            key: const ValueKey('mediaPreviewSend'),
            onLongPress: _configureAndSubmit,
          ),
        ],
      ),
    );
  }

  Widget _textAction(
    String label,
    Color color,
    VoidCallback onTap, {
    Key? key,
    VoidCallback? onLongPress,
  }) {
    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      onLongPress: onLongPress,
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

  bool get _canSendAsFile =>
      _attachments.isNotEmpty &&
      _attachments.every(
        (attachment) =>
            attachment.kind == OutgoingAttachmentKind.photo ||
            attachment.kind == OutgoingAttachmentKind.video ||
            attachment.kind == OutgoingAttachmentKind.animation,
      );

  Widget _sendAsFileControl(AppColors c) {
    return GestureDetector(
      key: const ValueKey('mediaPreviewSendAsFile'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _sendAsFile = !_sendAsFile),
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 6, 12, 2),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: _sendAsFile
              ? AppTheme.brand.withValues(alpha: 0.12)
              : c.searchFill,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: _sendAsFile
                ? AppTheme.brand.withValues(alpha: 0.42)
                : c.divider,
            width: 0.8,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _sendAsFile
                    ? AppTheme.brand
                    : AppTheme.brand.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(9),
              ),
              child: AppIcon(
                _sendAsFile ? HeroAppIcons.check : HeroAppIcons.solidFolder,
                size: 18,
                color: _sendAsFile ? Colors.white : AppTheme.brand,
              ),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStringKeys.composerSendAsFile.l10n(context),
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppStringKeys.composerSendAsFileDescription.l10n(context),
                    style: TextStyle(
                      color: c.textSecondary,
                      fontSize: 12,
                      height: 1.2,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
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

enum _MediaRangeThumb { start, end }

class _MediaRangeSelector extends StatefulWidget {
  const _MediaRangeSelector({
    required this.values,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final RangeValues values;
  final double max;
  final int divisions;
  final ValueChanged<RangeValues> onChanged;

  @override
  State<_MediaRangeSelector> createState() => _MediaRangeSelectorState();
}

class _MediaRangeSelectorState extends State<_MediaRangeSelector> {
  static const _thumbSize = 22.0;
  _MediaRangeThumb _activeThumb = _MediaRangeThumb.start;

  double _valueForPosition(double dx, double width) {
    final usableWidth = width - _thumbSize;
    final fraction = ((dx - _thumbSize / 2) / usableWidth).clamp(0.0, 1.0);
    final raw = widget.max * fraction;
    final step = widget.max / widget.divisions;
    return ((raw / step).round() * step).clamp(0.0, widget.max).toDouble();
  }

  void _chooseThumb(double dx, double width) {
    final value = _valueForPosition(dx, width);
    _activeThumb =
        (value - widget.values.start).abs() <= (value - widget.values.end).abs()
        ? _MediaRangeThumb.start
        : _MediaRangeThumb.end;
  }

  void _update(double dx, double width) {
    final value = _valueForPosition(dx, width);
    if (_activeThumb == _MediaRangeThumb.start) {
      widget.onChanged(
        RangeValues(value.clamp(0.0, widget.values.end), widget.values.end),
      );
    } else {
      widget.onChanged(
        RangeValues(
          widget.values.start,
          value.clamp(widget.values.start, widget.max),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final usableWidth = constraints.maxWidth - _thumbSize;
      final start = widget.values.start / widget.max;
      final end = widget.values.end / widget.max;
      return Semantics(
        label: 'Video trim range',
        value: '${(start * 100).round()}% to ${(end * 100).round()}%',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            _chooseThumb(details.localPosition.dx, constraints.maxWidth);
            _update(details.localPosition.dx, constraints.maxWidth);
          },
          onHorizontalDragStart: (details) =>
              _chooseThumb(details.localPosition.dx, constraints.maxWidth),
          onHorizontalDragUpdate: (details) =>
              _update(details.localPosition.dx, constraints.maxWidth),
          child: SizedBox(
            height: 44,
            child: Stack(
              alignment: Alignment.centerLeft,
              children: [
                Positioned(
                  left: _thumbSize / 2,
                  right: _thumbSize / 2,
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: context.colors.textTertiary.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Positioned(
                  left: _thumbSize / 2 + usableWidth * start,
                  width: usableWidth * (end - start),
                  child: Container(
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppTheme.brand,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Positioned(
                  left: usableWidth * start,
                  child: const _MediaRangeHandle(),
                ),
                Positioned(
                  left: usableWidth * end,
                  child: const _MediaRangeHandle(),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _MediaRangeHandle extends StatelessWidget {
  const _MediaRangeHandle();

  @override
  Widget build(BuildContext context) => Container(
    width: _MediaRangeSelectorState._thumbSize,
    height: _MediaRangeSelectorState._thumbSize,
    decoration: BoxDecoration(
      color: AppTheme.brand,
      shape: BoxShape.circle,
      border: Border.all(color: Colors.white, width: 2),
      boxShadow: const [
        BoxShadow(
          color: Color(0x33000000),
          blurRadius: 4,
          offset: Offset(0, 1),
        ),
      ],
    ),
  );
}
