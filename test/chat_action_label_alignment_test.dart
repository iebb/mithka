import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/contacts/add_people_view.dart';
import 'package:mithka/l10n/app_localizations.dart';

void main() {
  testWidgets('create action labels use centered line alignment', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(home: AddPeopleView()));

    for (final key in [
      AppStringKeys.chatListCreateGroup,
      AppStringKeys.chatListCreateChannel,
    ]) {
      final label = tester.widget<Text>(find.text(AppStrings.t(key)));
      expect(label.textAlign, TextAlign.center);
    }
  });

  testWidgets('chat swipe action labels stay centered when they wrap', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          height: 64,
          child: ChatSwipeRow(
            rowId: 1,
            openRowId: 1,
            onOpenChanged: (_) {},
            onTap: () {},
            actions: [
              SwipeActionItem(
                title: AppStringKeys.chatListMarkUnread,
                color: Colors.orange,
                onTap: () {},
              ),
              SwipeActionItem(
                title: AppStringKeys.chatInfoLeaveGroup,
                color: Colors.red,
                onTap: () {},
              ),
            ],
            child: const ColoredBox(color: Colors.white),
          ),
        ),
      ),
    );

    for (final key in [
      AppStringKeys.chatListMarkUnread,
      AppStringKeys.chatInfoLeaveGroup,
    ]) {
      final label = tester.widget<Text>(find.text(AppStrings.t(key)));
      expect(label.textAlign, TextAlign.center);
    }
  });
}
