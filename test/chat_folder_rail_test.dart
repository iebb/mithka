import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/chat_list_view.dart';
import 'package:mithka/chats/chat_list_view_model.dart';
import 'package:mithka/components/app_icons.dart';
import 'package:mithka/components/chat_folder_icons.dart';

void main() {
  testWidgets(
    'narrow rail wraps long folder names onto a second line with a tooltip fallback',
    (tester) async {
      const title = 'Very Long Folder Name';
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: 58,
              height: 300,
              child: ChatFolderRail(
                filters: const [
                  ChatFilterOption(title: 'All'),
                  ChatFilterOption(title: title, folderId: 9),
                ],
                selectedFolderId: 9,
                onSelect: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final label = tester.widget<Text>(find.text(title));
      expect(label.maxLines, 2);
      // The label must wrap onto a second painted line instead of collapsing
      // into a single ellipsized line.
      final paragraph = tester.renderObject<RenderParagraph>(find.text(title));
      final boxes = paragraph.getBoxesForSelection(
        const TextSelection(baseOffset: 0, extentOffset: title.length),
      );
      final paintedLines = boxes.map((box) => box.top).toSet().length;
      expect(paintedLines, 2, reason: 'full name wraps instead of ellipsizing');
      // Anything still too long for two lines stays reachable via hover.
      expect(find.byType(Tooltip), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.iOS,
  ]) {
    testWidgets(
      'folder hover label timing and dismissal on $platform',
      (tester) async {
        const title = 'Very Long Folder Name';
        const hintKey = ValueKey('side-folder-name-tooltip-9');
        var selections = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 58,
                height: 300,
                child: ChatFolderRail(
                  filters: const [ChatFilterOption(title: title, folderId: 9)],
                  selectedFolderId: null,
                  onSelect: (_) => selections++,
                ),
              ),
            ),
          ),
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: const Offset(700, 500));
        final target = find.byKey(const ValueKey('side-folder-9'));
        await mouse.moveTo(tester.getCenter(target));
        await tester.pump(const Duration(milliseconds: 449));
        expect(find.byKey(hintKey), findsNothing);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        expect(find.byKey(hintKey), findsOneWidget);
        expect(
          find.descendant(of: find.byKey(hintKey), matching: find.text(title)),
          findsOneWidget,
        );
        expect(find.byType(Tooltip), findsNothing);
        await mouse.down(tester.getCenter(target));
        await mouse.up();
        await tester.pump();
        expect(selections, 1);
        expect(find.byKey(hintKey), findsNothing);
        await mouse.moveTo(const Offset(700, 500));
        await mouse.moveTo(tester.getCenter(target));
        await tester.pump(const Duration(milliseconds: 200));
        await mouse.moveTo(const Offset(700, 500));
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(hintKey), findsNothing);
        await mouse.moveTo(tester.getCenter(target));
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        expect(find.byKey(hintKey), findsNothing);
        expect(tester.takeException(), isNull);
        await mouse.removePointer();
      },
      variant: TargetPlatformVariant.only(platform),
    );
  }

  testWidgets('folder hover label fits a scaled RTL rail near window edges', (
    tester,
  ) async {
    const title = '文件与视频资料归档非常长的文件夹名称';
    const hintKey = ValueKey('side-folder-name-tooltip-9');
    await tester.pumpWidget(
      const MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Align(
              alignment: Alignment.bottomRight,
              child: SizedBox(
                width: 58,
                height: 82,
                child: ChatFolderRail(
                  filters: [
                    ChatFilterOption(
                      title: title,
                      folderId: 9,
                      unreadChatCount: 150,
                    ),
                  ],
                  selectedFolderId: null,
                  showUnreadBadges: true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    await mouse.moveTo(tester.getCenter(find.byType(ChatFolderIcon)));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(find.byKey(hintKey), findsOneWidget);
    final rect = tester.getRect(find.byKey(hintKey));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.top, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(800));
    expect(rect.bottom, lessThanOrEqualTo(600));
    expect(find.text('99+'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('folder hover label is dismissed on rename and disposal', (
    tester,
  ) async {
    const hintKey = ValueKey('side-folder-name-tooltip-9');
    var title = 'Original Folder Name';
    late StateSetter update;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 58,
            height: 300,
            child: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return ChatFolderRail(
                  filters: [ChatFilterOption(title: title, folderId: 9)],
                  selectedFolderId: null,
                );
              },
            ),
          ),
        ),
      ),
    );
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(700, 500));
    final target = find.byKey(const ValueKey('side-folder-9'));
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(find.byKey(hintKey), findsOneWidget);
    update(() => title = 'Renamed Folder Name');
    await tester.pump();
    expect(find.byKey(hintKey), findsNothing);
    await mouse.moveTo(const Offset(700, 500));
    await mouse.moveTo(tester.getCenter(target));
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(
      find.descendant(of: find.byKey(hintKey), matching: find.text(title)),
      findsOneWidget,
    );
    await tester.pumpWidget(const SizedBox.shrink());
    expect(find.byKey(hintKey), findsNothing);
    await tester.pump(const Duration(seconds: 1));
    expect(tester.takeException(), isNull);
    await mouse.removePointer();
  });

  testWidgets('right click opens the menu only on custom folders', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    int? menuFolder;
    var selections = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 72,
            height: 300,
            child: ChatFolderRail(
              filters: const [
                ChatFilterOption(title: 'All'),
                ChatFilterOption(title: 'Work', folderId: 7),
              ],
              selectedFolderId: null,
              onSelect: (_) => selections++,
              onMenu: (folder) => menuFolder = folder.folderId,
            ),
          ),
        ),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey('side-folder-all')),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    expect(menuFolder, isNull);
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.addPointer(location: const Offset(700, 500));
    final target = tester.getCenter(
      find.byKey(const ValueKey('side-folder-7')),
    );
    await mouse.moveTo(target);
    await tester.pump(const Duration(milliseconds: 450));
    await tester.pump();
    expect(
      find.byKey(const ValueKey('side-folder-name-tooltip-7')),
      findsOneWidget,
    );
    await mouse.down(target);
    await mouse.up();
    await tester.pumpAndSettle();
    expect(menuFolder, 7);
    expect(selections, 0);
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  test('folder icons map configured names and safely fall back', () {
    expect(chatFolderIcon('Work'), HeroAppIcons.briefcase);
    expect(chatFolderIcon('Private'), HeroAppIcons.circleUser);
    expect(chatFolderIcon('Game'), HeroAppIcons.puzzle);
    expect(chatFolderIcon('Unread'), HeroAppIcons.message);
    expect(chatFolderIcon('All'), HeroAppIcons.inbox);
    expect(chatFolderIcon('Custom'), HeroAppIcons.folder);
    expect(chatFolderIcon('future-icon'), HeroAppIcons.folder);
  });

  testWidgets(
    'folder rail scrolls and changes selection without moving lower navigation',
    (tester) async {
      int? selected;
      late StateSetter update;
      const navigationKey = ValueKey('fixed-navigation');
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: Overlay(
            initialEntries: [
              OverlayEntry(
                builder: (context) => MediaQuery(
                  data: const MediaQueryData(),
                  child: DefaultTextStyle(
                    style: const TextStyle(fontSize: 11),
                    child: Center(
                      child: SizedBox(
                        width: 72,
                        height: 300,
                        child: StatefulBuilder(
                          builder: (context, setState) {
                            update = setState;
                            return Column(
                              children: [
                                Expanded(
                                  child: ChatFolderRail(
                                    filters: [
                                      const ChatFilterOption(title: 'All'),
                                      for (var i = 0; i < 12; i++)
                                        ChatFilterOption(
                                          title: 'Folder $i',
                                          folderId: i,
                                          iconName: 'Work',
                                        ),
                                    ],
                                    selectedFolderId: selected,
                                    onSelect: (folder) => update(
                                      () => selected = folder.folderId,
                                    ),
                                  ),
                                ),
                                const SizedBox(key: navigationKey, height: 64),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
      final navigationRect = tester.getRect(find.byKey(navigationKey));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('side-folder-10')),
        120,
        scrollable: find.byType(Scrollable),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('side-folder-10')));
      await tester.pumpAndSettle();
      expect(selected, 10);
      final folderIcon = tester.widget<AppIcon>(
        find.descendant(
          of: find.byKey(const ValueKey('side-folder-10')),
          matching: find.byType(AppIcon),
        ),
      );
      expect(folderIcon.icon, HeroAppIcons.briefcase);
      expect(tester.getRect(find.byKey(navigationKey)), navigationRect);
      expect(tester.takeException(), isNull);
    },
  );
}
