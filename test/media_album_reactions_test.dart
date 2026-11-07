import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/image_media_album_bubble.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

ChatMessage _photo(int id) => ChatMessage(
  id: id,
  isOutgoing: false,
  senderId: 7,
  text: '',
  date: id,
  contentType: 'messagePhoto',
  mediaAlbumId: 91,
  image: TdFileRef(id: id),
  imageWidth: 320,
  imageHeight: 240,
);

Future<void> _pump(WidgetTester tester, Widget child) async {
  SharedPreferences.setMockInitialValues({});
  final theme = ThemeController(await SharedPreferences.getInstance());
  addTearDown(theme.dispose);
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: theme,
      child: MaterialApp(
        theme: ThemeData(extensions: [AppColors.light]),
        locale: const Locale('en'),
        localizationsDelegates: const [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: child),
      ),
    ),
  );
}

void main() {
  testWidgets('a photo album shows and toggles its owner reactions', (
    tester,
  ) async {
    const reaction = MessageReaction(emoji: '👍', count: 1, chosen: true);
    final first = _photo(1);
    final second = _photo(2)..reactions = const [reaction];
    final toggled = <(int, MessageReaction)>[];

    await _pump(
      tester,
      ImageMediaAlbumBubble(
        messages: [first, second],
        peerTitle: 'Chat',
        isGroup: false,
        meId: 42,
        imageBuilder: (_, message, _, _) =>
            const ColoredBox(color: Colors.blue),
        onToggleReaction: (message, r) => toggled.add((message.id, r)),
      ),
    );

    expect(selectMediaAlbumInteractionOwner([first, second]).id, 2);
    final chip = find.byKey(const ValueKey('reactionChip-2-emoji:👍'));
    expect(chip, findsOneWidget);

    await tester.tap(chip);
    expect(toggled, [(2, reaction)]);
  });

  testWidgets('a photo album without reactions shows no chips', (tester) async {
    await _pump(
      tester,
      ImageMediaAlbumBubble(
        messages: [_photo(1), _photo(2)],
        peerTitle: 'Chat',
        isGroup: false,
        meId: 42,
        imageBuilder: (_, message, _, _) =>
            const ColoredBox(color: Colors.blue),
      ),
    );

    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget.key is ValueKey<String> &&
            (widget.key! as ValueKey<String>).value.startsWith('reactionChip-'),
      ),
      findsNothing,
    );
  });
}
