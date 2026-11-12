import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/media_download_service.dart';
import 'package:mithka/settings/android_download_saver.dart';
import 'package:mithka/settings/download_storage.dart';
import 'package:mithka/tdlib/td_client.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late File localFile;
  late List<Map<String, dynamic>> queries;
  const slot = 1;
  const chatId = 1001;
  const messageId = 2002;
  const fileId = 3003;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('mithka-saver-test-');
    localFile = File('${temporary.path}/sample.pdf')
      ..writeAsStringSync('pdf-bytes');
    queries = [];
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DownloadStorage.channel, null);
  });

  TdClient createFakeClient({
    bool canBeSaved = true,
    Map<String, dynamic>? selfDestructType,
    double selfDestructIn = 0.0,
    bool containsFile = true,
    bool completed = true,
    bool fileExists = true,
  }) {
    final client = TdClient.forTesting();
    client.configureProxy(
      TdClientProxyTransport(
        accountSlot: slot,
        query: (request) async {
          queries.add(request);
          return switch (request['@type']) {
            'getMessageProperties' => {
              '@type': 'messageProperties',
              'can_be_saved': canBeSaved,
            },
            'getMessage' => {
              '@type': 'message',
              'id': messageId,
              'chat_id': chatId,
              'self_destruct_type': selfDestructType,
              'self_destruct_in': selfDestructIn,
              'content': containsFile
                  ? {
                      '@type': 'messageDocument',
                      'document': {
                        '@type': 'document',
                        'file_name': 'sample.pdf',
                        'document': {'@type': 'file', 'id': fileId},
                      },
                    }
                  : {'@type': 'messageText'},
            },
            'getFile' => {
              '@type': 'file',
              'id': fileId,
              'local': {
                'path': fileExists
                    ? localFile.path
                    : '${temporary.path}/nonexistent.pdf',
                'is_downloading_completed': completed,
              },
            },
            _ => throw StateError('Unexpected query: ${request['@type']}'),
          };
        },
        send: (_) async {},
        updates: const Stream.empty(),
      ),
    );
    return client;
  }

  void setupChannel({
    String? currentFolder,
    String? pickedFolder,
    String? exportedFolder,
  }) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(DownloadStorage.channel, (call) async {
          return switch (call.method) {
            'saveFolder' => currentFolder,
            'pickSaveFolder' => pickedFolder,
            'exportFile' => exportedFolder ?? 'Downloads',
            _ => null,
          };
        });
  }

  test('rejects message when can_be_saved is false', () async {
    setupChannel(currentFolder: 'Downloads');
    final client = createFakeClient(canBeSaved: false);
    final outcome = await AndroidDownloadSaver.save(
      accountSlot: slot,
      chatId: chatId,
      messageId: messageId,
      fileId: fileId,
      name: 'sample.pdf',
      mimeType: 'application/pdf',
      client: client,
    );
    expect(outcome.result, MediaDownloadResult.unsupported);
  });

  test('rejects self-destructing message', () async {
    setupChannel(currentFolder: 'Downloads');
    final client = createFakeClient(selfDestructIn: 10.0);
    final outcome = await AndroidDownloadSaver.save(
      accountSlot: slot,
      chatId: chatId,
      messageId: messageId,
      fileId: fileId,
      name: 'sample.pdf',
      mimeType: 'application/pdf',
      client: client,
    );
    expect(outcome.result, MediaDownloadResult.unsupported);
  });

  test('rejects message not containing target fileId', () async {
    setupChannel(currentFolder: 'Downloads');
    final client = createFakeClient(containsFile: false);
    final outcome = await AndroidDownloadSaver.save(
      accountSlot: slot,
      chatId: chatId,
      messageId: messageId,
      fileId: fileId,
      name: 'sample.pdf',
      mimeType: 'application/pdf',
      client: client,
    );
    expect(outcome.result, MediaDownloadResult.unsupported);
  });

  test('exports file successfully to user folder', () async {
    setupChannel(currentFolder: 'Documents', exportedFolder: 'Documents');
    final client = createFakeClient();
    final outcome = await AndroidDownloadSaver.save(
      accountSlot: slot,
      chatId: chatId,
      messageId: messageId,
      fileId: fileId,
      name: 'sample.pdf',
      mimeType: 'application/pdf',
      client: client,
    );
    expect(outcome.result, MediaDownloadResult.saved);
    expect(outcome.folder, 'Documents');
  });

  test(
    'prompts for folder when none selected and handles cancellation',
    () async {
      setupChannel();
      final client = createFakeClient();
      final outcome = await AndroidDownloadSaver.save(
        accountSlot: slot,
        chatId: chatId,
        messageId: messageId,
        fileId: fileId,
        name: 'sample.pdf',
        mimeType: 'application/pdf',
        client: client,
      );
      expect(outcome.result, MediaDownloadResult.cancelled);
    },
  );
}
