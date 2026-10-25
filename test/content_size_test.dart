import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/scaled_app_view.dart';
import 'package:mithka/theme/content_size.dart';

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize + fontSize * fontSize / 20;
  @override
  double get textScaleFactor => 1.7;
}

void main() {
  testWidgets('root preserves nonlinear OS chrome; nested scopes replace', (
    tester,
  ) async {
    const system = _NonlinearScaler();
    final values = <String, TextScaler>{};
    Widget probe(String key) => Builder(
      builder: (context) {
        values[key] = MediaQuery.textScalerOf(context);
        return const SizedBox();
      },
    );
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: system),
        child: ContentSizeRoot(
          appScale: 1.6,
          child: Column(
            children: [
              probe('chrome'),
              ContentSizeScope(
                child: Column(
                  children: [
                    probe('content'),
                    ContentSizeScope(child: probe('nested')),
                    ContentSizeScope(appScale: 2, child: probe('custom')),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    expect(values['chrome'], same(system));
    for (final size in [12.0, 17.0, 32.0]) {
      expect(values['content']!.scale(size), system.scale(size * 1.6));
      expect(values['nested']!.scale(size), system.scale(size * 1.6));
      expect(values['custom']!.scale(size), system.scale(size * 2));
    }
    expect(values['custom']!.scale(32), greaterThan(32 * 2));
  });

  testWidgets('interface transform retains geometry and original OS scaler', (
    tester,
  ) async {
    const system = _NonlinearScaler();
    late MediaQueryData media;
    late ContentSizeData size;
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: MediaQuery(
          data: const MediaQueryData(
            size: Size(600, 900),
            viewInsets: EdgeInsets.only(bottom: 300),
            textScaler: system,
          ),
          child: ScaledAppView(
            textScale: 1.35,
            interfaceScale: 1.5,
            child: Builder(
              builder: (context) {
                media = MediaQuery.of(context);
                size = ContentSizeScope.of(context);
                return const SizedBox();
              },
            ),
          ),
        ),
      ),
    );
    expect(media.size, const Size(400, 600));
    expect(media.viewInsets.bottom, 200);
    expect(media.textScaler, same(system));
    expect(size.systemTextScaler, same(system));
    expect(size.appScale, 1.35);
  });

  testWidgets('OS changes reach a cached mounted content subtree', (
    tester,
  ) async {
    final system = ValueNotifier<TextScaler>(const TextScaler.linear(1));
    addTearDown(system.dispose);
    late TextScaler content;
    late TextScaler chrome;
    final cached = ContentSizeRoot(
      appScale: 1.6,
      child: Column(
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
                return const SizedBox();
              },
            ),
          ),
        ],
      ),
    );
    await tester.pumpWidget(
      ValueListenableBuilder<TextScaler>(
        valueListenable: system,
        child: cached,
        builder: (context, scaler, child) => MediaQuery(
          data: MediaQueryData(textScaler: scaler),
          child: child!,
        ),
      ),
    );
    expect(content.scale(17), closeTo(17 * 1.6, .001));
    system.value = const _NonlinearScaler();
    await tester.pump();
    expect(chrome, same(system.value));
    expect(content.scale(17), system.value.scale(17 * 1.6));
    system.value = const TextScaler.linear(3.2);
    await tester.pump();
    expect(content.scale(17), closeTo(17 * 1.6 * 3.2, .001));
  });

  testWidgets('outside root defaults to one and current system scaler', (
    tester,
  ) async {
    late ContentSizeData data;
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(.85)),
        child: Builder(
          builder: (context) {
            data = ContentSizeScope.of(context);
            return const SizedBox();
          },
        ),
      ),
    );
    expect(data.appScale, 1);
    expect(data.systemTextScaler.scale(20), 17);
    expect(contentSizePresets, [.9, 1, 1.1, 1.2, 1.35, 1.6]);
  });
}
