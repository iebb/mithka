import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('data, storage and download surfaces use owned controls', () {
    const paths = [
      'lib/settings/auto_download_settings_view.dart',
      'lib/settings/storage_usage_view.dart',
      'lib/settings/network_usage_view.dart',
      'lib/settings/downloads_view.dart',
    ];
    final forbiddenControls = RegExp(
      r'\b(AlertDialog|SimpleDialog|TextButton|DropdownButton|DropdownMenuItem|ListTile|SwitchListTile|FilledButton|ElevatedButton|OutlinedButton|IconButton|FloatingActionButton|ActionChip|ChoiceChip|FilterChip|InputChip|Checkbox|Radio|CircularProgressIndicator|LinearProgressIndicator|RefreshIndicator|PopupMenuButton|MenuAnchor|SegmentedButton|Slider|RangeSlider|InkWell|RawMaterialButton)\b',
    );

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        forbiddenControls.hasMatch(source),
        isFalse,
        reason: '$path must use project-owned controls',
      );
      expect(
        source.replaceAll('HeroAppIcons.', '').contains('Icons.'),
        isFalse,
        reason: path,
      );
      expect(source.contains('CupertinoIcons'), isFalse, reason: path);
      expect(source.contains(' child: Icon('), isFalse, reason: path);
    }
  });
}
