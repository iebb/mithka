import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/components/chat_folder_icons.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  testWidgets('side rail floats folder badges on the icon top-right corner', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: const Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 58,
              height: 400,
              child: ChatFolderRail(
                showUnreadBadges: true,
                selectedFolderId: 1,
                filters: [
                  ChatFilterOption(title: 'All'),
                  ChatFilterOption(
                    title: 'Business',
                    folderId: 1,
                    unreadChatCount: 2,
                    hasUnmutedUnread: true,
                  ),
                  ChatFilterOption(
                    title: 'Unread',
                    folderId: 2,
                    unreadChatCount: 250,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(FolderUnreadBadge), findsNWidgets(2));
    for (final id in [1, 2]) {
      final row = find.byKey(ValueKey('side-folder-$id'));
      final icon = tester.getRect(
        find.descendant(of: row, matching: find.byType(ChatFolderIcon)),
      );
      final badge = tester.getRect(
        find.descendant(of: row, matching: find.byType(FolderUnreadBadge)),
      );
      final label = tester.getRect(
        find.descendant(of: row, matching: find.byType(Text)).last,
      );
      // Overlaps the glyph's top-right corner and sits above the label.
      expect(badge.top, lessThan(icon.top));
      expect(badge.bottom, greaterThan(icon.top));
      expect(badge.left, lessThan(icon.right));
      expect(badge.right, greaterThan(icon.right));
      expect(badge.bottom, lessThan(label.top));
      // Stays inside the rail so a wide "99+" is never clipped.
      expect(badge.right, lessThanOrEqualTo(58));
    }
    expect(tester.takeException(), isNull);
  });
}
