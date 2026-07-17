import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/audio_search_view.dart';
import 'package:mithka/chat/outgoing_attachment.dart';
import 'package:mithka/chat/rich_text_composer_view.dart';
import 'package:mithka/l10n/app_localizations.dart';

void main() {
  testWidgets('rich composer renders ordered file and music attachments', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: RichTextComposerView(
          initialText: 'Album caption',
          initialAttachments: [
            OutgoingAttachment(
              path: '/tmp/document.pdf',
              kind: OutgoingAttachmentKind.document,
            ),
            OutgoingAttachment(
              path: '/tmp/song.flac',
              kind: OutgoingAttachmentKind.audio,
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('2/50'), findsOneWidget);
    expect(find.text('document.pdf'), findsOneWidget);
    expect(find.text('song.flac'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('audio action opens Telegram audio search in selection mode', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('en'),
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: RichTextComposerView(initialText: ''),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('Audio'));
    await tester.pumpAndSettle();

    expect(find.byType(AudioSearchView), findsOneWidget);
    expect(
      tester.widget<AudioSearchView>(find.byType(AudioSearchView)).selectOnly,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
