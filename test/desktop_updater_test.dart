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

    test('an unwritable parent would strand the swap halfway', () {
      expect(
        inspect(parentWritable: false),
        DesktopUpdateBlock.readOnlyInstall,
      );
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

    test('quotes paths so a space cannot split an argument', () {
      final text = script(installDirectory: '/home/u/My Apps/Mithka');
      expect(text, contains(r"install_dir='/home/u/My Apps/Mithka'"));
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

    test('restores the backup on the failure path', () {
      final text = script();
      final failed = text.substring(text.indexOf(':failed'));
      expect(failed, contains('move "%BACKUP_DIR%" "%INSTALL_DIR%"'));
      expect(failed, contains('start "" /D "%INSTALL_DIR%"'));
    });
  });
}
