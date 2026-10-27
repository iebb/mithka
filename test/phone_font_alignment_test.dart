import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/scaled_app_view.dart';
import 'package:mithka/channels/topic_list_row.dart';
import 'package:mithka/channels/topic_navigation.dart';
import 'package:mithka/chats/chat_folder_tag_controller.dart';
import 'package:mithka/chats/chat_row_metrics.dart';
import 'package:mithka/chats/chat_row_view.dart';
import 'package:mithka/components/photo_avatar.dart';
import 'package:mithka/components/ui_components.dart';
import 'package:mithka/tdlib/td_models.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/content_size.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Crosses 1.0 within the tested font sizes: a scale(1) linear approximation
/// would incorrectly discard its larger-font growth.
class _MixedNonlinearScaler extends TextScaler {
  const _MixedNonlinearScaler();
  @override
  double scale(double fontSize) => fontSize * (.7 + fontSize / 40);
  @override
  double get textScaleFactor => .725;
}

class _GrowingNonlinearScaler extends TextScaler {
  const _GrowingNonlinearScaler();
  @override
  double scale(double fontSize) => fontSize + fontSize * fontSize / 40;
  @override
  double get textScaleFactor => 1.025;
}

RenderParagraph _paragraph(WidgetTester tester, String text) =>
    tester.renderObject<RenderParagraph>(
      find
          .byWidgetPredicate(
            (widget) => widget is RichText && widget.text.toPlainText() == text,
          )
          .first,
    );

double _fontPixels(RenderParagraph paragraph) =>
    paragraph.textScaler.scale(paragraph.text.style!.fontSize!);

void _platformTestWidgets(
  String description,
  TargetPlatform platform,
  WidgetTesterCallback callback,
) {
  testWidgets(description, (tester) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await callback(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  Future<ThemeController> controller() async {
    SharedPreferences.setMockInitialValues({});
    final result = ThemeController(await SharedPreferences.getInstance());
    addTearDown(result.dispose);
    return result;
  }

  Widget harness(
    ThemeController theme,
    Widget child, {
    required double appScale,
    required TextScaler system,
    double interfaceScale = 1,
    double? height,
  }) => ChangeNotifierProvider<ThemeController>.value(
    value: theme,
    child: MaterialApp(
      theme: ThemeData(extensions: [AppColors.light]),
      builder: (context, route) => MediaQuery(
        data: MediaQuery.of(context).copyWith(textScaler: system),
        child: ScaledAppView(
          textScale: appScale,
          interfaceScale: interfaceScale,
          child: route!,
        ),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: DefaultTextStyle(
            style: TextStyle(fontFamily: 'Ahem', fontSize: 15, height: height),
            child: child,
          ),
        ),
      ),
    ),
  );

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final system in <TextScaler>[
      const TextScaler.linear(.823),
      TextScaler.noScaling,
      const TextScaler.linear(2),
      const _MixedNonlinearScaler(),
      const _GrowingNonlinearScaler(),
    ]) {
      _platformTestWidgets(
        '$platform floors each OS font size before content: $system',
        platform,
        (tester) async {
          final theme = await controller();
          late ContentSizeData captured;
          late TextScaler chrome;
          late TextScaler content;
          late TextScaler nested;
          late TextScaler preview;
          late TextScaler customPreview;
          await tester.pumpWidget(
            harness(
              theme,
              Column(
                children: [
                  Builder(
                    builder: (context) {
                      captured = ContentSizeScope.of(context);
                      chrome = MediaQuery.textScalerOf(context);
                      return const Text(
                        'Search',
                        style: TextStyle(fontSize: 15),
                      );
                    },
                  ),
                  ContentSizeScope(
                    child: Column(
                      children: [
                        Builder(
                          builder: (context) {
                            content = MediaQuery.textScalerOf(context);
                            preview = ContentSizeScope.chatListPreviewScalerOf(
                              context,
                            );
                            return const SizedBox();
                          },
                        ),
                        ContentSizeScope(
                          child: Builder(
                            builder: (context) {
                              nested = MediaQuery.textScalerOf(context);
                              return const SizedBox();
                            },
                          ),
                        ),
                        ContentSizeScope(
                          appScale: 1.35,
                          child: Builder(
                            builder: (context) {
                              customPreview =
                                  ContentSizeScope.chatListPreviewScalerOf(
                                    context,
                                  );
                              return const SizedBox();
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              appScale: .9,
              system: system,
            ),
          );
          expect(captured.systemTextScaler, same(chrome));
          expect(captured.appScale, .9);
          for (final font in [10.0, 13.0, 15.0, 17.0, 32.0, 48.0]) {
            double floored(double size) => math.max(size, system.scale(size));
            expect(chrome.scale(font), floored(font));
            expect(content.scale(font), closeTo(floored(font * .9), 1e-9));
            expect(nested.scale(font), closeTo(floored(font * .9), 1e-9));
            expect(preview.scale(font), floored(font));
            expect(
              customPreview.scale(font),
              closeTo(floored(font * 1.35), 1e-9),
            );
          }
          expect(
            _fontPixels(_paragraph(tester, 'Search')),
            math.max(15, system.scale(15)),
          );
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.fuchsia,
  ]) {
    _platformTestWidgets(
      '$platform retains original OS and app scaling',
      platform,
      (tester) async {
        final theme = await controller();
        for (final system in <TextScaler>[
          const TextScaler.linear(.823),
          const _MixedNonlinearScaler(),
          const _GrowingNonlinearScaler(),
        ]) {
          late TextScaler chrome;
          late TextScaler content;
          late TextScaler preview;
          await tester.pumpWidget(
            harness(
              theme,
              Column(
                children: [
                  Builder(
                    builder: (context) {
                      chrome = MediaQuery.textScalerOf(context);
                      return const SizedBox();
                    },
                  ),
                  ContentSizeScope(
                    child: Builder(
                      builder: (context) {
                        content = MediaQuery.textScalerOf(context);
                        preview = ContentSizeScope.chatListPreviewScalerOf(
                          context,
                        );
                        return const SizedBox();
                      },
                    ),
                  ),
                ],
              ),
              appScale: .9,
              system: system,
            ),
          );
          expect(chrome, same(system));
          for (final font in [12.0, 14.0, 17.0, 32.0]) {
            expect(content.scale(font), system.scale(font * .9));
            expect(preview.scale(font), system.scale(font * .9));
          }
        }
      },
    );
  }

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    _platformTestWidgets(
      '$platform preview floor preserves other roles and geometry',
      platform,
      (tester) async {
        final theme = await controller();
        final chat = ChatSummary(
          id: 401,
          title: 'Conversation',
          lastMessage: 'Preview',
          lastSender: 'Sender',
          lastMessageId: 1,
          date: 1,
          unreadCount: 0,
          order: 1,
          isMuted: false,
        );
        for (final os in [.823, 1.0, 2.0]) {
          for (final app in contentSizePresets) {
            late ChatRowMetrics metrics;
            await tester.pumpWidget(
              harness(
                theme,
                SizedBox(
                  width: 390,
                  child: Builder(
                    builder: (context) {
                      metrics = chatRowMetricsFor(context, chat, width: 390);
                      return Column(
                        children: [
                          ChatRowView(chat: chat),
                          const ContentSizeScope(
                            child: Text('Body', style: TextStyle(fontSize: 17)),
                          ),
                          const Text('Search', style: TextStyle(fontSize: 15)),
                        ],
                      );
                    },
                  ),
                ),
                appScale: app,
                system: TextScaler.linear(os),
              ),
            );
            final osScale = math.max(os, 1.0);
            expect(
              _fontPixels(_paragraph(tester, 'Conversation')),
              closeTo(17 * app * osScale, 1e-9),
            );
            expect(
              _fontPixels(_paragraph(tester, 'Sender: Preview')),
              closeTo(13 * math.max(app, 1) * osScale, 1e-9),
            );
            expect(
              _fontPixels(_paragraph(tester, 'Body')),
              closeTo(17 * app * osScale, 1e-9),
            );
            expect(_fontPixels(_paragraph(tester, 'Search')), 15 * osScale);
            final row = find.byType(ChatRowView);
            final time = find.descendant(
              of: row,
              matching: find.byWidgetPredicate(
                (widget) => widget is Text && widget.style?.fontSize == 13,
              ),
            );
            final timeText = tester.widget<Text>(time).data!;
            expect(
              _fontPixels(_paragraph(tester, timeText)),
              closeTo(13 * app * osScale, 1e-9),
            );
            expect(
              tester.widget<PhotoAvatar>(find.byType(PhotoAvatar)).size,
              48 * app,
            );
            expect(tester.getSize(row).height, metrics.extent);
            if (os <= 1) expect(metrics.extent, closeTo(72 * app, 1e-9));
            if (app == .9 && os <= 1) {
              expect(
                _fontPixels(_paragraph(tester, 'Sender: Preview')) * 3,
                39,
              );
              expect(
                _fontPixels(_paragraph(tester, 'Conversation')) * 3,
                closeTo(45.9, 1e-9),
              );
              expect(_fontPixels(_paragraph(tester, 'Search')) * 3, 45);
            }
            expect(tester.takeException(), isNull);
          }
        }
      },
    );
  }

  _platformTestWidgets(
    'preview measurement matches tall rendered text and nonlinear OS',
    TargetPlatform.iOS,
    (tester) async {
      final theme = await controller();
      for (final system in <TextScaler>[
        const TextScaler.linear(.823),
        const _GrowingNonlinearScaler(),
      ]) {
        late ChatRowMetrics metrics;
        await tester.pumpWidget(
          harness(
            theme,
            SizedBox(
              width: 390,
              child: Builder(
                builder: (context) {
                  metrics = ChatRowMetrics.resolve(context, width: 390);
                  return SizedBox(
                    height: metrics.extent,
                    child: const ContentSizeScope(
                      child: ChatRowTextColumn(
                        title: Text('国Ag', style: TextStyle(fontSize: 17)),
                        body: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: 4),
                            ChatPreviewText(message: '国Ag'),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            appScale: .9,
            system: system,
            height: 3,
          ),
        );
        final context = tester.element(find.byType(ChatRowTextColumn));
        final data = ContentSizeScope.of(context);
        double lineHeight(double size, TextScaler scaler) {
          final painter = TextPainter(
            text: TextSpan(
              text: '国Ag',
              style: DefaultTextStyle.of(
                context,
              ).style.copyWith(fontSize: size),
            ),
            textDirection: TextDirection.ltr,
            textScaler: scaler,
            maxLines: 1,
          )..layout();
          final height = painter.height;
          painter.dispose();
          return height;
        }

        final titleHeight = lineHeight(
          data.systemTextScaler.scale(17 * .9),
          TextScaler.noScaling,
        );
        final preview = tester.renderObject<RenderParagraph>(
          find.descendant(
            of: find.byType(ChatPreviewText),
            matching: find.byType(RichText),
          ),
        );
        expect(
          metrics.extent,
          closeTo(titleHeight + 4 + preview.size.height + 16, 1e-9),
        );
        expect(metrics.extent, greaterThan(64.8));
        expect(tester.takeException(), isNull);
      }
    },
  );

  _platformTestWidgets(
    'topic, draft and sender previews share Small and AX role scaling',
    TargetPlatform.iOS,
    (tester) async {
      final theme = await controller();
      for (final system in <TextScaler>[
        const TextScaler.linear(.823),
        TextScaler.noScaling,
        const TextScaler.linear(2),
        const _GrowingNonlinearScaler(),
      ]) {
        for (final app in [.9, 1.0, 1.6]) {
          late ChatRowMetrics metrics;
          await tester.pumpWidget(
            harness(
              theme,
              SizedBox(
                width: 390,
                child: Builder(
                  builder: (context) {
                    metrics = ChatRowMetrics.resolve(context, width: 390);
                    return Column(
                      children: [
                        TopicListRowView(
                          topic: const TopicNavigationItem(
                            id: 1,
                            name: 'Topic',
                            lastPreview: 'Topic preview',
                            lastSender: 'Sender',
                          ),
                          selected: false,
                          onTap: () {},
                        ),
                        const ContentSizeScope(
                          child: ChatPreviewText(message: 'Draft', draft: true),
                        ),
                      ],
                    );
                  },
                ),
              ),
              appScale: app,
              system: system,
            ),
          );
          final previewSize = 13.0 * math.max(app, 1.0);
          final expected = math.max(previewSize, system.scale(previewSize));
          expect(
            _fontPixels(_paragraph(tester, 'Sender: Topic preview')),
            closeTo(expected, 1e-9),
          );
          for (final element
              in find
                  .descendant(
                    of: find.byType(ChatPreviewText),
                    matching: find.byType(RichText),
                  )
                  .evaluate()) {
            expect(
              _fontPixels(element.renderObject! as RenderParagraph),
              closeTo(expected, 1e-9),
            );
          }
          expect(
            _fontPixels(_paragraph(tester, 'Topic')),
            closeTo(math.max(17 * app, system.scale(17 * app)), 1e-9),
          );
          expect(
            tester.getSize(find.byType(TopicListRowView)).height,
            metrics.extent,
          );
          expect(tester.takeException(), isNull);
        }
      }
    },
  );

  for (final platform in [
    TargetPlatform.macOS,
    TargetPlatform.windows,
    TargetPlatform.linux,
  ]) {
    _platformTestWidgets(
      '$platform rendered row keeps Small and sub-default OS sizes',
      platform,
      (tester) async {
        final theme = await controller();
        final chat = ChatSummary(
          id: 412,
          title: 'Desktop name',
          lastMessage: 'Desktop preview',
          lastMessageId: 1,
          date: 0,
          unreadCount: 0,
          order: 1,
          isMuted: false,
        );
        late ChatRowMetrics metrics;
        await tester.pumpWidget(
          harness(
            theme,
            SizedBox(
              width: 390,
              child: Builder(
                builder: (context) {
                  metrics = chatRowMetricsFor(context, chat, width: 390);
                  return ChatRowView(chat: chat);
                },
              ),
            ),
            appScale: .9,
            system: const TextScaler.linear(.823),
          ),
        );
        expect(
          _fontPixels(_paragraph(tester, 'Desktop name')),
          closeTo(14 * .9 * .823, 1e-9),
        );
        expect(
          _fontPixels(_paragraph(tester, 'Desktop preview')),
          closeTo(12 * .9 * .823, 1e-9),
        );
        expect(
          tester.widget<PhotoAvatar>(find.byType(PhotoAvatar)).size,
          44 * .9,
        );
        expect(tester.getSize(find.byType(ChatRowView)).height, metrics.extent);
        expect(metrics.extent, closeTo(44 * .9 + 14, 1e-9));
        expect(tester.takeException(), isNull);
      },
    );
  }

  _platformTestWidgets(
    'live OS changes preserve saved font/UI choices across relaunch',
    TargetPlatform.iOS,
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'fontScale': .9,
        'interfaceScale': 1.1,
      });
      final prefs = await SharedPreferences.getInstance();
      var theme = ThemeController(prefs);
      final os = ValueNotifier<TextScaler>(const TextScaler.linear(.823));
      addTearDown(os.dispose);
      late TextScaler chrome;
      late TextScaler content;
      late TextScaler preview;
      final cached = Column(
        children: [
          Builder(
            builder: (context) {
              chrome = MediaQuery.textScalerOf(context);
              return const SizedBox();
            },
          ),
          ContentSizeScope(
            child: Builder(
              builder: (context) {
                content = MediaQuery.textScalerOf(context);
                preview = ContentSizeScope.chatListPreviewScalerOf(context);
                return const SizedBox();
              },
            ),
          ),
        ],
      );
      final before = {for (final key in prefs.getKeys()) key: prefs.get(key)};
      try {
        Future<void> pump() => tester.pumpWidget(
          ValueListenableBuilder<TextScaler>(
            valueListenable: os,
            child: cached,
            builder: (context, system, child) => harness(
              theme,
              child!,
              appScale: theme.fontScale,
              system: system,
              interfaceScale: theme.renderedInterfaceScale,
            ),
          ),
        );
        await pump();
        expect(chrome.scale(17), 17);
        expect(content.scale(17), closeTo(15.3, 1e-9));
        expect(preview.scale(13), 13);
        os.value = const _GrowingNonlinearScaler();
        await tester.pump();
        expect(chrome.scale(17), os.value.scale(17));
        expect(content.scale(17), os.value.scale(17 * .9));
        expect(preview.scale(13), os.value.scale(13));
        os.value = const TextScaler.linear(.823);
        await tester.pump();
        expect(content.scale(17), closeTo(15.3, 1e-9));
        await tester.pumpWidget(const SizedBox());
        theme.dispose();
        await prefs.reload();
        theme = ThemeController(prefs);
        await pump();
        expect(theme.fontScale, .9);
        expect(theme.renderedInterfaceScale, 1.1);
        expect(os.value.scale(17), 17 * .823);
        expect({
          for (final key in prefs.getKeys()) key: prefs.get(key),
        }, before);
        expect(preview.scale(13), 13);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        theme.dispose();
      }
    },
  );
}
