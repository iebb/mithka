//
//  main.dart
//
//  MithkaApp entry point. Wires the controllers (AuthManager, ThemeController,
//  AccountStore, DrawerController) as providers, applies the adaptive theme +
//  themeMode, and keys the content on the active account so the whole tree
//  rebuilds for the newly active account. Port of the Swift `MithkaApp`.
//

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:fvp/fvp.dart' as fvp;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/content_view.dart';
import 'auth/account_store.dart';
import 'auth/auth_manager.dart';
import 'components/drawer_controller.dart' as dc;
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Route video_player through the MDK/FFmpeg backend so .webm (VP9 + alpha)
  // video stickers decode + play (and stay transparent).
  fvp.registerWith();
  // Portrait only — no landscape.
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  final prefs = await SharedPreferences.getInstance();
  runApp(MithkaApp(prefs: prefs));
}

class MithkaApp extends StatefulWidget {
  const MithkaApp({super.key, required this.prefs});
  final SharedPreferences prefs;

  @override
  State<MithkaApp> createState() => _MithkaAppState();
}

class _MithkaAppState extends State<MithkaApp> {
  late final AuthManager _auth = AuthManager();
  late final ThemeController _theme = ThemeController(widget.prefs);
  late final AccountStore _accounts = AccountStore(widget.prefs);
  late final dc.DrawerController _drawer = dc.DrawerController();

  @override
  void initState() {
    super.initState();
    _auth.start();
  }

  ThemeData _themeData(Brightness brightness) {
    final colors = brightness == Brightness.dark
        ? AppColors.dark
        : AppColors.light;
    return ThemeData(
      brightness: brightness,
      useMaterial3: true,
      scaffoldBackgroundColor: colors.background,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppTheme.brand,
        brightness: brightness,
      ),
      extensions: [colors],
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: _auth),
        ChangeNotifierProvider.value(value: _theme),
        ChangeNotifierProvider.value(value: _accounts),
        ChangeNotifierProvider<dc.DrawerController>.value(value: _drawer),
      ],
      child: Consumer2<ThemeController, AccountStore>(
        builder: (context, theme, accounts, _) {
          return MaterialApp(
            title: 'Mithka',
            debugShowCheckedModeBanner: false,
            theme: _themeData(Brightness.light),
            darkTheme: _themeData(Brightness.dark),
            themeMode: theme.themeMode,
            // Apply the user's chosen font size app-wide (设置 › 通用 › 字体大小).
            builder: (context, child) {
              return _ScaledAppView(
                fontScale: theme.fontScale,
                interfaceScale: theme.interfaceScale,
                child: child ?? const SizedBox.shrink(),
              );
            },
            // Rebuild the whole tree when the active account changes.
            home: KeyedSubtree(
              key: ValueKey(accounts.activeSlot),
              child: const ContentView(),
            ),
          );
        },
      ),
    );
  }
}

class _ScaledAppView extends StatelessWidget {
  const _ScaledAppView({
    required this.fontScale,
    required this.interfaceScale,
    required this.child,
  });

  final double fontScale;
  final double interfaceScale;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final scale = interfaceScale;
    final virtualSize = Size(
      media.size.width / scale,
      media.size.height / scale,
    );
    final scaledMedia = media.copyWith(
      size: virtualSize,
      padding: _unscaleInsets(media.padding, scale),
      viewPadding: _unscaleInsets(media.viewPadding, scale),
      viewInsets: _unscaleInsets(media.viewInsets, scale),
      systemGestureInsets: _unscaleInsets(media.systemGestureInsets, scale),
      textScaler: TextScaler.linear(fontScale / scale),
    );

    return ClipRect(
      child: OverflowBox(
        alignment: Alignment.topLeft,
        minWidth: virtualSize.width,
        maxWidth: virtualSize.width,
        minHeight: virtualSize.height,
        maxHeight: virtualSize.height,
        child: Transform.scale(
          scale: scale,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: virtualSize.width,
            height: virtualSize.height,
            child: MediaQuery(data: scaledMedia, child: child),
          ),
        ),
      ),
    );
  }

  EdgeInsets _unscaleInsets(EdgeInsets insets, double scale) {
    return EdgeInsets.fromLTRB(
      insets.left / scale,
      insets.top / scale,
      insets.right / scale,
      insets.bottom / scale,
    );
  }
}
