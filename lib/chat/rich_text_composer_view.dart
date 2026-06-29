import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/app_theme.dart';

class RichTextComposerResult {
  const RichTextComposerResult({required this.text, required this.media});

  final String text;
  final List<XFile> media;
}

class RichTextComposerView extends StatefulWidget {
  const RichTextComposerView({
    super.key,
    required this.initialText,
    this.title = '分享',
    this.submitText = '发布',
    this.hintText = '输入 Markdown 或富文本内容',
    this.allowMedia = true,
  });

  final String initialText;
  final String title;
  final String submitText;
  final String hintText;
  final bool allowMedia;

  @override
  State<RichTextComposerView> createState() => _RichTextComposerViewState();
}

class _RichTextComposerViewState extends State<RichTextComposerView> {
  late final TextEditingController _controller;
  final _picker = ImagePicker();
  final _media = <XFile>[];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialText);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _wrap(String left, [String? right]) {
    right ??= left;
    final value = _controller.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final selected = value.text.substring(start, end);
    final next = value.text.replaceRange(start, end, '$left$selected$right');
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(
        offset: start + left.length + selected.length,
      ),
    );
  }

  void _prefixLine(String prefix) {
    final value = _controller.value;
    final offset = value.selection.isValid
        ? value.selection.start
        : value.text.length;
    final lineStart = value.text.lastIndexOf('\n', offset - 1) + 1;
    final next = value.text.replaceRange(lineStart, lineStart, prefix);
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: offset + prefix.length),
    );
  }

  void _submit() {
    Navigator.of(context).pop(
      RichTextComposerResult(
        text: _controller.text,
        media: List<XFile>.of(_media),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: 54,
              child: Row(
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text('取消', style: TextStyle(color: c.textPrimary)),
                  ),
                  Expanded(
                    child: Text(
                      widget.title,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _submit,
                    child: Text(widget.submitText),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.divider),
            _toolbar(c),
            if (widget.allowMedia) _mediaStrip(c),
            Expanded(
              child: TextField(
                controller: _controller,
                autofocus: true,
                maxLines: null,
                expands: true,
                textAlignVertical: TextAlignVertical.top,
                style: TextStyle(
                  fontSize: 16,
                  height: 1.4,
                  color: c.textPrimary,
                ),
                decoration: InputDecoration(
                  contentPadding: const EdgeInsets.all(16),
                  border: InputBorder.none,
                  hintText: widget.hintText,
                  hintStyle: TextStyle(color: c.textTertiary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar(AppColors c) {
    return Container(
      height: 44,
      color: c.navBar,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        children: [
          _formatButton(c, 'B', () => _wrap('**')),
          _formatButton(c, 'I', () => _wrap('*')),
          _formatButton(c, 'U', () => _wrap('__')),
          _formatButton(c, 'S', () => _wrap('~~')),
          _formatButton(c, '</>', () => _wrap('`')),
          _formatButton(c, 'H', () => _prefixLine('## ')),
          _formatButton(c, '•', () => _prefixLine('- ')),
          _formatButton(c, '引用', () => _wrap('> ', '')),
        ],
      ),
    );
  }

  Widget _mediaStrip(AppColors c) {
    if (_media.isEmpty) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _pickMedia,
          icon: FaIcon(FontAwesomeIcons.image, size: 20),
          label: const Text('照片/视频'),
        ),
      );
    }
    return SizedBox(
      height: 94,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        scrollDirection: Axis.horizontal,
        itemCount: _media.length + (_media.length < 9 ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (index == _media.length) return _addMediaTile(c);
          return _mediaTile(c, index);
        },
      ),
    );
  }

  Widget _addMediaTile(AppColors c) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _pickMedia,
      child: Container(
        width: 84,
        height: 84,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(8),
        ),
        child: FaIcon(FontAwesomeIcons.plus, color: c.textTertiary),
      ),
    );
  }

  Widget _mediaTile(AppColors c, int index) {
    final item = _media[index];
    final isVideo = _isVideoPath(item.path);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.file(
            File(item.path),
            width: 84,
            height: 84,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => Container(
              width: 84,
              height: 84,
              color: c.searchFill,
              child: Icon(
                isVideo
                    ? FontAwesomeIcons.solidFileVideo.data
                    : FontAwesomeIcons.image.data,
                color: c.textTertiary,
              ),
            ),
          ),
        ),
        if (isVideo)
          Positioned.fill(
            child: Center(
              child: FaIcon(
                FontAwesomeIcons.play,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        Positioned(
          top: 4,
          right: 4,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _media.removeAt(index)),
            child: Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                shape: BoxShape.circle,
              ),
              child: FaIcon(
                FontAwesomeIcons.xmark,
                size: 12,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickMedia() async {
    try {
      final picked = await _picker.pickMultipleMedia();
      if (picked.isEmpty || !mounted) return;
      final remaining = 9 - _media.length;
      setState(() => _media.addAll(picked.take(remaining)));
    } catch (_) {}
  }

  Widget _formatButton(AppColors c, String label, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: TextButton(
        onPressed: onTap,
        child: Text(label, style: TextStyle(color: c.textPrimary)),
      ),
    );
  }

  bool _isVideoPath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.m4v') ||
        lower.endsWith('.webm');
  }
}
