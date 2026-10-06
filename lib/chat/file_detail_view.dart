//
//  file_detail_view.dart
//
//  Full-screen file page shown when a document bubble is tapped, modeled on the reference app's
//  file viewer: a large type glyph + name + size, a live download progress bar
//  (downloaded / total) with a cancel button, then an 打开 (open) button once the
//  download completes. Explicit message downloads join the global task list;
//  progress is tracked from updateFile.
//

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/document_file_icon.dart';
import '../components/toast.dart';
import '../settings/data_storage_service.dart';
import '../settings/retain_download_button.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_image_loader.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import 'file_opener.dart';

class FileDetailView extends StatefulWidget {
  const FileDetailView({
    super.key,
    required this.doc,
    this.chatId,
    this.messageId,
    this.accountSlot,
  });
  final MessageDocument doc;
  final int? chatId;
  final int? messageId;
  final int? accountSlot;

  @override
  State<FileDetailView> createState() => _FileDetailViewState();
}

class _FileDetailViewState extends State<FileDetailView> {
  StreamSubscription? _sub;
  int _downloaded = 0;
  int _total = 0;
  bool _done = false;
  String? _path;
  late final int _accountSlot;
  late final Future<void> _startFuture;
  bool _canceling = false;

  int get _fileId => widget.doc.file?.id ?? 0;

  @override
  void initState() {
    super.initState();
    _accountSlot = widget.accountSlot ?? TdClient.shared.activeSlot;
    _total = widget.doc.size;
    _startFuture = _start();
  }

  Future<void> _start() async {
    final id = _fileId;
    if (id == 0) return;
    _sub = TdClient.shared
        .subscribeAll()
        .where(
          (u) =>
              u.type == 'updateFile' &&
              TdClient.shared.slotForClient(u.integer('@client_id') ?? -1) ==
                  _accountSlot,
        )
        .listen((u) {
          final f = u.obj('file');
          if (f != null && f.integer('id') == id) _apply(f);
        });
    try {
      final existing = await TdClient.shared.queryForSlot({
        '@type': 'getFile',
        'file_id': id,
      }, _accountSlot);
      _apply(existing);
      if (existing.obj('local')?.boolean('is_downloading_completed') == true) {
        return;
      }
      final chatId = widget.chatId;
      final messageId = widget.messageId;
      final managed =
          chatId != null && chatId != 0 && messageId != null && messageId > 0;
      final resp = managed
          ? await DataStorageService(
              TdClient.shared,
              _accountSlot,
            ).addDownload(fileId: id, chatId: chatId, messageId: messageId)
          : await TdFileCenter.shared.downloadPriorityFile(
              id,
              accountSlot: _accountSlot,
            );
      if (resp != null) _apply(resp);
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    }
  }

  void _apply(Map<String, dynamic> file) {
    if (!mounted) return;
    final local = file.obj('local');
    final size = file.int64('size') ?? 0;
    final exp = size > 0 ? size : file.int64('expected_size') ?? 0;
    final dl = local?.integer('downloaded_size') ?? 0;
    final done = local?.boolean('is_downloading_completed') == true;
    final path = local?.str('path');
    setState(() {
      if (exp > 0) _total = exp;
      _downloaded = dl;
      _done = done && path != null && path.isNotEmpty;
      _path = _done ? path : null;
      if (done && path != null && path.isNotEmpty) {
        _downloaded = _total;
      }
    });
  }

  Future<void> _cancel() async {
    if (_canceling) return;
    setState(() => _canceling = true);
    final id = _fileId;
    try {
      // A fast cancel must not race the addFileToDownloads response and leave
      // a newly registered task running after this page closes.
      await _startFuture;
      if (id != 0) {
        await DataStorageService(
          TdClient.shared,
          _accountSlot,
        ).pauseDownload(id);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _canceling = false);
    }
  }

  Future<void> _open() async {
    final p = _path;
    if (p == null) return;
    await openDownloadedFile(
      context,
      p,
      mimeType: mimeForExtension(widget.doc.ext),
    );
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
                        child: AppIcon(
                          HeroAppIcons.chevronLeft,
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
              child: _done
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _openButton(),
                        const SizedBox(height: 10),
                        RetainDownloadButton(
                          key: ValueKey('file-detail-retain-$_fileId'),
                          accountSlot: _accountSlot,
                          fileId: _fileId,
                          title: widget.doc.fileName,
                          isVideo: false,
                          showLabel: true,
                        ),
                      ],
                    )
                  : _progress(progress),
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
          AppStrings.t(AppStringKeys.fileDetailDownloadProgress, {
            'value1': _bytes(_downloaded),
            'value2': _bytes(_total),
          }),
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
              key: const ValueKey('file-detail-pause'),
              onTap: _canceling ? null : _cancel,
              child: Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFFFF3B30),
                ),
                child: const AppIcon(
                  HeroAppIcons.xmark,
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
          color: AppTheme.brand,
          borderRadius: BorderRadius.circular(25),
        ),
        child: Text(
          AppStrings.t(AppStringKeys.fileDetailOpen),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: AppTheme.onBrand,
          ),
        ),
      ),
    );
  }

  /// Large version of the same extension-colored file glyph used in messages.
  Widget _glyph() {
    return SizedBox(
      width: 100,
      height: 100,
      child: Center(
        child: DocumentFileIcon(
          fileName: widget.doc.fileName,
          extension: widget.doc.ext,
          size: 76,
        ),
      ),
    );
  }

  static String _bytes(int b) {
    if (b >= 1 << 20) return '${(b / (1 << 20)).toStringAsFixed(2)}MB';
    if (b >= 1 << 10) return '${(b / (1 << 10)).toStringAsFixed(1)}KB';
    return '${b}B';
  }
}
