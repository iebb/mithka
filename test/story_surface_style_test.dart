import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new story surfaces use owned controls and icon wrappers', () {
    const paths = [
      'lib/moments/story_authoring_view.dart',
      'lib/moments/story_camera_view.dart',
      'lib/moments/story_management_view.dart',
      'lib/moments/story_area_editor_view.dart',
      'lib/moments/story_ui_components.dart',
    ];
    final forbiddenControls = RegExp(
      r'\b(AlertDialog|SimpleDialog|TextButton|DropdownButton|DropdownMenuItem|ListTile|SwitchListTile|FilledButton|ElevatedButton|OutlinedButton|IconButton|FloatingActionButton|ActionChip|ChoiceChip|FilterChip|InputChip|Checkbox|Radio|CircularProgressIndicator|LinearProgressIndicator|RefreshIndicator|PopupMenuButton|MenuAnchor|SegmentedButton|Slider|RangeSlider|InkWell|RawMaterialButton)\b',
    );

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(
        forbiddenControls.hasMatch(source),
        isFalse,
        reason: '$path must use owned story and project controls',
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
