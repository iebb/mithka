import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Telegram AI and video-message recorder use owned controls', () {
    const paths = [
      'lib/chat/unread_chat_summary_view.dart',
      'lib/chat/telegram_ai_editor_view.dart',
      'lib/chat/video_note_recorder_view.dart',
      'lib/chat/video_note_preview_view.dart',
      'lib/chat/voice_note_preview_view.dart',
      'lib/settings/ai_settings_view.dart',
    ];
    final forbiddenControls = RegExp(
      r'\b(AlertDialog|SimpleDialog|TextButton|DropdownButton|DropdownMenuItem|ListTile|SwitchListTile|FilledButton|ElevatedButton|OutlinedButton|IconButton|FloatingActionButton|ActionChip|ChoiceChip|FilterChip|InputChip|Checkbox|Radio|CircularProgressIndicator|LinearProgressIndicator|RefreshIndicator|PopupMenuButton|MenuAnchor|SegmentedButton|Slider|RangeSlider|InkWell|RawMaterialButton)\b',
    );
    for (final path in paths) {
      final source = File(path).readAsStringSync();
      expect(forbiddenControls.hasMatch(source), isFalse, reason: path);
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
