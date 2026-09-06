import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/update/desktop_updater.dart';
import 'package:mithka/update/release_feed.dart';

List<int> appImageHeader(int machine) => List<int>.filled(64, 0)
  ..setRange(0, 6, [0x7f, 0x45, 0x4c, 0x46, 2, 1])
  ..setRange(8, 11, [0x41, 0x49, 2])
  ..[18] = machine;

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync("mithka's update "));
  tearDown(() => root.deleteSync(recursive: true));

  test('AppImage layout stages beside the original and preserves its name', () {
    final layout = DesktopInstallLayout.fromExecutable(
      executablePath: '/tmp/.mount_mithka/usr/bin/mithka',
      environment: const {'APPIMAGE': '/home/u/My Apps/Custom.AppImage'},
      isLinux: true,
    );
    expect(layout.isAppImage, isTrue);
    expect(layout.launcher.path, '/home/u/My Apps/Custom.AppImage');
    expect(layout.parentDirectory.path, '/home/u/My Apps');
    final unpacked = DesktopInstallLayout.fromExecutable(
      executablePath: '/home/u/Mithka/mithka',
      environment: const {},
      isLinux: true,
    );
    expect(unpacked.isAppImage, isFalse);
    expect(unpacked.parentDirectory.path, '/home/u');
  });

  test('only accepts a type-2 AppImage for the target architecture', () async {
    final file = File('${root.path}/package');
    for (final (abi, machine) in [(Abi.linuxX64, 62), (Abi.linuxArm64, 183)]) {
      file.writeAsBytesSync(appImageHeader(machine));
      await DesktopUpdater.validateAppImage(file, abi: abi);
      await expectLater(
        DesktopUpdater.validateAppImage(
          file,
          abi: machine == 62 ? Abi.linuxArm64 : Abi.linuxX64,
        ),
        throwsA(isA<DesktopUpdateException>()),
      );
    }
    for (final bytes in [
      <int>[],
      'not an AppImage'.codeUnits,
      appImageHeader(62)..[10] = 1,
      appImageHeader(62)..[4] = 1,
    ]) {
      file.writeAsBytesSync(bytes);
      await expectLater(
        DesktopUpdater.validateAppImage(file, abi: Abi.linuxX64),
        throwsA(isA<DesktopUpdateException>()),
      );
    }
  });

  test(
    'restores the launcher environment before starting the helper',
    () async {
      final bin = Directory('${root.path}/usr/bin')
        ..createSync(recursive: true);
      final hooks = Directory('${root.path}/apprun-hooks')..createSync();
      File('${hooks.path}/gtk.sh').writeAsStringSync(
        'export GTK_PATH="$root/mounted/gtk"\nexport GTK_THEME=Adwaita\n',
      );
      final output = File('${root.path}/environment');
      final launcher = File('${bin.path}/mithka')
        ..writeAsStringSync('#!/bin/sh\nenv > "\$1"\n');
      await Process.run('chmod', ['0755', launcher.path]);
      final result = await Process.run(
        '/bin/bash',
        ['linux/appimage/AppRun', output.path],
        environment: {
          'PATH': Platform.environment['PATH']!,
          'APPDIR': root.path,
          'APPIMAGE': '${root.path}/Mithka.AppImage',
          'GTK_THEME': '',
          'LD_LIBRARY_PATH': '/original/lib',
          'DISPLAY': ':42',
        },
        includeParentEnvironment: false,
      );
      expect(result.exitCode, 0, reason: '${result.stderr}');
      final bundled = <String, String>{};
      for (final line in output.readAsLinesSync()) {
        final separator = line.indexOf('=');
        if (separator > 0) {
          bundled[line.substring(0, separator)] = line.substring(separator + 1);
        }
      }
      expect(bundled['LD_LIBRARY_PATH'], contains(root.path));
      final restored = appImageUpdateEnvironment(bundled);
      expect(restored['PATH'], Platform.environment['PATH']);
      expect(restored['LD_LIBRARY_PATH'], '/original/lib');
      expect(restored['GTK_THEME'], '');
      expect(restored['DISPLAY'], ':42');
      expect(restored, isNot(contains('GTK_PATH')));
      expect(restored, isNot(contains('APPIMAGE')));
      expect(restored, isNot(contains('APPDIR')));
      expect(
        restored.keys.any((key) => key.startsWith('MITHKA_APPIMAGE_')),
        isFalse,
      );
    },
  );

  for (final missingStage in [false, true]) {
    test(
      missingStage
          ? 'failed file swap preserves and relaunches old build'
          : 'file swap waits for exit, preserves siblings, and relaunches',
      () async {
        final original = File('${root.path}/Custom Mithka.AppImage');
        String executable(String version) =>
            '#!/bin/sh\necho $version > "\$0.ran"\n';
        original.writeAsStringSync(executable('old'));
        await Process.run('chmod', ['0755', original.path]);
        final sibling = File('${root.path}/other-file')
          ..writeAsStringSync('keep');
        final portableHome = Directory('${original.path}.home')..createSync();
        final work = Directory('${root.path}/work')..createSync();
        final staged = File('${work.path}/package.AppImage');
        if (!missingStage) {
          staged.writeAsStringSync(executable('new'));
          await Process.run('chmod', ['0755', staged.path]);
        }
        final running = await Process.start('sleep', ['30']);
        final script = File('${root.path}/apply.sh')
          ..writeAsStringSync(
            buildAppImageUpdateScript(
              processId: running.pid,
              appImagePath: original.path,
              stagedPath: staged.path,
              workDirectory: work.path,
            ),
          );
        final helper = Process.run('/bin/sh', [script.path]);
        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(original.readAsStringSync(), executable('old'));
        running.kill();
        await running.exitCode;
        final result = await helper;
        expect(
          result.exitCode,
          missingStage ? 1 : 0,
          reason: '${result.stderr}',
        );
        expect(
          original.readAsStringSync(),
          executable(missingStage ? 'old' : 'new'),
        );
        expect(sibling.readAsStringSync(), 'keep');
        expect(portableHome.existsSync(), isTrue);
        expect(work.existsSync(), isFalse);
        final relaunched = File('${original.path}.ran');
        for (var i = 0; i < 100 && !relaunched.existsSync(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        expect(
          relaunched.readAsStringSync().trim(),
          missingStage ? 'old' : 'new',
        );
      },
    );
  }

  test(
    'downloads and verifies an AppImage without extracting or replacing it',
    () async {
      final bytes = appImageHeader(Abi.current() == Abi.linuxArm64 ? 183 : 62);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((request) async {
        request.response.add(bytes);
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));
      final original = File('${root.path}/Mithka.AppImage')
        ..writeAsStringSync('old');
      final layout = DesktopInstallLayout(
        installDirectory: root,
        launcher: original,
        isAppImage: true,
      );
      final asset = ReleaseAsset(
        name: 'mithka-linux-x64.AppImage',
        url: 'http://127.0.0.1:${server.port}/package',
        size: bytes.length,
        sha256: sha256.convert(bytes).toString(),
      );
      final stages = <DesktopUpdateStage>[];
      final update = await DesktopUpdater.prepare(
        asset,
        version: '9.0.0',
        installLayout: layout,
        onProgress: (progress) => stages.add(progress.stage),
      );
      expect(original.readAsStringSync(), 'old');
      expect(
        stages,
        containsAll([
          DesktopUpdateStage.downloading,
          DesktopUpdateStage.verifying,
          DesktopUpdateStage.staging,
        ]),
      );
      expect(stages, isNot(contains(DesktopUpdateStage.extracting)));
      final work = root.listSync().whereType<Directory>().single;
      final package = File('${work.path}/package.AppImage');
      expect(package.readAsBytesSync(), bytes);
      expect(package.statSync().mode & 0x49, 0x49);
      await update.discard();
      expect(root.listSync().whereType<Directory>(), isEmpty);
      for (final badAsset in [
        ReleaseAsset(
          name: asset.name,
          url: asset.url,
          size: asset.size,
          sha256: '0' * 64,
        ),
        ReleaseAsset(
          name: asset.name,
          url: asset.url,
          size: asset.size + 1,
          sha256: asset.sha256,
        ),
        ReleaseAsset(
          name: asset.name,
          url: asset.url,
          size: asset.size,
          sha256: null,
        ),
      ]) {
        await expectLater(
          DesktopUpdater.prepare(
            badAsset,
            version: '9.0.0',
            installLayout: layout,
          ),
          throwsA(isA<DesktopUpdateException>()),
        );
        expect(original.readAsStringSync(), 'old');
        expect(root.listSync().whereType<Directory>(), isEmpty);
      }
    },
    skip: !Platform.isLinux,
  );
}
