import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'Saved Messages defaults to the normal chat view and persists',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final theme = ThemeController(prefs);

      expect(theme.savedMessagesBookmarkView, isFalse);

      theme.savedMessagesBookmarkView = true;
      expect(theme.savedMessagesBookmarkView, isTrue);
      expect(prefs.getBool('savedMessagesBookmarkView'), isTrue);
    },
  );

  test('the former shortcut preference migrates to bookmark view', () async {
    SharedPreferences.setMockInitialValues({'displayOwnChatAsFavorites': true});
    final prefs = await SharedPreferences.getInstance();
    final theme = ThemeController(prefs);

    expect(theme.savedMessagesBookmarkView, isTrue);
    expect(prefs.getBool('savedMessagesBookmarkView'), isTrue);
  });

  test('all Saved Messages entry points use the display preference', () {
    for (final path in [
      'lib/chats/chat_list_view.dart',
      'lib/profile/profile_view.dart',
      'lib/chat/link_handler.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, contains('savedMessagesBookmarkView'), reason: path);
      expect(source, contains('SavedMessagesView()'), reason: path);
      expect(source, contains('ChatView('), reason: path);
    }
  });

  test('Saved Messages entry matches the selected display mode', () {
    final rowSource = File('lib/chats/chat_row_view.dart').readAsStringSync();
    final profileSource = File(
      'lib/profile/profile_view.dart',
    ).readAsStringSync();

    expect(rowSource, contains('theme.savedMessagesBookmarkView'));
    expect(rowSource, contains('HeroAppIcons.thumbtack'));
    expect(rowSource, contains('PhotoAvatar('));
    expect(rowSource, contains('? AppStringKeys.savedMessages.l10n(context)'));
    expect(profileSource, contains('HeroAppIcons.thumbtack'));

    final bookmarkSource = File(
      'lib/chat/saved_messages_view.dart',
    ).readAsStringSync();
    expect(bookmarkSource, contains('mePhoto: _mePhoto'));
    expect(bookmarkSource, contains('peerPhoto: _mePhoto'));
    expect(bookmarkSource, contains('TDParse.smallPhoto'));
  });
}
