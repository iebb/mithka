//
//  search_view.dart
//
//  Chat search — a pushed secondary screen. Custom header (back chevron +
//  rounded search field) on the list-header wash, with a live list of matching
//  chats below. Port of the Swift `SearchView` / `_SearchViewModel`.
//

import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../app/primary_chat_launcher.dart';
import '../chat/telegram_mini_app_recents.dart';
import '../chat/telegram_mini_app_view.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/telegram_language_controller.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'chat_row_view.dart';
import 'mini_apps_page.dart';
import 'public_discovery_view.dart';

/// Shared state for the compact desktop title-bar search field and its
/// anchored result panel.
typedef DesktopMiniAppSearch =
    Future<List<TelegramMiniAppRecent>> Function(String query);

class DesktopInlineSearchController extends ChangeNotifier {
  DesktopInlineSearchController({DesktopMiniAppSearch? miniAppSearch})
    : textController = TextEditingController(),
      focusNode = FocusNode(),
      _miniAppSearch = miniAppSearch ?? TelegramMiniAppRecents.search {
    _model.addListener(_handleModelChanged);
    focusNode.addListener(_handleFocusChanged);
  }

  static const List<SearchTab> _searchTabs = [
    SearchTab.chats,
    SearchTab.posts,
    SearchTab.media,
    SearchTab.links,
    SearchTab.files,
    SearchTab.music,
    SearchTab.voice,
  ];
  static const int _chatResultLimit = 4;
  static const int _messageResultLimit = 3;
  static const int _miniAppResultLimit = 3;

  final TextEditingController textController;
  final FocusNode focusNode;
  final DesktopMiniAppSearch _miniAppSearch;
  final _SearchViewModel _model = _SearchViewModel();
  Timer? _debounce;
  String _query = '';
  bool _panelVisible = false;
  bool _debouncing = false;
  bool _miniAppsLoading = false;
  bool _disposed = false;
  int _miniAppRunId = 0;
  List<TelegramMiniAppRecent> _miniApps = const [];

  String get query => _query;
  bool get panelVisible => _panelVisible && _query.trim().isNotEmpty;
  bool get isLoading =>
      _debouncing || _miniAppsLoading || _searchTabs.any(_model.isLoading);
  List<TelegramMiniAppRecent> get _visibleMiniApps => _miniApps;
  List<_DesktopInlineSearchSection> get _visibleSections => [
    for (final tab in _searchTabs)
      if (_model.resultsFor(tab).isNotEmpty)
        _DesktopInlineSearchSection(
          tab: tab,
          hits: _model
              .resultsFor(tab)
              .take(
                tab == SearchTab.chats ? _chatResultLimit : _messageResultLimit,
              )
              .toList(growable: false),
        ),
  ];

  void focus() {
    if (_disposed) return;
    focusNode.requestFocus();
    final shouldShow = _query.trim().isNotEmpty;
    if (_panelVisible == shouldShow) return;
    _panelVisible = shouldShow;
    notifyListeners();
  }

  void updateQuery(String value) {
    if (_disposed) return;
    _query = value;
    _panelVisible = value.trim().isNotEmpty;
    _debounce?.cancel();
    // Invalidate every in-flight category as soon as the text changes. The
    // next network fan-out remains debounced, but an older query can never
    // repopulate the panel during that debounce window.
    _model.clearTabs(_searchTabs);
    _invalidateMiniApps();
    _debouncing = value.trim().isNotEmpty;
    if (value.trim().isNotEmpty) {
      _debounce = Timer(const Duration(milliseconds: 240), () {
        if (_disposed) return;
        final query = _query.trim();
        _debouncing = false;
        _model.searchMany(query, _searchTabs, resultLimitPerTab: 6);
        _startMiniAppSearch(query);
      });
    }
    notifyListeners();
  }

  void clear() {
    if (_disposed) return;
    _debounce?.cancel();
    textController.clear();
    _query = '';
    _panelVisible = false;
    _debouncing = false;
    _model.clearTabs(_searchTabs);
    _invalidateMiniApps();
    focusNode.requestFocus();
    notifyListeners();
  }

  void dismiss() {
    if (_disposed) return;
    if (!_panelVisible && !focusNode.hasFocus) return;
    _panelVisible = false;
    focusNode.unfocus();
    notifyListeners();
  }

  void _invalidateMiniApps() {
    _miniAppRunId += 1;
    _miniApps = const [];
    _miniAppsLoading = false;
  }

  void _startMiniAppSearch(String query) {
    final runId = ++_miniAppRunId;
    _miniAppsLoading = true;
    unawaited(_runMiniAppSearch(query, runId));
  }

  Future<void> _runMiniAppSearch(String query, int runId) async {
    try {
      final apps = await _miniAppSearch(query);
      if (!_isCurrentMiniAppRun(query, runId)) return;
      _miniApps = apps.take(_miniAppResultLimit).toList(growable: false);
    } catch (_) {
      if (!_isCurrentMiniAppRun(query, runId)) return;
      _miniApps = const [];
    }
    if (!_isCurrentMiniAppRun(query, runId)) return;
    _miniAppsLoading = false;
    notifyListeners();
  }

  bool _isCurrentMiniAppRun(String query, int runId) =>
      !_disposed && _miniAppRunId == runId && _query.trim() == query;

  void _handleModelChanged() {
    if (!_disposed) notifyListeners();
  }

  void _handleFocusChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _debounce?.cancel();
    _miniAppRunId += 1;
    _miniAppsLoading = false;
    _model.removeListener(_handleModelChanged);
    focusNode.removeListener(_handleFocusChanged);
    _model.dispose();
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}

class _DesktopInlineSearchSection {
  const _DesktopInlineSearchSection({required this.tab, required this.hits});

  final SearchTab tab;
  final List<_SearchHit> hits;
}

/// The always-visible desktop search input that replaces the former icon-only
/// title-bar action.
class DesktopInlineSearchField extends StatelessWidget {
  const DesktopInlineSearchField({
    super.key,
    required this.controller,
    required this.onSearchAll,
  });

  static const double width = 220;
  static const double height = 28;

  final DesktopInlineSearchController controller;
  final FutureOr<void> Function(String query) onSearchAll;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = context.colors;
      return Focus(
        onKeyEvent: (_, event) {
          if (event is KeyDownEvent &&
              event.logicalKey == LogicalKeyboardKey.escape) {
            controller.dismiss();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          key: const ValueKey('desktop-title-bar-search'),
          width: width,
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: c.searchFill,
            borderRadius: BorderRadius.circular(7),
            border: Border.all(
              color: controller.focusNode.hasFocus
                  ? AppTheme.brand.withValues(alpha: 0.72)
                  : c.divider.withValues(alpha: 0.55),
              width: controller.focusNode.hasFocus ? 1.25 : 0.5,
            ),
          ),
          child: Row(
            children: [
              AppIcon(
                HeroAppIcons.magnifyingGlass,
                size: 14,
                color: c.textTertiary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: CupertinoTextField(
                  key: const ValueKey('desktop-title-bar-search-input'),
                  controller: controller.textController,
                  focusNode: controller.focusNode,
                  autocorrect: false,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(fontSize: 13, color: c.textPrimary),
                  placeholder: AppStrings.t(
                    AppStringKeys.chatsSearchPlaceholder,
                  ),
                  placeholderStyle: TextStyle(
                    fontSize: 13,
                    color: c.textTertiary,
                  ),
                  padding: EdgeInsets.zero,
                  decoration: null,
                  onTap: controller.focus,
                  onChanged: controller.updateQuery,
                  onSubmitted: (value) {
                    final query = value.trim();
                    if (query.isEmpty) return;
                    controller.dismiss();
                    unawaited(Future<void>.sync(() => onSearchAll(query)));
                  },
                ),
              ),
              if (controller.query.isNotEmpty)
                AppInteractiveSurface(
                  key: const ValueKey('desktop-title-bar-search-clear'),
                  semanticLabel: AppStringKeys.desktopSearchClear.l10n(context),
                  onTap: controller.clear,
                  borderRadius: BorderRadius.circular(9),
                  child: SizedBox.square(
                    dimension: 18,
                    child: Center(
                      child: AppIcon(
                        HeroAppIcons.xmark,
                        size: 12,
                        color: c.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

/// Compact in-place desktop results. Full category search remains available
/// through the fixed bottom action without replacing the current workspace.
class DesktopInlineSearchPanel extends StatelessWidget {
  const DesktopInlineSearchPanel({
    super.key,
    required this.controller,
    required this.onSearchAll,
    this.onSearchCategory,
    this.onOpenMiniApp,
  });

  static const double width = 440;
  static const double maxResultsHeight = 464;

  final DesktopInlineSearchController controller;
  final FutureOr<void> Function(String query) onSearchAll;

  /// Section-header chevron: run the full search scoped to that category.
  /// Falls back to [onSearchAll] when null.
  final FutureOr<void> Function(String query, SearchTab tab)? onSearchCategory;
  final FutureOr<void> Function(TelegramMiniAppRecent app)? onOpenMiniApp;

  void _openCategory(SearchTab tab) {
    final query = controller.query.trim();
    if (query.isEmpty) return;
    controller.dismiss();
    final scoped = onSearchCategory;
    if (scoped != null) {
      unawaited(Future<void>.sync(() => scoped(query, tab)));
    } else {
      unawaited(Future<void>.sync(() => onSearchAll(query)));
    }
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.panelVisible) return const SizedBox.shrink();
      final c = context.colors;
      final sections = controller._visibleSections;
      final miniApps = controller._visibleMiniApps;
      return Container(
        key: const ValueKey('desktop-inline-search-panel'),
        width: width,
        constraints: const BoxConstraints(maxHeight: 540),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: c.divider, width: 0.75),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF000000).withValues(alpha: 0.22),
              blurRadius: 24,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxHeight: maxResultsHeight,
                  minHeight: 76,
                ),
                child: _resultList(context, sections, miniApps),
              ),
            ),
            Container(height: 0.5, color: c.divider),
            AppInteractiveSurface(
              key: const ValueKey('desktop-inline-search-all'),
              semanticLabel: AppStringKeys.desktopSearchAll.l10n(context),
              onTap: () {
                final query = controller.query.trim();
                if (query.isEmpty) return;
                controller.dismiss();
                unawaited(Future<void>.sync(() => onSearchAll(query)));
              },
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(12),
              ),
              child: SizedBox(
                height: 58,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.brand,
                          shape: BoxShape.circle,
                        ),
                        child: const AppIcon(
                          HeroAppIcons.magnifyingGlass,
                          size: 17,
                          color: Color(0xFFFFFFFF),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '${AppStringKeys.desktopSearchAll.l10n(context)}  ${controller.query.trim()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      AppIcon(
                        HeroAppIcons.chevronRight,
                        size: 16,
                        color: c.textTertiary,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
  );

  Widget _resultList(
    BuildContext context,
    List<_DesktopInlineSearchSection> sections,
    List<TelegramMiniAppRecent> miniApps,
  ) {
    final c = context.colors;
    if (controller.isLoading && sections.isEmpty && miniApps.isEmpty) {
      return const Center(child: CupertinoActivityIndicator());
    }
    if (sections.isEmpty && miniApps.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
          child: Text(
            AppStringKeys.chatsSearchNoResults.l10n(context),
            style: TextStyle(fontSize: 13, color: c.textTertiary),
          ),
        ),
      );
    }
    return ListView(
      key: const ValueKey('desktop-inline-search-results'),
      padding: const EdgeInsets.symmetric(vertical: 6),
      shrinkWrap: true,
      children: _sectionWidgets(context, sections, miniApps, c),
    );
  }

  List<Widget> _sectionWidgets(
    BuildContext context,
    List<_DesktopInlineSearchSection> sections,
    List<TelegramMiniAppRecent> miniApps,
    AppColors c,
  ) {
    final widgets = <Widget>[];

    void addDivider() {
      if (widgets.isNotEmpty) {
        widgets.add(
          Container(
            height: 0.5,
            margin: const EdgeInsets.symmetric(horizontal: 12),
            color: c.divider,
          ),
        );
      }
    }

    final highlight = controller.query.trim();

    void addSearchSection(_DesktopInlineSearchSection section) {
      addDivider();
      widgets.add(
        _DesktopInlineSearchSectionHeader(
          tab: section.tab,
          onOpenCategory: () => _openCategory(section.tab),
        ),
      );
      for (var index = 0; index < section.hits.length; index++) {
        final hit = section.hits[index];
        if (index > 0) {
          widgets.add(
            Container(
              height: 0.5,
              margin: const EdgeInsets.only(left: 62),
              color: c.divider,
            ),
          );
        }
        widgets.add(
          _DesktopInlineSearchHitAction(
            hit: hit,
            highlight: highlight,
            onOpen: () {
              controller.dismiss();
              unawaited(_openSearchHit(context, hit));
            },
          ),
        );
      }
    }

    for (final section in sections.where(
      (section) => section.tab == SearchTab.chats,
    )) {
      addSearchSection(section);
    }
    if (miniApps.isNotEmpty) {
      addDivider();
      widgets.add(
        _DesktopInlineSearchSectionHeader(
          tab: SearchTab.miniApps,
          onOpenCategory: () => _openCategory(SearchTab.miniApps),
        ),
      );
      for (var index = 0; index < miniApps.length; index++) {
        if (index > 0) {
          widgets.add(
            Container(
              height: 0.5,
              margin: const EdgeInsets.only(left: 62),
              color: c.divider,
            ),
          );
        }
        final app = miniApps[index];
        widgets.add(
          _DesktopInlineMiniAppAction(
            app: app,
            onOpen: () {
              controller.dismiss();
              final override = onOpenMiniApp;
              if (override != null) {
                unawaited(Future<void>.sync(() => override(app)));
              } else {
                unawaited(_openDesktopInlineMiniApp(context, app));
              }
            },
          ),
        );
      }
    }
    for (final section in sections.where(
      (section) => section.tab != SearchTab.chats,
    )) {
      addSearchSection(section);
    }
    return widgets;
  }
}

Future<void> _openDesktopInlineMiniApp(
  BuildContext context,
  TelegramMiniAppRecent app,
) async {
  final opened = await openTelegramMiniApp(
    context,
    chatId: app.chatId,
    botUserId: app.botUserId,
    url: app.url,
    title: app.launchTitle,
    keyboardButtonText: app.keyboardButtonText,
    mainWebApp: app.mainWebApp,
    startParameter: app.startParameter,
    webAppShortName: app.webAppShortName,
    allowWriteAccess: app.allowWriteAccess,
    photo: app.photo,
  );
  if (!opened && context.mounted) {
    showToast(context, AppStrings.t(AppStringKeys.miniAppCannotStart));
  }
}

class _DesktopInlineSearchSectionHeader extends StatelessWidget {
  const _DesktopInlineSearchSectionHeader({
    required this.tab,
    this.onOpenCategory,
  });

  final SearchTab tab;

  /// Opens the full search scoped to this category (the trailing chevron).
  final VoidCallback? onOpenCategory;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final header = Container(
      key: ValueKey('desktop-inline-search-section-${tab.name}'),
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              tab.label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: c.textSecondary,
              ),
            ),
          ),
          if (onOpenCategory != null)
            AppIcon(HeroAppIcons.chevronRight, size: 12, color: c.textTertiary),
        ],
      ),
    );
    if (onOpenCategory == null) return header;
    return AppInteractiveSurface(
      key: ValueKey('desktop-inline-search-section-open-${tab.name}'),
      semanticLabel: tab.label,
      onTap: onOpenCategory,
      child: header,
    );
  }
}

class _DesktopInlineSearchHitAction extends StatelessWidget {
  const _DesktopInlineSearchHitAction({
    required this.hit,
    required this.onOpen,
    this.highlight = '',
  });

  final _SearchHit hit;
  final VoidCallback onOpen;
  final String highlight;

  @override
  Widget build(BuildContext context) => AppInteractiveSurface(
    semanticLabel: hit.title,
    onTap: onOpen,
    child: _DesktopCompactSearchHitRow(hit: hit, highlight: highlight),
  );
}

/// Splits [text] into spans with case-insensitive occurrences of each
/// whitespace-separated term of [query] rendered in the highlight style.
List<InlineSpan> searchHighlightSpans(
  String text,
  String query, {
  required TextStyle base,
  required TextStyle highlight,
}) {
  final terms = query
      .split(RegExp(r'\s+'))
      .where((term) => term.isNotEmpty)
      .map(RegExp.escape)
      .toList();
  if (text.isEmpty || terms.isEmpty) {
    return [TextSpan(text: text, style: base)];
  }
  final pattern = RegExp(terms.join('|'), caseSensitive: false);
  final spans = <InlineSpan>[];
  var cursor = 0;
  for (final match in pattern.allMatches(text)) {
    if (match.start > cursor) {
      spans.add(
        TextSpan(text: text.substring(cursor, match.start), style: base),
      );
    }
    spans.add(
      TextSpan(text: text.substring(match.start, match.end), style: highlight),
    );
    cursor = match.end;
  }
  if (cursor < text.length) {
    spans.add(TextSpan(text: text.substring(cursor), style: base));
  }
  return spans;
}

class _DesktopInlineMiniAppAction extends StatelessWidget {
  const _DesktopInlineMiniAppAction({required this.app, required this.onOpen});

  final TelegramMiniAppRecent app;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) => AppInteractiveSurface(
    key: ValueKey(
      'desktop-inline-search-mini-app-${app.botUserId}-${app.chatId}',
    ),
    semanticLabel: app.displayTitle,
    onTap: onOpen,
    child: SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            PhotoAvatar(title: app.displayTitle, photo: app.photo, size: 40),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    app.displayTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: context.colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    AppStringKeys.miniAppName.l10n(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: context.colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _DesktopCompactSearchHitRow extends StatelessWidget {
  const _DesktopCompactSearchHitRow({required this.hit, this.highlight = ''});

  final _SearchHit hit;
  final String highlight;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final titleStyle = TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: c.textPrimary,
    );
    final subtitleStyle = TextStyle(fontSize: 12, color: c.textSecondary);
    return SizedBox(
      height: 56,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            _DesktopCompactSearchThumb(hit: hit),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      children: searchHighlightSpans(
                        hit.title,
                        highlight,
                        base: titleStyle,
                        highlight: titleStyle.copyWith(color: AppTheme.brand),
                      ),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (hit.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text.rich(
                      TextSpan(
                        children: searchHighlightSpans(
                          hit.subtitle,
                          highlight,
                          base: subtitleStyle,
                          highlight: subtitleStyle.copyWith(
                            color: AppTheme.brand,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopCompactSearchThumb extends StatelessWidget {
  const _DesktopCompactSearchThumb({required this.hit});

  final _SearchHit hit;

  @override
  Widget build(BuildContext context) {
    final image = hit.thumbnail ?? hit.photo;
    if (hit.chat != null || hit.userId != null && hit.message == null) {
      return PhotoAvatar(title: hit.title, photo: hit.photo, size: 40);
    }
    if (image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 40,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TDImage(photo: image),
              if (hit.message?.video != null)
                Center(
                  child: Container(
                    width: 22,
                    height: 22,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000).withValues(alpha: 0.50),
                      shape: BoxShape.circle,
                    ),
                    child: const AppIcon(
                      HeroAppIcons.play,
                      size: 11,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hit.tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: AppIcon(hit.icon, size: 20, color: hit.tint),
    );
  }
}

class SearchView extends StatefulWidget {
  const SearchView({
    super.key,
    this.initialQuery = '',
    this.initialTab,
    this.showBackButton = true,
  });

  final String initialQuery;

  /// Opens the view pre-scoped to one category (the dropdown's per-section
  /// chevrons land here).
  final SearchTab? initialTab;
  final bool showBackButton;

  @override
  State<SearchView> createState() => _SearchViewState();
}

class _SearchViewState extends State<SearchView> {
  late final TextEditingController _controller;
  final _focus = FocusNode();
  final _vm = _SearchViewModel();
  late SearchTab _tab = widget.initialTab ?? SearchTab.chats;
  late String _query;

  @override
  void initState() {
    super.initState();
    _query = widget.initialQuery.trim();
    _controller = TextEditingController(text: _query);
    _vm.addListener(() => setState(() {}));
    _vm.search(_query, _tab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(milliseconds: 250), () {
        if (mounted) _focus.requestFocus();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    _vm.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return CupertinoPageScaffold(
      backgroundColor: c.groupedBackground,
      child: Column(
        children: [
          _header(),
          Expanded(child: _results()),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.listHeaderTint,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  if (widget.showBackButton)
                    GestureDetector(
                      key: const ValueKey('search-view-back'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: AppIcon(
                          HeroAppIcons.chevronLeft,
                          size: 22,
                          color: c.textPrimary,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Container(
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: c.searchFill,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        children: [
                          AppIcon(
                            HeroAppIcons.magnifyingGlass,
                            size: 15,
                            color: c.textTertiary,
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: CupertinoTextField(
                              controller: _controller,
                              focusNode: _focus,
                              autocorrect: false,
                              textInputAction: TextInputAction.search,
                              style: TextStyle(
                                fontSize: 15,
                                color: c.textPrimary,
                              ),
                              placeholder: AppStrings.t(
                                AppStringKeys.topicChatSearch,
                              ),
                              placeholderStyle: TextStyle(
                                fontSize: 15,
                                color: c.textTertiary,
                              ),
                              padding: EdgeInsets.zero,
                              decoration: null,
                              onChanged: (q) {
                                setState(() => _query = q);
                                _vm.search(q, _tab);
                              },
                            ),
                          ),
                          if (_query.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _controller.clear();
                                setState(() => _query = '');
                                _vm.search('', _tab);
                              },
                              child: AppIcon(
                                HeroAppIcons.xmark,
                                size: 16,
                                color: c.textTertiary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      _focus.unfocus();
                      Navigator.of(context).push(
                        CupertinoPageRoute(
                          builder: (_) =>
                              PublicDiscoveryView(initialQuery: _query),
                        ),
                      );
                    },
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: Center(
                        child: AppIcon(
                          HeroAppIcons.globe,
                          size: 21,
                          color: AppTheme.brand,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          _tabBar(),
        ],
      ),
    );
  }

  Widget _results() {
    final c = context.colors;
    if (_tab == SearchTab.miniApps) {
      return MiniAppsSearchTab(query: _query);
    }
    final hits = _vm.resultsFor(_tab);
    final allowEmptyQuery = _tab != SearchTab.chats;
    if (_query.trim().isEmpty && !allowEmptyQuery) {
      return _empty(AppStrings.t(AppStringKeys.chatsSearchPlaceholder));
    }
    if (_vm.isLoading(_tab) && hits.isEmpty) {
      return Container(
        color: c.groupedBackground,
        alignment: Alignment.center,
        child: const SizedBox(
          width: 22,
          height: 22,
          child: CupertinoActivityIndicator(radius: 11),
        ),
      );
    }
    if (hits.isEmpty) {
      return _empty(AppStrings.t(AppStringKeys.chatsSearchNoResults));
    }
    return Container(
      color: c.background,
      child: ListView.builder(
        padding: EdgeInsets.zero,
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        itemCount: hits.length,
        itemBuilder: (context, i) {
          final hit = hits[i];
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _open(hit),
                child: hit.chat != null
                    ? ChatRowView(chat: hit.chat!)
                    : _hitRow(hit),
              ),
              const InsetDivider(leadingInset: 78),
            ],
          );
        },
      ),
    );
  }

  Future<void> _open(_SearchHit hit) async {
    await _openSearchHit(context, hit);
  }

  Widget _hitRow(_SearchHit hit) {
    final c = context.colors;
    final thumb = _hitThumb(hit);
    return Container(
      height: 66,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      color: c.background,
      child: Row(
        children: [
          thumb,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  hit.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  hit.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: c.textSecondary),
                ),
              ],
            ),
          ),
          if (hit.timeLabel.isNotEmpty) ...[
            const SizedBox(width: 10),
            Text(
              hit.timeLabel,
              style: TextStyle(fontSize: 13, color: c.textTertiary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _hitThumb(_SearchHit hit) {
    final image = hit.thumbnail ?? hit.photo;
    if (hit.chat != null || hit.userId != null && hit.message == null) {
      return PhotoAvatar(title: hit.title, photo: hit.photo, size: 54);
    }
    if (image != null) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(9),
        child: SizedBox(
          width: 54,
          height: 54,
          child: Stack(
            fit: StackFit.expand,
            children: [
              TDImage(photo: image),
              if (hit.message?.video != null)
                Center(
                  child: Container(
                    width: 26,
                    height: 26,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000).withValues(alpha: 0.50),
                      shape: BoxShape.circle,
                    ),
                    child: const AppIcon(
                      HeroAppIcons.play,
                      size: 13,
                      color: Color(0xFFFFFFFF),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
    return Container(
      width: 54,
      height: 54,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hit.tint.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: AppIcon(hit.icon, size: 24, color: hit.tint),
    );
  }

  Widget _empty(String text) {
    final c = context.colors;
    return Container(
      width: double.infinity,
      color: c.groupedBackground,
      alignment: Alignment.center,
      child: Text(text, style: TextStyle(fontSize: 14, color: c.textTertiary)),
    );
  }

  Widget _tabBar() {
    final c = context.colors;
    return Container(
      height: 44,
      color: c.listHeaderTint,
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 18),
        child: Row(
          children: [for (final tab in SearchTab.values) _tabButton(tab)],
        ),
      ),
    );
  }

  Widget _tabButton(SearchTab tab) {
    final c = context.colors;
    final selected = _tab == tab;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_tab == tab) return;
        setState(() => _tab = tab);
        _vm.search(_query, tab);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          height: 44,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 160),
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? AppTheme.brand : c.textSecondary,
                ),
                child: Text(tab.label, maxLines: 1),
              ),
              Positioned(
                bottom: 4,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  width: selected ? 18 : 0,
                  height: 3,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Future<void> _openSearchHit(BuildContext context, _SearchHit hit) async {
  if (hit.message != null && hit.chatId != null) {
    final title = hit.sourceTitle;
    await openChatFromCurrentWindow(
      context,
      chatId: hit.chatId!,
      title: title.isEmpty ? hit.title : title,
      initialMessageId: hit.message!.id,
    );
    return;
  }
  final chat = hit.chat;
  if (chat != null) {
    await openChatFromCurrentWindow(
      context,
      chatId: chat.id,
      title: chat.title,
    );
    return;
  }
  final userId = hit.userId;
  if (userId == null) return;
  try {
    final chat = await TdClient.shared.query({
      '@type': 'createPrivateChat',
      'user_id': userId,
      'force': false,
    });
    final summary = TDParse.chat(chat);
    if (!context.mounted || summary == null) return;
    await openChatFromCurrentWindow(
      context,
      chatId: summary.id,
      title: summary.title,
    );
  } catch (_) {}
}

enum SearchTab {
  chats,
  miniApps,
  posts,
  media,
  links,
  files,
  music,
  voice;

  String get label => switch (this) {
    SearchTab.chats => AppStrings.t(AppStringKeys.searchTabChats),
    SearchTab.miniApps => AppStrings.t(AppStringKeys.searchTabMiniApps),
    SearchTab.posts => AppStrings.t(AppStringKeys.searchTabMessages),
    SearchTab.media => AppStrings.t(AppStringKeys.searchTabMedia),
    SearchTab.links => AppStrings.t(AppStringKeys.searchTabLinks),
    SearchTab.files => AppStrings.t(AppStringKeys.searchTabFiles),
    SearchTab.music => AppStrings.t(AppStringKeys.searchTabMusic),
    SearchTab.voice => AppStrings.t(AppStringKeys.searchTabVoiceMessages),
  };

  String? get filter => switch (this) {
    SearchTab.chats => null,
    SearchTab.miniApps => null,
    SearchTab.posts => 'searchMessagesFilterEmpty',
    SearchTab.media => 'searchMessagesFilterPhotoAndVideo',
    SearchTab.links => 'searchMessagesFilterUrl',
    SearchTab.files => 'searchMessagesFilterDocument',
    SearchTab.music => 'searchMessagesFilterAudio',
    SearchTab.voice => 'searchMessagesFilterVoiceNote',
  };
}

class _SearchViewModel extends ChangeNotifier {
  final Map<SearchTab, List<_SearchHit>> _results = {
    for (final tab in SearchTab.values) tab: <_SearchHit>[],
  };
  final Set<SearchTab> _loading = {};
  final Map<SearchTab, String> _queries = {
    for (final tab in SearchTab.values) tab: '',
  };
  final Map<SearchTab, int> _runIds = {
    for (final tab in SearchTab.values) tab: 0,
  };
  bool _disposed = false;

  List<_SearchHit> resultsFor(SearchTab tab) => _results[tab] ?? const [];
  bool isLoading(SearchTab tab) => _loading.contains(tab);

  void search(String q, SearchTab tab) {
    if (_disposed) return;
    _startSearch(q.trim(), tab, resultLimit: 60);
    notifyListeners();
  }

  void searchMany(
    String q,
    Iterable<SearchTab> tabs, {
    required int resultLimitPerTab,
  }) {
    if (_disposed) return;
    final trimmed = q.trim();
    for (final tab in tabs) {
      _startSearch(trimmed, tab, resultLimit: resultLimitPerTab);
    }
    notifyListeners();
  }

  void clearTabs(Iterable<SearchTab> tabs) {
    if (_disposed) return;
    for (final tab in tabs) {
      _queries[tab] = '';
      _runIds[tab] = (_runIds[tab] ?? 0) + 1;
      _results[tab] = const [];
      _loading.remove(tab);
    }
    notifyListeners();
  }

  void _startSearch(String trimmed, SearchTab tab, {required int resultLimit}) {
    if (_disposed) return;
    final runId = (_runIds[tab] ?? 0) + 1;
    _runIds[tab] = runId;
    _queries[tab] = trimmed;
    if (tab == SearchTab.miniApps) {
      _results[tab] = const [];
      _loading.remove(tab);
      return;
    }
    if (trimmed.isEmpty && tab == SearchTab.chats) {
      _results[tab] = const [];
      _loading.remove(tab);
      return;
    }
    _loading.add(tab);
    if (tab == SearchTab.chats) {
      unawaited(_runChats(trimmed, tab, runId, resultLimit));
    } else {
      unawaited(_runMessages(trimmed, tab, runId, resultLimit));
    }
  }

  Future<void> _runChats(
    String trimmed,
    SearchTab tab,
    int runId,
    int resultLimit,
  ) async {
    try {
      final out = <_SearchHit>[];
      final seenChats = <int>{};
      final seenUsers = <int>{};

      Future<void> addChat(int id, {String? subtitle}) async {
        if (!_isCurrent(tab, runId, trimmed) ||
            out.length >= resultLimit ||
            !seenChats.add(id)) {
          return;
        }
        try {
          final chat = await TdClient.shared.query({
            '@type': 'getChat',
            'chat_id': id,
          });
          final s = TDParse.chat(chat);
          if (s == null) return;
          out.add(_SearchHit.chat(s, subtitle: subtitle));
          final uid = s.peerUserId;
          if (uid != null) seenUsers.add(uid);
        } catch (_) {}
      }

      final local = await TdClient.shared.query({
        '@type': 'searchChats',
        'query': trimmed,
        'type_filter': null,
        'limit': resultLimit,
      });
      for (final id in (local.int64Array('chat_ids') ?? const <int>[]).take(
        resultLimit,
      )) {
        await addChat(id);
      }
      if (!_isCurrent(tab, runId, trimmed)) return;

      try {
        final contacts = await TdClient.shared.query({
          '@type': 'searchContacts',
          'query': trimmed,
          'limit': resultLimit,
        });
        for (final id
            in (contacts.int64Array('user_ids') ?? const <int>[]).take(
              resultLimit,
            )) {
          if (!_isCurrent(tab, runId, trimmed) || out.length >= resultLimit) {
            break;
          }
          if (!seenUsers.add(id)) continue;
          try {
            final user = await TdClient.shared.query({
              '@type': 'getUser',
              'user_id': id,
            });
            out.add(_SearchHit.user(id, user));
          } catch (_) {}
        }
      } catch (_) {}
      if (!_isCurrent(tab, runId, trimmed)) return;

      try {
        final public = await TdClient.shared.query({
          '@type': 'searchPublicChats',
          'query': trimmed,
          'type_filter': null,
        });
        for (final id in (public.int64Array('chat_ids') ?? const <int>[]).take(
          resultLimit,
        )) {
          await addChat(
            id,
            subtitle: AppStrings.t(
              AppStringKeys.chatsSearchPublicGroupsAndChannels,
            ),
          );
        }
      } catch (_) {}
      if (!_isCurrent(tab, runId, trimmed)) return;

      final handle = _usernameOf(trimmed);
      if (handle != null) {
        try {
          final chat = await TdClient.shared.query({
            '@type': 'searchPublicChat',
            'username': handle,
          });
          final id = chat.int64('id');
          if (id != null) await addChat(id, subtitle: '@$handle');
        } catch (_) {}
      }

      _finish(tab, runId, trimmed, out.take(resultLimit).toList());
    } catch (_) {
      _finish(tab, runId, trimmed, const []);
    }
  }

  Future<void> _runMessages(
    String trimmed,
    SearchTab tab,
    int runId,
    int resultLimit,
  ) async {
    final filter = tab.filter;
    if (filter == null) return;
    try {
      final pages = await Future.wait([
        _searchMessagesInList(
          query: trimmed,
          filter: filter,
          chatList: {'@type': 'chatListMain'},
          limit: resultLimit,
        ),
        _searchMessagesInList(
          query: trimmed,
          filter: filter,
          chatList: {'@type': 'chatListArchive'},
          limit: resultLimit,
        ),
      ]);
      if (!_isCurrent(tab, runId, trimmed)) return;
      final raw = <Map<String, dynamic>>[...pages[0], ...pages[1]]
        ..sort(
          (a, b) => (b.integer('date') ?? 0).compareTo(a.integer('date') ?? 0),
        );
      final seen = <String>{};
      final out = <_SearchHit>[];
      for (final object in raw) {
        if (!_isCurrent(tab, runId, trimmed) || out.length >= resultLimit) {
          break;
        }
        final chatId = object.int64('chat_id');
        final message = TDParse.message(object);
        if (chatId == null || message == null) continue;
        final key = '$chatId:${message.id}';
        if (!seen.add(key)) continue;
        final source = await _sourceFor(chatId);
        out.add(_SearchHit.message(message, chatId: chatId, source: source));
      }
      _finish(tab, runId, trimmed, out);
    } catch (_) {
      _finish(tab, runId, trimmed, const []);
    }
  }

  Future<List<Map<String, dynamic>>> _searchMessagesInList({
    required String query,
    required String filter,
    required Map<String, dynamic> chatList,
    required int limit,
  }) async {
    try {
      final res = await TdClient.shared.query({
        '@type': 'searchMessages',
        'chat_list': chatList,
        'query': query,
        'offset': '',
        'limit': limit,
        'filter': {'@type': filter},
        'chat_type_filter': null,
        'min_date': 0,
        'max_date': 0,
      });
      return res.objects('messages') ?? const <Map<String, dynamic>>[];
    } catch (_) {
      return const <Map<String, dynamic>>[];
    }
  }

  Future<_SearchSource> _sourceFor(int chatId) async {
    try {
      final chat = await TdClient.shared.query({
        '@type': 'getChat',
        'chat_id': chatId,
      });
      return _SearchSource(
        title: chat.str('title') ?? '',
        photo: TDParse.smallPhoto(chat.obj('photo')),
      );
    } catch (_) {
      return const _SearchSource(title: '', photo: null);
    }
  }

  void _finish(SearchTab tab, int runId, String query, List<_SearchHit> out) {
    if (!_isCurrent(tab, runId, query)) return;
    _results[tab] = out;
    _loading.remove(tab);
    notifyListeners();
  }

  bool _isCurrent(SearchTab tab, int runId, String query) =>
      !_disposed && _runIds[tab] == runId && _queries[tab] == query;

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final tab in SearchTab.values) {
      _runIds[tab] = (_runIds[tab] ?? 0) + 1;
    }
    _loading.clear();
    super.dispose();
  }

  String? _usernameOf(String q) {
    var s = q.trim();
    final link = RegExp(
      r'(?:https?://)?(?:t\.me|telegram\.me)/(@?[A-Za-z0-9_]+)',
      caseSensitive: false,
    ).firstMatch(s);
    if (link != null) s = link.group(1)!;
    if (s.startsWith('@')) s = s.substring(1);
    return RegExp(r'^[A-Za-z0-9_]{3,32}$').hasMatch(s) ? s : null;
  }
}

class _SearchHit {
  _SearchHit({
    required this.title,
    required this.subtitle,
    this.timeLabel = '',
    this.date = 0,
    this.sourceTitle = '',
    this.thumbnail,
    AppIconData? icon,
    this.tint = const Color(0xFF12B7F5),
    this.photo,
    this.chat,
    this.userId,
    this.chatId,
    this.message,
  }) : icon = icon ?? HeroAppIcons.message;

  factory _SearchHit.chat(ChatSummary chat, {String? subtitle}) => _SearchHit(
    title: chat.title,
    subtitle: subtitle ?? _chatSubtitle(chat),
    photo: chat.photo,
    chat: chat,
    userId: chat.peerUserId,
  );

  factory _SearchHit.user(int id, Map<String, dynamic> user) {
    final username = user.obj('usernames')?.str('editable_username');
    return _SearchHit(
      title: TDParse.userName(user),
      subtitle: username != null && username.isNotEmpty
          ? '@$username'
          : TDParse.userStatus(user),
      photo: TDParse.smallPhoto(user.obj('profile_photo')),
      userId: id,
    );
  }

  factory _SearchHit.message(
    ChatMessage message, {
    required int chatId,
    required _SearchSource source,
  }) {
    final document = message.document;
    final music = message.music;
    final title = document?.fileName ?? music?.title ?? _messageTitle(message);
    final subtitle = _messageSubtitle(message, source.title);
    return _SearchHit(
      title: title,
      subtitle: subtitle,
      timeLabel: DateText.listLabel(message.date),
      date: message.date,
      sourceTitle: source.title,
      photo: source.photo,
      thumbnail: message.image ?? music?.cover,
      chatId: chatId,
      message: message,
      icon: _messageIcon(message),
      tint: _messageTint(message),
    );
  }

  final String title;
  final String subtitle;
  final String timeLabel;
  final int date;
  final String sourceTitle;
  final TdFileRef? photo;
  final TdFileRef? thumbnail;
  final ChatSummary? chat;
  final int? userId;
  final int? chatId;
  final ChatMessage? message;
  final AppIconData icon;
  final Color tint;

  static String _chatSubtitle(ChatSummary chat) {
    if (chat.kind == ChatKind.group) {
      return AppStrings.t(AppStringKeys.linkHandlerGroupLabel);
    }
    if (chat.kind == ChatKind.channel) {
      return AppStrings.t(AppStringKeys.tabChannels);
    }
    if (chat.kind == ChatKind.bot) {
      return AppStrings.t(AppStringKeys.chatsSearchBots);
    }
    return chat.lastMessage.isEmpty
        ? AppStrings.t(AppStringKeys.audioSearchChatTab)
        : chat.lastMessage;
  }

  static String _messageTitle(ChatMessage message) {
    if (message.music != null) return message.music!.title;
    if (message.voice != null) {
      return telegramText(AppStringKeys.sharedMediaVoiceMessages);
    }
    if (message.video != null) {
      final text = message.text.trim();
      return text.isEmpty ||
              text == telegramText(AppStringKeys.chatVideoPlaceholder)
          ? telegramText(AppStringKeys.chatVideoPlaceholder)
          : text;
    }
    if (message.image != null) {
      final text = message.text.trim();
      return text.isEmpty ||
              text == telegramText(AppStringKeys.composerImagePreview)
          ? telegramText(AppStringKeys.composerImagePreview)
          : text;
    }
    return message.text.trim().isEmpty
        ? telegramText(AppStringKeys.chatSearchMessageResultLabel)
        : message.text.trim();
  }

  static String _messageSubtitle(ChatMessage message, String sourceTitle) {
    final pieces = <String>[];
    final document = message.document;
    if (document != null && document.size > 0) {
      pieces.add(_fileSize(document.size));
    }
    final music = message.music;
    if (music?.performer?.isNotEmpty == true) pieces.add(music!.performer!);
    if (message.voice != null && message.voice!.duration > 0) {
      pieces.add(_duration(message.voice!.duration));
    }
    if (sourceTitle.isNotEmpty) pieces.add(sourceTitle);
    final text = message.text.trim();
    if (text.isNotEmpty &&
        document == null &&
        music == null &&
        message.voice == null &&
        text != telegramText(AppStringKeys.composerImagePreview) &&
        text != telegramText(AppStringKeys.chatVideoPlaceholder)) {
      pieces.add(text.replaceAll('\n', ' '));
    }
    return pieces.join(' · ');
  }

  static AppIconData _messageIcon(ChatMessage message) {
    if (message.document != null) return HeroAppIcons.solidFile;
    if (message.music != null) return HeroAppIcons.music;
    if (message.voice != null) return HeroAppIcons.microphone;
    if (message.linkPreview != null) return HeroAppIcons.link;
    if (message.video != null) return HeroAppIcons.video;
    if (message.image != null) return HeroAppIcons.solidImage;
    return HeroAppIcons.message;
  }

  static Color _messageTint(ChatMessage message) {
    if (message.document != null) return const Color(0xFF4AA3F0);
    if (message.music != null) return const Color(0xFFFF8A2A);
    if (message.voice != null) return const Color(0xFF28A878);
    if (message.linkPreview != null) return const Color(0xFF8E7BFF);
    if (message.video != null) return const Color(0xFF7B61FF);
    if (message.image != null) return const Color(0xFF15A7F7);
    return AppTheme.brand;
  }

  static String _fileSize(int bytes) {
    if (bytes >= 1 << 20) return '${(bytes / (1 << 20)).toStringAsFixed(1)} MB';
    if (bytes >= 1 << 10) return '${(bytes / (1 << 10)).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  static String _duration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }
}

class _SearchSource {
  const _SearchSource({required this.title, required this.photo});
  final String title;
  final TdFileRef? photo;
}
