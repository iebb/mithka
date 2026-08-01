import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/document_file_icon.dart';

void main() {
  test('uses the explicit Telegram document color buckets', () {
    const expected = <DocumentFilePalette, List<String>>{
      DocumentFilePalette.blue: ['doc', 'docx', 'txt', 'psd'],
      DocumentFilePalette.green: ['xls', 'xlsx', 'csv'],
      DocumentFilePalette.red: ['pdf', 'ppt', 'pptx', 'key'],
      DocumentFilePalette.yellow: ['zip', 'rar', 'ai', 'mp3', 'mov', 'avi'],
    };

    for (final entry in expected.entries) {
      for (final extension in entry.value) {
        expect(
          documentFileVisualFor(
            fileName: 'example.$extension',
            extension: extension,
          ).palette,
          entry.key,
          reason: extension,
        );
      }
    }
  });

  test('deterministically colors archives, installers, and unknown types', () {
    const expected = <String, DocumentFilePalette>{
      'apk': DocumentFilePalette.green,
      'apks': DocumentFilePalette.green,
      'aab': DocumentFilePalette.green,
      'ipa': DocumentFilePalette.green,
      'xapk': DocumentFilePalette.blue,
      '7z': DocumentFilePalette.yellow,
      'gzip': DocumentFilePalette.yellow,
      'tar': DocumentFilePalette.blue,
      'tgz': DocumentFilePalette.blue,
      'rpm': DocumentFilePalette.red,
      'dylib': DocumentFilePalette.blue,
    };

    for (final entry in expected.entries) {
      expect(
        documentFileVisualFor(
          fileName: 'example.${entry.key}',
          extension: entry.key,
        ).palette,
        entry.value,
        reason: entry.key,
      );
    }
  });

  test(
    'normalizes the extension and falls back to the final filename suffix',
    () {
      final fromArgument = documentFileVisualFor(
        fileName: 'archive.zip.txt',
        extension: '.PDF',
      );
      expect(fromArgument.palette, DocumentFilePalette.red);
      expect(fromArgument.label, 'pdf');

      final fromName = documentFileVisualFor(
        fileName: 'archive.zip.txt',
        extension: '',
      );
      expect(fromName.palette, DocumentFilePalette.blue);
      expect(fromName.label, 'txt');
    },
  );

  testWidgets('renders a colored folded file with a lowercase extension', (
    tester,
  ) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: DocumentFileIcon(fileName: 'release.APK', extension: 'APK'),
      ),
    );

    final icon = tester.widget<AppIcon>(find.byType(AppIcon));
    expect(icon.icon.data, HeroAppIcons.solidFile.data);
    expect(icon.color, DocumentFilePalette.green.color);
    expect(find.text('apk'), findsOneWidget);
  });
}
