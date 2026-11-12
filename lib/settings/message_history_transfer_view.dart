//
//  message_history_transfer_view.dart
//
//  消息历史导出/导入（Telegram §1.4 功能，自建构建专属）：整个镜像库导出
//  为一个自描述 JSON 文件（含 base64 媒体快照），或从这样的文件恢复。
//  导出的是当前活跃账号的镜像；导入整库替换当前账号的镜像。
//

import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../components/app_confirm_dialog.dart';
import '../components/app_icons.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../config/build_flags.dart';
import '../history/message_history_store.dart';
import '../l10n/app_localizations.dart';

class MessageHistoryTransferView extends StatefulWidget {
  const MessageHistoryTransferView({super.key});

  @override
  State<MessageHistoryTransferView> createState() =>
      _MessageHistoryTransferViewState();
}

class _MessageHistoryTransferViewState
    extends State<MessageHistoryTransferView> {
  bool _working = false;

  bool get _busy => _working;

  @override
  Widget build(BuildContext context) {
    if (!allowTelegramTosViolations) return const SizedBox.shrink();
    return SettingsPageScaffold(
      title: AppStringKeys.historyTransferTitle,
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsCard.rows(
            rows: [
              SettingsRow(
                key: const ValueKey('history-transfer-export'),
                title: AppStringKeys.historyExportAction.l10n(context),
                subtitle: AppStringKeys.historyExportSubtitle.l10n(context),
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.upload),
                enabled: !_busy,
                onTap: _export,
              ),
              SettingsRow(
                key: const ValueKey('history-transfer-import'),
                title: AppStringKeys.historyImportAction.l10n(context),
                subtitle: AppStringKeys.historyImportSubtitle.l10n(context),
                leading: const SettingsLeadingIcon(icon: HeroAppIcons.download),
                enabled: !_busy,
                onTap: _import,
              ),
            ],
          ),
          const SettingsNote(text: AppStringKeys.historyTransferNote),
        ],
      ),
    );
  }

  Future<void> _export() async {
    if (_working) return;
    final exportTitle = AppStringKeys.historyExportAction.l10n(context);
    setState(() => _working = true);
    int entryCount = 0;
    try {
      final store = MessageHistoryStore.shared;
      final document = await store.exportAccount();
      entryCount = (document['entries'] as List).length;
      final encoded = const JsonEncoder.withIndent('  ').convert(document);
      final stamp = _exportStamp(DateTime.now());
      final fileName = 'kept-history-$stamp.json';
      // Android SAF: the returned uri.path is not directly writable and the
      // plugin may truncate the target first — pass the bytes so the plugin
      // itself writes the file, and never touch the path afterwards.
      final encodedBytes = Uint8List.fromList(utf8.encode(encoded));
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: exportTitle,
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: const ['json'],
        bytes: encodedBytes,
      );
      if (destination == null || destination.trim().isEmpty) {
        return; // cancelled — not an error
      }
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.historyExportedToast, {
          'value1': '$entryCount',
        }),
      );
    } catch (error) {
      if (mounted) showToast(context, error.toString());
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _import() async {
    if (_working) return;
    final importTitle = AppStringKeys.historyImportAction.l10n(context);
    final picked = await FilePicker.platform.pickFiles(
      dialogTitle: importTitle,
      type: FileType.custom,
      allowedExtensions: const ['json'],
      withData: true,
    );
    if (!mounted) return;
    final file = picked?.files.singleOrNull;
    if (file == null) return;
    final bytes = file.bytes;
    if (bytes == null) {
      if (mounted) {
        showToast(
          context,
          AppStringKeys.historyImportFailedToast.l10n(context),
        );
      }
      return;
    }
    if (!mounted) return;
    final confirmed = await showAppConfirmDialog(
      context,
      title: AppStringKeys.historyImportConfirmTitle,
      message: AppStringKeys.historyImportConfirmMessage,
      confirmText: AppStringKeys.historyImportAction,
      destructive: true,
    );
    if (!confirmed || !mounted) return;
    setState(() => _working = true);
    try {
      final document = jsonDecode(utf8.decode(bytes));
      if (document is! Map<String, Object?>) {
        throw const FormatException('Not a kept-message history export');
      }
      final restored = await MessageHistoryStore.shared.importAccount(document);
      if (!mounted) return;
      showToast(
        context,
        AppStrings.t(AppStringKeys.historyImportedToast, {
          'value1': '$restored',
        }),
      );
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          AppStringKeys.historyImportFailedToast.l10n(context),
        );
      }
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  static String _exportStamp(DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}';
  }
}
