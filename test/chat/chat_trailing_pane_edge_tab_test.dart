import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mithka/app/adaptive_split_layout.dart';
import 'package:mithka/chat/admin/chat_info_view.dart';
import 'package:mithka/chat/chat_view.dart';
import 'package:mithka/chat/desktop_chat_context_pane.dart';
import 'package:mithka/l10n/app_localizations.dart';
import 'package:mithka/theme/app_theme.dart';
import 'package:mithka/theme/theme_controller.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Writes PNGs of each state to build/info-pane-tab-captures when set.
const _capture = bool.fromEnvironment('CAPTURE_INFO_PANE_TAB');

/// Directory holding [_fontPrefix]*.ttf, so captures use real glyphs.
const _fontDir = String.fromEnvironment('INFO_PANE_TAB_FONT_DIR');
const _fontPrefix = String.fromEnvironment(
  'INFO_PANE_TAB_FONT_PREFIX',
  defaultValue: 'Roboto-',
);

/// An opened iPhone Duo window, in points.
const _openedDuo = Size(951, 669);
const _headerHeight = 66.0;

final _paneKey = find.byKey(const ValueKey('chatTrailingContextPane'));
final _tabKey = find.byKey(const ValueKey('chatTrailingPaneEdgeTab'));
final _gripKey = find.byKey(const ValueKey('chatTrailingPaneEdgeTabGrip'));
final _contentKey = find.byKey(const ValueKey('chatConversationContent'));

bool _realFonts = false;

void main() {
  setUpAll(() async {
    _realFonts = await _loadRealFonts();
  });

  for (final dark in const [false, true]) {
    final mode = dark ? 'dark' : 'light';
    testWidgets('opened Duo ($mode): the edge tab closes and reopens the '
        'group info pane without taking width', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pump(tester, dark: dark);
      final detail = tester.getRect(find.byType(ChatHeaderTrailingPaneLayout));
      final body = Rect.fromLTRB(
        detail.left,
        detail.top + _headerHeight,
        detail.right,
        detail.bottom,
      );

      // Open: the grip protrudes from the pane's leading edge, centred in the
      // body, and the conversation keeps everything left of the divider.
      expect(_paneKey, findsOneWidget);
      expect(
        find.byKey(const ValueKey('desktopChatContextPane')),
        findsOneWidget,
      );
      final pane = tester.getRect(_paneKey);
      expect(pane.width, desktopInfoPaneWidth);
      expect(
        tester.getRect(_contentKey).width,
        detail.width - desktopInfoPaneWidth - desktopInfoPaneHandleWidth,
      );
      var grip = tester.getRect(_gripKey);
      expect(grip.size, const Size(16, 56));
      expect(grip.right, pane.left);
      expect(grip.center.dy, moreOrLessEquals(body.center.dy));
      final hit = tester.getRect(_tabKey);
      expect(hit.width, greaterThanOrEqualTo(44));
      expect(hit.height, greaterThanOrEqualTo(44));
      expect(hit.right, grip.right);
      expect(find.bySemanticsLabel('Hide group info'), findsOneWidget);
      await _captureIfEnabled(tester, 'opened-duo-$mode-open');

      // Closed: the conversation spans the detail pane and the same tab sits
      // on its trailing edge.
      await tester.tap(_tabKey);
      await tester.pumpAndSettle();
      expect(_paneKey, findsNothing);
      expect(tester.getRect(_contentKey).width, detail.width);
      expect(_tabKey, findsOneWidget);
      grip = tester.getRect(_gripKey);
      expect(grip.right, detail.right);
      expect(grip.center.dy, moreOrLessEquals(body.center.dy));
      expect(find.bySemanticsLabel('Show group info'), findsOneWidget);
      await _captureIfEnabled(tester, 'opened-duo-$mode-collapsed');

      // Reopened by the same tab.
      await tester.tap(_tabKey);
      await tester.pumpAndSettle();
      expect(_paneKey, findsOneWidget);
      expect(tester.getRect(_gripKey).right, tester.getRect(_paneKey).left);
      semantics.dispose();
    });
  }

  testWidgets('toggling keeps the conversation element mounted', (
    tester,
  ) async {
    await _pump(tester, dark: false);
    final before = tester.state(find.byType(_ProbeBody));
    await tester.tap(_tabKey);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(_ProbeBody)), same(before));
    await tester.tap(_tabKey);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(_ProbeBody)), same(before));
  });

  testWidgets('no tab where the pane cannot be toggled', (tester) async {
    await _pump(tester, dark: false, canToggle: false);
    expect(_tabKey, findsNothing);
    expect(_paneKey, findsNothing);
  });
}

class _ProbeBody extends StatefulWidget {
  const _ProbeBody();

  @override
  State<_ProbeBody> createState() => _ProbeBodyState();
}

class _ProbeBodyState extends State<_ProbeBody> {
  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.chatBackground,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: c.inputBarBackground,
            border: Border(top: BorderSide(color: c.divider)),
          ),
        ),
      ),
    );
  }
}

/// Mirrors the shell: one bool owns the pane, and the toggle exists only
/// while the pane fits beside the chat.
class _Shell extends StatefulWidget {
  const _Shell({required this.viewModel, required this.canToggle});

  final ChatInfoViewModel viewModel;
  final bool canToggle;

  @override
  State<_Shell> createState() => _ShellState();
}

class _ShellState extends State<_Shell> {
  bool _shown = true;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final sidebarWidth = defaultSplitSidebarWidth(_openedDuo.width);
    final showPane = widget.canToggle && _shown;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: sidebarWidth,
          child: ColoredBox(color: c.background),
        ),
        VerticalDivider(width: 1, thickness: 1, color: c.divider),
        Expanded(
          child: ChatHeaderTrailingPaneLayout(
            header: Container(height: _headerHeight, color: c.chatBackground),
            body: const _ProbeBody(),
            trailingPane: showPane
                ? DesktopChatContextPane(
                    chatId: 42,
                    title: 'Group',
                    viewModel: widget.viewModel,
                  )
                : null,
            trailingPaneWidth: desktopInfoPaneWidth,
            onTrailingPaneToggle: widget.canToggle
                ? () => setState(() => _shown = !_shown)
                : null,
          ),
        ),
      ],
    );
  }
}

const _boundaryKey = ValueKey('info-pane-tab-capture');

Future<void> _pump(
  WidgetTester tester, {
  required bool dark,
  bool canToggle = true,
}) async {
  await tester.binding.setSurfaceSize(_openedDuo);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  tester.view.physicalSize = _openedDuo;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final themeController = ThemeController(prefs);
  addTearDown(themeController.dispose);
  final viewModel = ChatInfoViewModel(chatId: 42, title: 'Group')
    ..isGroup = true
    ..memberCount = 3
    ..members = [
      ChatMember(1, 'Ada', null),
      ChatMember(2, 'Grace', null),
      ChatMember(3, 'Linus', null),
    ];
  await tester.pumpWidget(
    ChangeNotifierProvider<ThemeController>.value(
      value: themeController,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        theme: ThemeData(
          brightness: dark ? Brightness.dark : Brightness.light,
          extensions: [dark ? AppColors.dark : AppColors.light],
          fontFamily: _realFonts ? 'Roboto' : null,
        ),
        builder: (context, child) =>
            RepaintBoundary(key: _boundaryKey, child: child),
        home: _Shell(viewModel: viewModel, canToggle: canToggle),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<bool> _loadRealFonts() async {
  if (_fontDir.isEmpty) return false;
  final dir = Directory(_fontDir);
  if (!dir.existsSync()) return false;
  final roboto = FontLoader('Roboto');
  var any = false;
  for (final file in dir.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (!name.startsWith(_fontPrefix) || !name.endsWith('.ttf')) continue;
    roboto.addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
    any = true;
  }
  if (!any) return false;
  await roboto.load();
  // Icon fonts and any bundled families, so glyphs draw as on the device.
  final manifest = jsonDecode(await rootBundle.loadString('FontManifest.json'));
  for (final entry in manifest as List<dynamic>) {
    final loader = FontLoader(entry['family'] as String);
    for (final font in entry['fonts'] as List<dynamic>) {
      loader.addFont(rootBundle.load(font['asset'] as String));
    }
    await loader.load();
  }
  return true;
}

Future<void> _captureIfEnabled(WidgetTester tester, String name) async {
  if (!_capture) return;
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(_boundaryKey),
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 2);
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      final bytes = data!;
      final directory = Directory('build/info-pane-tab-captures');
      await directory.create(recursive: true);
      await File('${directory.path}/$name.png').writeAsBytes(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
        flush: true,
      );
    } finally {
      image.dispose();
    }
  });
}
