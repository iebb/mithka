//
//  file_detail_view.dart
//
//  Full-screen file page shown when a document bubble is tapped, modeled on the reference app's
//  file viewer: a large type glyph + name + size, a live download progress bar
//  (downloaded / total) with a cancel button, then an 打开 (open) button once the
//  download completes. Drives TDLib downloadFile / cancelDownloadFile directly
//  and tracks progress from updateFile.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../components/toast.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

class FileDetailView extends StatefulWidget {
  const FileDetailView({super.key, required this.doc});
  final MessageDocument doc;

  @override
  State<FileDetailView> createState() => _FileDetailViewState();
}

class _FileDetailViewState extends State<FileDetailView> {
  StreamSubscription? _sub;
  int _downloaded = 0;
  int _total = 0;
  bool _done = false;
  String? _path;

  int get _fileId => widget.doc.file?.id ?? 0;

  @override
  void initState() {
    super.initState();
    _total = widget.doc.size;
    _start();
  }

  Future<void> _start() async {
    final id = _fileId;
    if (id == 0) return;
    _sub = TdClient.shared.subscribe().listen((u) {
      if (u.type != 'updateFile') return;
      final f = u.obj('file');
      if (f != null && f.integer('id') == id) _apply(f);
    });
    try {
      final resp = await TdClient.shared.query({
        '@type': 'downloadFile',
        'file_id': id,
        'priority': 32,
        'offset': 0,
        'limit': 0,
        'synchronous': false,
      });
      _apply(resp);
    } catch (_) {}
  }

  void _apply(Map<String, dynamic> file) {
    if (!mounted) return;
    final local = file.obj('local');
    final exp = file.integer('expected_size') ?? file.integer('size') ?? 0;
    final dl = local?.integer('downloaded_size') ?? 0;
    final done = local?.boolean('is_downloading_completed') == true;
    final path = local?.str('path');
    setState(() {
      if (exp > 0) _total = exp;
      if (dl > _downloaded) _downloaded = dl;
      if (done && path != null && path.isNotEmpty) {
        _done = true;
        _downloaded = _total;
        _path = path;
      }
    });
  }

  void _cancel() {
    final id = _fileId;
    if (id != 0) {
      TdClient.shared.send({
        '@type': 'cancelDownloadFile',
        'file_id': id,
        'only_if_pending': false,
      });
    }
    Navigator.of(context).pop();
  }

  Future<void> _open() async {
    final p = _path;
    if (p == null) return;
    final r = await OpenFilex.open(p);
    if (r.type != ResultType.done && mounted) {
      showToast(context, '没有可打开此文件的应用');
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final progress = _total > 0 ? (_downloaded / _total).clamp(0.0, 1.0) : 0.0;
    return Scaffold(
      backgroundColor: c.background,
      body: SafeArea(
        child: Column(
          children: [
            // Header: back + centered filename.
            SizedBox(
              height: 52,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 56),
                    child: Text(
                      widget.doc.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 17, color: c.textPrimary),
                    ),
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: FaIcon(
                          FontAwesomeIcons.chevronLeft,
                          size: 24,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _glyph(),
            const SizedBox(height: 18),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: Text(
                widget.doc.fileName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _bytes(_total),
              style: TextStyle(fontSize: 13, color: c.textSecondary),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 28, 52),
              child: _done ? _openButton() : _progress(progress),
            ),
          ],
        ),
      ),
    );
  }

  Widget _progress(double p) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '文件下载中…(${_bytes(_downloaded)}/${_bytes(_total)})',
          style: TextStyle(fontSize: 13, color: c.textSecondary),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: LinearProgressIndicator(
                  value: _downloaded > 0 ? p : null,
                  minHeight: 6,
                  backgroundColor: c.divider,
                  valueColor: const AlwaysStoppedAnimation(Color(0xFF8BC34A)),
                ),
              ),
            ),
            const SizedBox(width: 18),
            GestureDetector(
              onTap: _cancel,
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFF3B30),
                ),
                child: FaIcon(
                  FontAwesomeIcons.xmark,
                  size: 20,
                  color: Colors.white,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _openButton() {
    return GestureDetector(
      onTap: _open,
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: AppTheme.brandGradient,
          borderRadius: BorderRadius.circular(25),
        ),
        child: const Text(
          '打开',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  /// custom large file glyph: a neutral rounded square + doc icon + extension.
  Widget _glyph() {
    return Container(
      width: 100,
      height: 100,
      decoration: BoxDecoration(
        color: const Color(0xFF8E99A3),
        borderRadius: BorderRadius.circular(22),
      ),
      alignment: Alignment.center,
      child: Stack(
        alignment: Alignment.center,
        children: [
          FaIcon(FontAwesomeIcons.solidFile, size: 60, color: Colors.white),
          if (widget.doc.ext.isNotEmpty)
            Positioned(
              bottom: 24,
              child: Text(
                widget.doc.ext.toUpperCase(),
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF8E99A3),
                ),
              ),
            ),
        ],
      ),
    );
  }

  static String _bytes(int b) {
    if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(2)}MB';
    if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(1)}KB';
    return '${b}B';
  }
}
