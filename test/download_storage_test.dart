import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/bot_api/bot_api_store.dart';
import 'package:mithka/settings/download_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory temporary;
  late Directory supportDir;
  late Directory externalDir;
  late SharedPreferences prefs;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp(
      'mithka-download-storage-test-',
    );
    supportDir = Directory('${temporary.path}/support')
      ..createSync(recursive: true);
    externalDir = Directory('${temporary.path}/external')
      ..createSync(recursive: true);
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();
    DownloadStorage.currentRoot = null;
    DownloadStorage.migrationFailed = false;
  });

  tearDown(() async {
    if (await temporary.exists()) {
      await temporary.delete(recursive: true);
    }
  });

  test(
    'prepare migrates tdlib, bot-api, and retained downloads to destination',
    () async {
      final slot0Dir = Directory('${supportDir.path}/tdlib/files')
        ..createSync(recursive: true);
      final slot1Dir = Directory('${supportDir.path}/tdlib/account-1/files')
        ..createSync(recursive: true);
      final botDir = Directory('${supportDir.path}/bot-api/account-2/files')
        ..createSync(recursive: true);
      final retainedDir = Directory('${supportDir.path}/retained-downloads-v1')
        ..createSync(recursive: true);

      File('${slot0Dir.path}/photo.jpg').writeAsStringSync('slot0-data');
      File('${slot1Dir.path}/video.mp4').writeAsStringSync('slot1-data');
      File('${botDir.path}/doc.pdf').writeAsStringSync('bot-data');
      File('${retainedDir.path}/saved.png').writeAsStringSync('retained-data');

      final copied = <String, String>{};
      Future<void> fakeCopy(String src, String dst) async {
        copied[src] = dst;
        final sourceDir = Directory(src);
        final targetDir = Directory(dst)..createSync(recursive: true);
        for (final entity in sourceDir.listSync()) {
          if (entity is File) {
            File(
              '${targetDir.path}/${entity.uri.pathSegments.last}',
            ).writeAsBytesSync(entity.readAsBytesSync());
          }
        }
      }

      final targetRoot = '${externalDir.path}/mithka-downloads-v1';
      await prefs.setString(DownloadStorage.selectedKey, targetRoot);

      final resolved = await DownloadStorage.prepare(
        support: supportDir,
        prefs: prefs,
        availableRoots: [targetRoot],
        copyDirectory: fakeCopy,
      );

      expect(resolved, targetRoot);
      expect(DownloadStorage.currentRoot, targetRoot);
      expect(DownloadStorage.migrationFailed, isFalse);
      expect(prefs.getString(DownloadStorage.activeKey), targetRoot);
      expect(prefs.getString(DownloadStorage.cleanupKey), isNull);

      // Verify files copied to target
      expect(
        File('$targetRoot/tdlib/files/photo.jpg').readAsStringSync(),
        'slot0-data',
      );
      expect(
        File('$targetRoot/tdlib/account-1/files/video.mp4').readAsStringSync(),
        'slot1-data',
      );
      expect(
        File('$targetRoot/bot-api/account-2/files/doc.pdf').readAsStringSync(),
        'bot-data',
      );
      expect(
        File('$targetRoot/retained-downloads-v1/saved.png').readAsStringSync(),
        'retained-data',
      );

      // Verify old source dirs were cleaned up
      expect(slot0Dir.existsSync(), isFalse);
      expect(slot1Dir.existsSync(), isFalse);
      expect(botDir.existsSync(), isFalse);
      expect(retainedDir.existsSync(), isFalse);
    },
  );

  test(
    'prepare handles migration failure cleanly without losing files',
    () async {
      final slot0Dir = Directory('${supportDir.path}/tdlib/files')
        ..createSync(recursive: true);
      final originalFile = File('${slot0Dir.path}/photo.jpg')
        ..writeAsStringSync('original-data');

      final targetRoot = '${externalDir.path}/mithka-downloads-v1';
      await prefs.setString(DownloadStorage.selectedKey, targetRoot);

      Future<void> failingCopy(String src, String dst) async {
        throw const FileSystemException('Disk full simulated');
      }

      final resolved = await DownloadStorage.prepare(
        support: supportDir,
        prefs: prefs,
        availableRoots: [targetRoot],
        copyDirectory: failingCopy,
      );

      expect(resolved, supportDir.path);
      expect(DownloadStorage.currentRoot, supportDir.path);
      expect(DownloadStorage.migrationFailed, isTrue);
      expect(prefs.getString(DownloadStorage.activeKey), isNull);

      // Original files remain intact
      expect(originalFile.existsSync(), isTrue);
      expect(originalFile.readAsStringSync(), 'original-data');
    },
  );

  test('prepare recovers from interrupted cleanup using journal', () async {
    final targetRoot = '${externalDir.path}/mithka-downloads-v1';
    Directory(targetRoot).createSync(recursive: true);
    final staleDir = Directory('${supportDir.path}/old-data')
      ..createSync(recursive: true);
    File('${staleDir.path}/leftover.bin').writeAsStringSync('stale');

    await prefs.setString(DownloadStorage.activeKey, targetRoot);
    await prefs.setString(
      DownloadStorage.cleanupKey,
      jsonEncode({
        'target': targetRoot,
        'sources': [staleDir.path],
      }),
    );

    final resolved = await DownloadStorage.prepare(
      support: supportDir,
      prefs: prefs,
      availableRoots: [targetRoot],
    );

    expect(resolved, targetRoot);
    expect(staleDir.existsSync(), isFalse);
    expect(prefs.getString(DownloadStorage.cleanupKey), isNull);
  });

  test(
    'BotApiStore.relocateMedia updates local paths when destination exists',
    () async {
      final dbFile = File('${temporary.path}/history.sqlite3');
      final store = BotApiStore(dbFile.path);
      await store.open();

      final oldMediaDir = Directory('${temporary.path}/old-media')
        ..createSync(recursive: true);
      final newMediaDir = Directory('${temporary.path}/new-media')
        ..createSync(recursive: true);

      final oldFile = File('${oldMediaDir.path}/100.jpg')
        ..writeAsStringSync('old-data');
      final record = store.registerFile(
        botFileId: 'bot-100',
        uniqueId: 'uniq-100',
        size: 8,
      );
      store.updateFile(id: record.id, localPath: oldFile.path);
      expect(store.file(record.id)!.localPath, oldFile.path);

      // Copy to new directory
      final newFile = File('${newMediaDir.path}/100.jpg')
        ..writeAsStringSync('new-data');

      store.relocateMedia(newMediaDir.path);
      expect(store.file(record.id)!.localPath, newFile.path);

      store.close();
    },
  );
}
