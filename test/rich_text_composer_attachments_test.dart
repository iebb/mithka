import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/audio_search_view.dart';
import 'package:mithka/chat/outgoing_attachment.dart';
import 'package:mithka/chat/rich_text_composer_view.dart';
import 'package:mithka/l10n/app_localizations.dart';

void main() {
  testWidgets('heading selector submits the selected heading level', (
    tester,
  ) async {
    RichTextComposerResult? submitted;
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              submitted = await Navigator.of(context).push(
                MaterialPageRoute<RichTextComposerResult>(
                  builder: (_) => const RichTextComposerView(initialText: ''),
                ),
              );
            },
            child: const Text('Open composer'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open composer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('H'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('rich-heading-level-selector')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('rich-heading-level-3')));
    await tester.enterText(find.byType(TextField).last, 'Chapter title');
    await tester.tap(find.text('Post'));
    await tester.pumpAndSettle();

    final segment = submitted!.segments.single;
    expect(segment.html, '<h3>Chapter title</h3>');
    expect(segment.blocks.single['@type'], 'inputPageBlockSectionHeading');
    expect(segment.blocks.single['size'], 3);
  });

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
