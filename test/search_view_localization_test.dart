import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chats/search_view.dart';
import 'package:mithka/l10n/app_localizations.dart';

void main() {
  testWidgets('search categories use concise localized plural labels', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [AppLocalizations.delegate],
        supportedLocales: AppLocalizations.supportedLocales,
        home: SearchView(),
      ),
    );
    await tester.pump(const Duration(milliseconds: 300));

    for (final label in const [
      'Chats',
      'Mini Apps',
      'Messages',
      'Media',
      'Links',
      'Files',
      'Music',
      'Voice Messages',
    ]) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('Mini App'), findsNothing);
    expect(find.text('Message'), findsNothing);
    expect(find.text('File'), findsNothing);
  });
}
