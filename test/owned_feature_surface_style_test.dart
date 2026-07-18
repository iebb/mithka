import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new profile and messaging surfaces use project-owned controls', () {
    const paths = [
      'lib/profile/profile_contact_management_view.dart',
      'lib/profile/profile_photo_management_view.dart',
      'lib/chat/saved_messages_view.dart',
      'lib/chat/scheduled_messages_view.dart',
      'lib/chat/contact_share_picker_view.dart',
      'lib/chat/channel_direct_messages_view.dart',
      'lib/call/calls_view.dart',
      'lib/chat/message_info_view.dart',
      'lib/chat/poll_results_view.dart',
      'lib/chat/message_special_content.dart',
      'lib/chat/message_send_options.dart',
      'lib/chat/chat_administrator_edit_view.dart',
      'lib/chat/checklist_composer_view.dart',
      'lib/chat/media_send_preview_view.dart',
      'lib/chat/poll_composer_view.dart',
      'lib/settings/account_security_views.dart',
      'lib/chats/public_discovery_view.dart',
      'lib/settings/chat_folder_management_view.dart',
      'lib/settings/business_tools_views.dart',
      'lib/components/app_dialog.dart',
      'lib/chat/full_image_viewer.dart',
    ];
    final forbiddenControls = RegExp(
      r'\b(AlertDialog|SimpleDialog|TextButton|DropdownButton|DropdownMenuItem|ListTile|SwitchListTile|Switch|FilledButton|ElevatedButton|OutlinedButton|IconButton|FloatingActionButton|ActionChip|ChoiceChip|FilterChip|InputChip|Chip|Checkbox|Radio|CircularProgressIndicator|LinearProgressIndicator|RefreshIndicator|PopupMenuButton|MenuAnchor|SegmentedButton|Slider|RangeSlider|InkWell|RawMaterialButton)\b',
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
        reason: '$path must use AppIcon data',
      );
      expect(source.contains('CupertinoIcons'), isFalse, reason: path);
      expect(source.contains(' child: Icon('), isFalse, reason: path);
    }
  });
}
