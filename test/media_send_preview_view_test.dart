import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/chat/media_send_preview_view.dart';
import 'package:mithka/chat/outgoing_attachment.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';

void main() {
  testWidgets('send as file is chosen in preview and disables media editing', (
    tester,
  ) async {
    MediaSendPreviewResult? result;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: Scaffold(
          body: Builder(
            builder: (context) => GestureDetector(
              key: const ValueKey('openMediaPreview'),
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                result = await Navigator.of(context).push(
                  MaterialPageRoute<MediaSendPreviewResult>(
                    builder: (_) => const MediaSendPreviewView(
                      attachments: [
                        OutgoingAttachment(
                          path: '/tmp/prepared.jpg',
                          originalPath: '/tmp/IMG_1234.HEIC',
                          fileName: 'IMG_1234.HEIC',
                          kind: OutgoingAttachmentKind.photo,
                        ),
                      ],
                    ),
                  ),
                );
              },
              child: const SizedBox(width: 80, height: 44),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('openMediaPreview')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mediaPreviewSendAsFile')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('mediaPreviewEdit')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('mediaPreviewSendAsFile')));
    await tester.pump();

    expect(find.byKey(const ValueKey('mediaPreviewEdit')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('mediaPreviewSend')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.attachments.single.kind, OutgoingAttachmentKind.document);
    expect(
      attachmentInputFile(result!.attachments.single)['path'],
      '/tmp/IMG_1234.HEIC',
    );
  });

  testWidgets('file mode hides video presentation editing', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(extensions: [AppColors.light]),
        home: const MediaSendPreviewView(
          attachments: [
            OutgoingAttachment(
              path: '/tmp/prepared.mp4',
              originalPath: '/tmp/IMG_5678.MOV',
              kind: OutgoingAttachmentKind.video,
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('mediaPreviewVideoMetadata')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey('mediaPreviewSendAsFile')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('mediaPreviewVideoMetadata')),
      findsNothing,
    );
  });
}
