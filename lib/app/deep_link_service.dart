//
//  deep_link_service.dart
//
//  Bridges OS-delivered links into the in-app link handler. The app registers
//  its own mk:// and mithka:// schemes (tg:// grammar) plus tg:// on macOS,
//  iOS and Android, and t.me / telegram.me / telegram.dog web links on
//  Android. app_links surfaces both the launch URI and URIs that arrive
//  while running.
//
//  Hand-off form for other surfaces (share extensions, other apps):
//  `mk://open?url=<percent-encoded tg://, t.me or telegram.me link>` — see
//  `mithkaOpenLinkFor` in chat/telegram_link.dart. Only Mithka registers mk://,
//  so it reaches Mithka even when an official Telegram client claims tg://.
//

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../auth/auth_manager.dart';
import '../chat/link_browser.dart';
import '../chat/link_handler.dart';
import '../chat/telegram_link.dart';
import '../components/toast.dart';
import '../l10n/app_localizations.dart';
import '../security/local_app_lock_controller.dart';
import '../settings/proxy_config.dart';
import 'app_navigator.dart';

/// What to do with a queued external link in the current app state.
enum DeepLinkGate {
  /// Open it now.
  open,

  /// Keep it: the app is starting, in the background, switching accounts or
  /// locked.
  wait,

  /// Keep it until an account is logged in; the login screen says so.
  logIn,
}

/// [needsAccount] is false for links that work signed out (proxy links) and
/// for plain notices. [foreground] is false until the app is resumed: a link
/// usually arrives while the app is still coming to the front, and a notice
/// shown then runs its timer before any frame is drawn, so it is gone before
/// the user sees it.
@visibleForTesting
DeepLinkGate deepLinkGateFor(
  AuthStep step, {
  required bool locked,
  required bool needsAccount,
  bool foreground = true,
}) {
  if (!foreground || locked) return DeepLinkGate.wait;
  if (step is AuthInitializing ||
      step is AuthReloading ||
      step is AuthLoggingOut ||
      step is AuthClosed) {
    return DeepLinkGate.wait;
  }
  if (!needsAccount || step is AuthReady) return DeepLinkGate.open;
  return DeepLinkGate.logIn;
}

/// Whether [state] counts as the app being in front. Null means the platform
/// has not reported a state yet (early cold start); links then wait for auth
/// anyway, so treating it as foreground cannot strand them.
@visibleForTesting
bool deepLinkAppInForeground(AppLifecycleState? state) =>
    state == null || state == AppLifecycleState.resumed;

/// One thing an external link asks for, run once the app is in front.
sealed class _ExternalAction {
  const _ExternalAction();
}

/// Open a Telegram link in-app.
class _OpenTelegramLink extends _ExternalAction {
  const _OpenTelegramLink(this.link);
  final String link;
}

/// Open a page that has nothing in-app (the bare t.me page) in the browser.
class _OpenInBrowser extends _ExternalAction {
  const _OpenInBrowser(this.uri);
  final Uri uri;
}

/// Show a notice, e.g. linkNotTelegramLink.
class _ShowNotice extends _ExternalAction {
  const _ShowNotice(this.messageKey);
  final String messageKey;
}

class DeepLinkService extends ChangeNotifier with WidgetsBindingObserver {
  DeepLinkService._();

  static final DeepLinkService shared = DeepLinkService._();

  AppLinks? _links;
  StreamSubscription<Uri>? _sub;
  AuthManager? _auth;
  LocalAppLockController? _appLock;

  /// The latest external link waiting for the foreground, login, unlock or
  /// startup. A newer link replaces it: only the last thing the user tapped
  /// is acted on.
  _ExternalAction? _pending;
  bool _draining = false;

  /// Whether a link is waiting for the user to log in. The login screen shows
  /// `linkLogInToOpen` while this is true.
  bool get waitingForLogIn => _pending != null && _gate() == DeepLinkGate.logIn;

  /// Starts listening. Safe to call more than once; later calls are no-ops.
  ///
  /// Without [auth], links open as soon as the app is in front (no sign-in
  /// queue).
  void start({AuthManager? auth, LocalAppLockController? appLock}) {
    if (_sub != null) return;
    _auth = auth?..addListener(_stateChanged);
    _appLock = appLock?..addListener(_stateChanged);
    WidgetsBinding.instance.addObserver(this);
    final links = _links ??= AppLinks();
    // uriLinkStream replays the launch URI, so cold-start links work too.
    _sub = links.uriLinkStream.listen(
      (uri) => unawaited(_handle(uri)),
      onError: (Object error) => debugPrint('deep link error: $error'),
    );
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    WidgetsBinding.instance.removeObserver(this);
    _auth?.removeListener(_stateChanged);
    _appLock?.removeListener(_stateChanged);
    _auth = null;
    _appLock = null;
    _pending = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _stateChanged();

  DeepLinkGate _gate() {
    final pending = _pending;
    return deepLinkGateFor(
      _auth?.step ?? const AuthReady(),
      locked: _appLock?.locked ?? false,
      needsAccount: switch (pending) {
        _OpenTelegramLink(:final link) => !_worksSignedOut(link),
        _OpenInBrowser() || _ShowNotice() => false,
        null => true,
      },
      foreground: deepLinkAppInForeground(
        WidgetsBinding.instance.lifecycleState,
      ),
    );
  }

  static bool _worksSignedOut(String link) {
    final normalized = normalizeTelegramLink(link);
    return normalized != null &&
        ProxyConfig.fromTelegramUrl(normalized) != null;
  }

  void _stateChanged() {
    if (_pending == null) return;
    notifyListeners();
    unawaited(_drain());
  }

  Future<void> _handle(Uri uri) async {
    final external = classifyExternalLink(uri);
    final _ExternalAction action;
    switch (external.kind) {
      case ExternalLinkKind.ignored:
        return;
      case ExternalLinkKind.notTelegram:
        action = const _ShowNotice(AppStringKeys.linkNotTelegramLink);
      case ExternalLinkKind.telegram:
        final link = external.link!;
        // The bare t.me home page has nothing to open in-app or to log in
        // for.
        final parsed = Uri.tryParse(link);
        action = parsed != null && isTelegramWebHomePage(parsed)
            ? _OpenInBrowser(parsed)
            : _OpenTelegramLink(link);
    }
    _pending = action;
    notifyListeners();
    await _drain();
  }

  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (_pending != null && _gate() == DeepLinkGate.open) {
        final action = _pending!;
        _pending = null;
        notifyListeners();
        // Let the gate's rebuild (login → chat list) and the first frame in
        // front land before pushing a route or showing a notice.
        await SchedulerBinding.instance.endOfFrame;
        final context = await _navigatorContext();
        if (context == null || !context.mounted) {
          debugPrint('deep link dropped (no navigator)');
          continue;
        }
        try {
          switch (action) {
            case _OpenTelegramLink(:final link):
              // Mithka is itself a tg:// handler now: a tg:// link it cannot
              // open must not be relaunched externally, or it would come
              // back.
              await openLink(context, link, keepTelegramInApp: true);
            case _OpenInBrowser(:final uri):
              await launchInDefaultBrowser(uri);
            case _ShowNotice(:final messageKey):
              showToast(context, AppStrings.t(messageKey));
          }
        } catch (error) {
          debugPrint('deep link failed: $error');
        }
      }
    } finally {
      _draining = false;
    }
  }

  /// Waits for a navigator if the link raced the first frame.
  Future<BuildContext?> _navigatorContext() async {
    for (var attempt = 0; attempt < 40; attempt++) {
      final context = appNavigatorKey.currentContext;
      if (context != null && context.mounted) return context;
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    return null;
  }
}
