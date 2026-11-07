import 'dart:io';

import '../chat/media_download_service.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import 'download_storage.dart';

/// Only a user-initiated save copies bytes out of TDLib's managed cache.
class AndroidDownloadSaver {
  static Future<MediaDownloadOutcome> save({
    required int accountSlot,
    required int chatId,
    required int messageId,
    required int fileId,
    required String name,
    required String mimeType,
    TdClient? client,
  }) async {
    final lease = (client ?? TdClient.shared).retainAccountSlot(accountSlot);
    if (lease == null) {
      return (result: MediaDownloadResult.failed, folder: null);
    }
    try {
      final properties = await lease.query({
        '@type': 'getMessageProperties',
        'chat_id': chatId,
        'message_id': messageId,
      });
      if (properties.boolean('can_be_saved') != true) {
        return (result: MediaDownloadResult.unsupported, folder: null);
      }
      final message = await lease.query({
        '@type': 'getMessage',
        'chat_id': chatId,
        'message_id': messageId,
      });
      if (message['self_destruct_type'] != null ||
          (message.dbl('self_destruct_in') ?? 0) > 0 ||
          !_containsFile(message.obj('content'), fileId)) {
        return (result: MediaDownloadResult.unsupported, folder: null);
      }
      if (await DownloadStorage.saveFolder() == null) {
        if (await DownloadStorage.pickSaveFolder() == null) {
          return (result: MediaDownloadResult.cancelled, folder: null);
        }
      }
      final file = await lease.query({'@type': 'getFile', 'file_id': fileId});
      final local = file.obj('local');
      final path = local?.str('path');
      if (local?.boolean('is_downloading_completed') != true ||
          path == null ||
          !await File(path).exists()) {
        return (result: MediaDownloadResult.failed, folder: null);
      }
      final safeName = name.replaceAll(RegExp(r'[/\\\x00-\x1f]'), '_').trim();
      final folder = await DownloadStorage.exportFile(
        path,
        name: safeName.isEmpty ? 'file_$fileId' : safeName,
        mimeType: mimeType,
      );
      return (result: MediaDownloadResult.saved, folder: folder);
    } catch (_) {
      return (result: MediaDownloadResult.failed, folder: null);
    } finally {
      await lease.release();
    }
  }

  static bool _containsFile(dynamic value, int id) {
    if (value is Map) {
      if (value['@type'] == 'file' && jsonInt(value['id']) == id) return true;
      return value.values.any((child) => _containsFile(child, id));
    }
    return value is List && value.any((child) => _containsFile(child, id));
  }
}
