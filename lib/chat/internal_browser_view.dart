import 'dart:async';

import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'link_browser.dart';

class InternalBrowserView extends StatefulWidget {
  const InternalBrowserView({
    super.key,
    required this.initialUri,
    this.onOpenInApp,
  });

  final Uri initialUri;
  final Future<void> Function(String url)? onOpenInApp;

  @override
  State<InternalBrowserView> createState() => _InternalBrowserViewState();
}

class _InternalBrowserViewState extends State<InternalBrowserView> {
  late final WebViewController _controller;
  late Uri _currentUri;
  var _progress = 0;
  var _canGoBack = false;
  var _canGoForward = false;
  var _navigationRevision = 0;

  @override
  void initState() {
    super.initState();
    assert(internalBrowserCanOpen(widget.initialUri));
    _currentUri = widget.initialUri;
    _controller =
        WebViewController(
            onPermissionRequest: (request) => unawaited(request.deny()),
          )
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..setNavigationDelegate(
            NavigationDelegate(
              onProgress: (value) {
                if (mounted) setState(() => _progress = value);
              },
              onUrlChange: (change) => _recordUrl(change.url),
              onPageStarted: (url) {
                _recordUrl(url);
                unawaited(_refreshNavigationState());
              },
              onPageFinished: (url) {
                _recordUrl(url);
                unawaited(_refreshNavigationState());
              },
              onNavigationRequest: (request) {
                final action = internalBrowserNavigationAction(
                  url: request.url,
                  isMainFrame: request.isMainFrame,
                );
                switch (action) {
                  case InternalBrowserNavigationAction.navigate:
                    return NavigationDecision.navigate;
                  case InternalBrowserNavigationAction.openInApp:
                    unawaited(_openInApp(request.url));
                    return NavigationDecision.prevent;
                  case InternalBrowserNavigationAction.openExternally:
                    final uri = Uri.tryParse(request.url);
                    if (uri != null) unawaited(launchInDefaultBrowser(uri));
                    return NavigationDecision.prevent;
                  case InternalBrowserNavigationAction.block:
                    return NavigationDecision.prevent;
                }
              },
              onSslAuthError: (error) => unawaited(error.cancel()),
            ),
          );

    if (_controller.platform is AndroidWebViewController) {
      final android = _controller.platform as AndroidWebViewController;
      unawaited(android.setAllowFileAccess(false));
      unawaited(android.setAllowContentAccess(false));
      unawaited(android.setMixedContentMode(MixedContentMode.neverAllow));
    }
    unawaited(_controller.loadRequest(widget.initialUri));
  }

  void _recordUrl(String? value) {
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || !internalBrowserCanOpen(uri) || !mounted) return;
    setState(() => _currentUri = uri);
  }

  Future<void> _refreshNavigationState() async {
    final revision = ++_navigationRevision;
    try {
      final values = await Future.wait([
        _controller.canGoBack(),
        _controller.canGoForward(),
      ]);
      if (!mounted || revision != _navigationRevision) return;
      setState(() {
        _canGoBack = values[0];
        _canGoForward = values[1];
      });
    } catch (_) {}
  }

  Future<void> _openInApp(String url) async {
    final callback = widget.onOpenInApp;
    if (callback != null) {
      await callback(url);
      return;
    }
    final uri = Uri.tryParse(url);
    if (uri != null) await launchInDefaultBrowser(uri);
  }

  Future<void> _goBack() async {
    if (!await _controller.canGoBack()) return;
    await _controller.goBack();
    await _refreshNavigationState();
  }

  Future<void> _goForward() async {
    if (!await _controller.canGoForward()) return;
    await _controller.goForward();
    await _refreshNavigationState();
  }

  String get _originLabel {
    final defaultPort = _currentUri.scheme == 'https' ? 443 : 80;
    final port = _currentUri.hasPort && _currentUri.port != defaultPort
        ? ':${_currentUri.port}'
        : '';
    return '${_currentUri.scheme}://${_currentUri.host}$port';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return PopScope(
      canPop: !_canGoBack,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_goBack());
      },
      child: Scaffold(
        backgroundColor: c.background,
        body: Column(
          children: [
            NavHeader(
              title: AppStringKeys.linkBrowserTitle,
              onBack: () => Navigator.of(context).pop(),
              trailing: _BrowserToolbarButton(
                semanticLabel: AppStringKeys.linkBrowserOpenInDefaultBrowser
                    .l10n(context),
                icon: HeroAppIcons.arrowTopRight,
                onTap: () => unawaited(launchInDefaultBrowser(_currentUri)),
              ),
            ),
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                color: c.navBar,
                border: Border(
                  bottom: BorderSide(
                    color: c.divider,
                    width: AppMetric.divider,
                  ),
                ),
              ),
              child: Row(
                children: [
                  _BrowserToolbarButton(
                    semanticLabel: AppStringKeys.linkBrowserBack.l10n(context),
                    icon: HeroAppIcons.arrowLeft,
                    enabled: _canGoBack,
                    onTap: () => unawaited(_goBack()),
                  ),
                  _BrowserToolbarButton(
                    semanticLabel: AppStringKeys.linkBrowserForward.l10n(
                      context,
                    ),
                    icon: HeroAppIcons.arrowRight,
                    enabled: _canGoForward,
                    onTap: () => unawaited(_goForward()),
                  ),
                  _BrowserToolbarButton(
                    semanticLabel: AppStringKeys.linkBrowserReload.l10n(
                      context,
                    ),
                    icon: HeroAppIcons.arrowsRotate,
                    onTap: () => unawaited(_controller.reload()),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Semantics(
                      label: AppStringKeys.linkBrowserAddress.l10n(context),
                      value: _originLabel,
                      child: Container(
                        height: 34,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.md,
                        ),
                        decoration: BoxDecoration(
                          color: c.card,
                          borderRadius: BorderRadius.circular(
                            AppRadius.control,
                          ),
                          border: Border.all(
                            color: c.divider,
                            width: AppMetric.divider,
                          ),
                        ),
                        child: Row(
                          children: [
                            AppIcon(
                              HeroAppIcons.lock,
                              size: AppIconSize.sm,
                              color: c.textSecondary,
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                _originLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: AppTextStyle.caption(c.textSecondary),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 2,
              child: Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: _progress <= 0 || _progress >= 100
                      ? 0
                      : _progress / 100,
                  child: ColoredBox(color: AppTheme.brand),
                ),
              ),
            ),
            Expanded(child: WebViewWidget(controller: _controller)),
          ],
        ),
      ),
    );
  }
}

class _BrowserToolbarButton extends StatelessWidget {
  const _BrowserToolbarButton({
    required this.semanticLabel,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String semanticLabel;
  final AppIconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      semanticLabel: semanticLabel,
      enabled: enabled,
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox.square(
        dimension: 44,
        child: Center(
          child: AppIcon(
            icon,
            size: AppIconSize.lg,
            color: enabled ? c.textPrimary : c.textTertiary,
          ),
        ),
      ),
    );
  }
}
