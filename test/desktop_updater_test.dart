import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/update/desktop_updater.dart';

void main() {
  group('install eligibility', () {
    DesktopUpdateBlock? inspect({
      bool platformSupported = true,
      Map<String, String> environment = const {},
      String executablePath = '/home/u/Apps/Mithka/mithka',
      bool parentWritable = true,
    }) => DesktopUpdater.describeInstallBlock(
      platformSupported: platformSupported,
      environment: environment,
      executablePath: executablePath,
      parentWritable: parentWritable,
    );

    test('a writable portable install can update itself', () {
      expect(inspect(), isNull);
    });

    test('a Windows install under the user profile can update itself', () {
      expect(
        inspect(executablePath: r'C:\Users\u\Apps\Mithka\mithka.exe'),
        isNull,
      );
    });

    test('macOS and every unpublished architecture are out of scope', () {
      expect(
        inspect(platformSupported: false),
        DesktopUpdateBlock.unsupportedPlatform,
      );
    });

    for (final key in ['APPIMAGE', 'FLATPAK_ID', 'SNAP']) {
      test('$key means the runtime owns its own payload', () {
        expect(
          inspect(environment: {key: '/somewhere/mithka'}),
          DesktopUpdateBlock.managedInstall,
        );
      });
    }

    test('an empty managed variable is not a managed install', () {
      expect(inspect(environment: const {'SNAP': ''}), isNull);
    });

    for (final prefix in ['/usr', '/opt', '/snap', '/app', '/nix/store']) {
      test('$prefix belongs to the system, not to the user', () {
        expect(
          inspect(executablePath: '$prefix/mithka/mithka'),
          DesktopUpdateBlock.managedInstall,
        );
      });
    }

    test('a path merely containing /usr/ is still updatable', () {
      expect(inspect(executablePath: '/home/usr/Mithka/mithka'), isNull);
    });

    test('an unwritable parent would strand the swap halfway', () {
      expect(
        inspect(parentWritable: false),
        DesktopUpdateBlock.readOnlyInstall,
      );
    });

    test('a managed install is reported ahead of its writability', () {
      // Both are true for a distro package; naming the package manager is the
      // answer the user can act on.
      expect(
        inspect(executablePath: '/usr/bin/mithka', parentWritable: false),
        DesktopUpdateBlock.managedInstall,
      );
    });
  });

  group('unpacked package guard', () {
    Directory unpacked(void Function(Directory root) build) {
      final directory = Directory.systemTemp.createTempSync('mithka-pkg-');
      build(directory);
      return directory;
    }

    test('accepts an archive holding one Mithka build', () {
      final directory = unpacked((root) {
        Directory('${root.path}/Mithka').createSync();
        File(
          '${root.path}/Mithka/${DesktopUpdater.launcherFileName}',
        ).writeAsStringSync('');
      });
      expect(DesktopUpdater.packageRoot(directory).path, endsWith('Mithka'));
      directory.deleteSync(recursive: true);
    });

    test('rejects a directory with no Mithka executable', () {
      final directory = unpacked((root) {
        Directory('${root.path}/Mithka').createSync();
        File('${root.path}/Mithka/readme.txt').writeAsStringSync('');
      });
      expect(
        () => DesktopUpdater.packageRoot(directory),
        throwsA(isA<DesktopUpdateException>()),
        reason: 'an archive without a launcher would brick the install',
      );
      directory.deleteSync(recursive: true);
    });

    test('rejects an archive that unpacked more than one directory', () {
      final directory = unpacked((root) {
        Directory('${root.path}/Mithka').createSync();
        Directory('${root.path}/Other').createSync();
      });
      expect(
        () => DesktopUpdater.packageRoot(directory),
        throwsA(isA<DesktopUpdateException>()),
      );
      directory.deleteSync(recursive: true);
    });

    test('rejects an empty archive', () {
      final directory = unpacked((_) {});
      expect(
        () => DesktopUpdater.packageRoot(directory),
        throwsA(isA<DesktopUpdateException>()),
      );
      directory.deleteSync(recursive: true);
    });
  });

  group('POSIX swap helper', () {
    String script({
      String installDirectory = '/home/u/Apps/Mithka',
      String stagedDirectory = '/home/u/Apps/.mithka-update-7/unpacked/Mithka',
    }) => buildPosixUpdateScript(
      processId: 4242,
      installDirectory: installDirectory,
      stagedDirectory: stagedDirectory,
      backupDirectory: '/home/u/Apps/.mithka-backup-7',
      workDirectory: '/home/u/Apps/.mithka-update-7',
      launcherName: 'mithka',
    );

    test('is valid shell', () async {
      final file = File(
        '${Directory.systemTemp.createTempSync('mithka-script-').path}/a.sh',
      );
      file.writeAsStringSync(script());
      final result = await Process.run('sh', ['-n', file.path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });

    test('quotes paths so a space cannot split an argument', () {
      final text = script(installDirectory: '/home/u/My Apps/Mithka');
      expect(text, contains(r"install_dir='/home/u/My Apps/Mithka'"));
    });

    test('escapes a quote in a path rather than ending the literal', () async {
      final text = script(installDirectory: "/home/u/it's/Mithka");
      expect(text, contains(r"install_dir='/home/u/it'\''s/Mithka'"));
      final file = File(
        '${Directory.systemTemp.createTempSync('mithka-script-').path}/b.sh',
      );
      file.writeAsStringSync(text);
      final result = await Process.run('sh', ['-n', file.path]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
    });

    test('waits for the process, swaps, and relaunches', () async {
      final root = Directory.systemTemp.createTempSync('mithka-swap-');
      final install = Directory('${root.path}/Mithka')..createSync();
      final staged = Directory('${root.path}/work/unpacked/Mithka')
        ..createSync(recursive: true);
      File('${install.path}/marker').writeAsStringSync('old');
      File('${staged.path}/marker').writeAsStringSync('new');
      // A launcher that records that the new build was started.
      File('${staged.path}/mithka').writeAsStringSync(
        '#!/bin/sh\necho started > "\$(dirname "\$0")/ran"\n',
      );
      await Process.run('chmod', ['0755', '${staged.path}/mithka']);

      final file = File('${root.path}/apply.sh');
      file.writeAsStringSync(
        buildPosixUpdateScript(
          // A PID that is already gone, so the wait falls straight through.
          processId: 2147483646,
          installDirectory: install.path,
          stagedDirectory: staged.path,
          backupDirectory: '${root.path}/.mithka-backup-1',
          workDirectory: '${root.path}/work',
          launcherName: 'mithka',
        ),
      );
      final result = await Process.run('sh', [file.path]);

      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(File('${install.path}/marker').readAsStringSync(), 'new');
      expect(Directory('${root.path}/work').existsSync(), isFalse);
      expect(Directory('${root.path}/.mithka-backup-1').existsSync(), isFalse);
      final relaunched = File('${install.path}/ran');
      for (
        var attempt = 0;
        attempt < 100 && !relaunched.existsSync();
        attempt++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(relaunched.existsSync(), isTrue);
      root.deleteSync(recursive: true);
    });

    test('restores the old install when the staged build is gone', () async {
      final root = Directory.systemTemp.createTempSync('mithka-swap-');
      final install = Directory('${root.path}/Mithka')..createSync();
      File('${install.path}/marker').writeAsStringSync('old');

      final file = File('${root.path}/apply.sh');
      file.writeAsStringSync(
        buildPosixUpdateScript(
          processId: 2147483646,
          installDirectory: install.path,
          stagedDirectory: '${root.path}/work/unpacked/Mithka',
          backupDirectory: '${root.path}/.mithka-backup-1',
          workDirectory: '${root.path}/work',
          launcherName: 'mithka',
        ),
      );
      final result = await Process.run('sh', [file.path]);

      expect(result.exitCode, 1);
      expect(
        File('${install.path}/marker').readAsStringSync(),
        'old',
        reason: 'a failed swap must leave the working build in place',
      );
      root.deleteSync(recursive: true);
    });
  });

  group('Windows swap helper', () {
    String script({String installDirectory = r'C:\Users\u\Apps\Mithka'}) =>
        buildWindowsUpdateScript(
          processId: 4242,
          installDirectory: installDirectory,
          stagedDirectory: r'C:\Users\u\Apps\.mithka-update-7\unpacked\Mithka',
          backupDirectory: r'C:\Users\u\Apps\.mithka-backup-7',
          workDirectory: r'C:\Users\u\Apps\.mithka-update-7',
          launcherName: 'mithka.exe',
        );

    test('uses CRLF, which batch requires for its labels', () {
      expect(script(), contains('\r\n'));
      expect(script().split('\r\n'), contains(':swap'));
    });

    test('assigns paths inside quotes so a space stays part of the value', () {
      expect(
        script(installDirectory: r'C:\Users\u\My Apps\Mithka'),
        contains(r'set "INSTALL_DIR=C:\Users\u\My Apps\Mithka"'),
      );
    });

    test('doubles a percent so batch does not expand it', () {
      expect(
        script(installDirectory: r'C:\100%Mithka'),
        contains(r'set "INSTALL_DIR=C:\100%%Mithka"'),
      );
    });

    test('every jump target it uses is defined', () {
      final lines = script().split('\r\n');
      final labels = lines
          .where((line) => line.startsWith(':'))
          .map((line) => line.substring(1))
          .toSet();
      final targets = lines
          .where((line) => line.contains('goto '))
          .map((line) => line.split('goto ').last.trim())
          .toSet();
      expect(targets, isNotEmpty);
      expect(labels, containsAll(targets));
    });

    test('restores the backup on the failure path', () {
      final text = script();
      final failed = text.substring(text.indexOf(':failed'));
      expect(failed, contains('move "%BACKUP_DIR%" "%INSTALL_DIR%"'));
      expect(failed, contains('start "" /D "%INSTALL_DIR%"'));
    });
  });
}
