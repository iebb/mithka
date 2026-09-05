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

import '../app/active_conversation.dart';
import '../app/app_navigator.dart';
import '../app/ipad_window_chrome.dart';
import '../app/primary_chat_launcher.dart';
import '../chat/chat_search_query.dart';
import '../chat/chat_search_view.dart';
import '../chat/telegram_link.dart';
import '../chat/telegram_mini_app_recents.dart';
import '../chat/telegram_mini_app_view.dart';
import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'chat_row_view.dart';
import 'mini_apps_page.dart';
import 'public_discovery_view.dart';
import 'search_token_suggestions.dart';
import 'search_token_views.dart';

/// Shared state for the compact desktop title-bar search field and its
/// anchored result panel.
typedef DesktopMiniAppSearch =
    Future<List<TelegramMiniAppRecent>> Function(String query);
typedef DesktopTelegramLinkOpener =
    FutureOr<void> Function(BuildContext context, String link);

// Search is information-dense, especially in the desktop result popover. Keep
// its emphasis at medium so the UI retains hierarchy without rendering every
// match like a bold heading.
const FontWeight _searchEmphasisWeight = AppTextWeight.medium;

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
  Timer? _suggestDebounce;
  String _query = '';
  bool _panelVisible = false;
  bool _debouncing = false;
  bool _miniAppsLoading = false;
  bool _disposed = false;
  int _miniAppRunId = 0;
  List<TelegramMiniAppRecent> _miniApps = const [];
  ActiveConversationScope? _scope;
  final ChatSearchTokenSuggester _suggester = ChatSearchTokenSuggester();
  ChatSearchTokens _tokens = const ChatSearchTokens(text: '');
  ChatSearchActiveToken? _activeToken;
  List<ChatSearchTokenSuggestion> _suggestions = const [];
  int _suggestRunId = 0;
  ChatSearchTokenSuggestion? _resolvedSender;
  ChatSearchTokenSuggestion? _resolvedChat;

  /// Picked from the suggestion list rather than typed — these outlive the
  /// text, because their token has been taken out of it.
  ChatSearchTokenSuggestion? _committedChat;
  ChatSearchTokenSuggestion? _committedSender;
  bool _scopeFromToken = false;

  String get query => _query;

  /// The `in: <chat>` filter, set when search is opened from a conversation
  /// or by typing the token. While it is on, only that chat is searched.
  ActiveConversationScope? get scope => _scope;

  /// The token the caret is in, if it is one that offers suggestions.
  ChatSearchActiveToken? get activeToken => _activeToken;
  List<ChatSearchTokenSuggestion> get suggestions => _suggestions;

  /// The person explicitly picked for a `from:` filter, shown as a badge.
  ///
  /// A typed token may still resolve internally so it can filter results, but
  /// it remains editable text until the user chooses a suggestion.
  ChatSearchTokenSuggestion? get resolvedSender => _committedSender;

  /// Whether the field is asking to be taught its syntax: focused, empty, and
  /// carrying no filters yet.
  bool get showsTokenHints =>
      focusNode.hasFocus &&
      _query.trim().isEmpty &&
      _scope == null &&
      resolvedSender == null;
  bool get panelVisible => showsTokenHints || (_panelVisible && _hasSearch);
  bool get isLoading =>
      _debouncing || _miniAppsLoading || _activeTabs.any(_model.isLoading);

  /// A chat-scoped search has no chat or Mini App hits to offer.
  List<SearchTab> get _activeTabs => _scope == null
      ? _searchTabs
      : _searchTabs.where((tab) => tab != SearchTab.chats).toList();

  List<TelegramMiniAppRecent> get _visibleMiniApps =>
      _scope == null ? _miniApps : const [];
  List<_DesktopInlineSearchSection> get _visibleSections {
    final sections = <_DesktopInlineSearchSection>[
      for (final tab in _activeTabs)
        if (_model.resultsFor(tab).isNotEmpty)
          _DesktopInlineSearchSection(
            tab: tab,
            hits: _model
                .resultsFor(tab)
                .take(
                  tab == SearchTab.chats
                      ? _chatResultLimit
                      : _messageResultLimit,
                )
                .toList(growable: false),
          ),
    ];
    final link = normalizeTelegramLink(_query);
    if (link == null) return sections;

    // A pasted Telegram link is an action, not just a text-search query. Put
    // its opener ahead of any chat result (including a freshly discovered
    // chat that has no message history yet), and do not spend one of the chat
    // result slots on it.
    final linkHit = _SearchHit.telegramLink(
      displayValue: _query.trim(),
      link: link,
    );
    final chatIndex = sections.indexWhere(
      (section) => section.tab == SearchTab.chats,
    );
    if (chatIndex < 0) {
      return [
        _DesktopInlineSearchSection(tab: SearchTab.chats, hits: [linkHit]),
        ...sections,
      ];
    }
    final chatSection = sections[chatIndex];
    sections[chatIndex] = _DesktopInlineSearchSection(
      tab: chatSection.tab,
      hits: [linkHit, ...chatSection.hits],
    );
    return sections;
  }

  /// Focuses the field, optionally scoping the search to a conversation.
  ///
  /// Passing null leaves an existing scope alone so re-focusing the field does
  /// not silently widen a search the user already narrowed.
  void focus({ActiveConversationScope? scope}) {
    if (_disposed) return;
    focusNode.requestFocus();
    final scopeChanged = scope != null && scope != _scope;
    if (scopeChanged) _applyScope(scope);
    final shouldShow = _hasSearch;
    if (_panelVisible == shouldShow && !scopeChanged) return;
    _panelVisible = shouldShow;
    notifyListeners();
  }

  void clearScope() {
    if (_disposed || _scope == null) return;
    _applyScope(null);
    focusNode.requestFocus();
    notifyListeners();
  }

  /// Re-runs the current query against the new scope. Results from the old one
  /// describe a different corpus, so they are dropped rather than filtered.
  void _applyScope(ActiveConversationScope? scope) {
    _scope = scope;
    _scopeFromToken = false;
    _model.scopeChatId = scope?.chatId;
    _debounce?.cancel();
    _model.clearTabs(_searchTabs);
    _invalidateMiniApps();
    _debouncing = _hasSearch;
    if (!_hasSearch) return;
    _debounce = Timer(const Duration(milliseconds: 240), () {
      if (_disposed) return;
      unawaited(_runSearch());
    });
  }

  void updateQuery(String value) {
    if (_disposed) return;
    _query = value;
    _tokens = parseChatSearchQuery(value);
    final caret = textController.selection.baseOffset;
    _activeToken = activeChatSearchToken(
      value,
      caret < 0 ? value.length : caret,
    );
    // A resolved token that no longer matches what is typed is stale. A
    // committed one has no text to match — it lives in its badge.
    if (_resolvedChat?.title != _tokens.inQuery) _resolvedChat = null;
    if (_resolvedSender?.token != _tokens.fromQuery) _resolvedSender = null;
    _panelVisible = _hasSearch || showsTokenHints;
    _debounce?.cancel();
    // Invalidate every in-flight category as soon as the text changes. The
    // next network fan-out remains debounced, but an older query can never
    // repopulate the panel during that debounce window.
    _model.clearTabs(_searchTabs);
    _invalidateMiniApps();
    _startSuggestions();
    _debouncing = _hasSearch;
    if (_hasSearch) {
      _debounce = Timer(const Duration(milliseconds: 240), () {
        if (_disposed) return;
        unawaited(_runSearch());
      });
    }
    notifyListeners();
  }

  /// Whether the field asks for anything — words, or a token on its own.
  bool get _hasSearch =>
      _tokens.text.trim().isNotEmpty ||
      _tokens.inQuery != null ||
      _tokens.fromQuery != null ||
      _committedChat != null ||
      _committedSender != null;

  Future<void> _runSearch() async {
    final query = _tokens.text.trim();
    await _resolveTokens();
    if (_disposed) return;
    _debouncing = false;
    _model.searchMany(query, _activeTabs, resultLimitPerTab: 6);
    if (_scope == null && _model.senderUserId == null && query.isNotEmpty) {
      _startMiniAppSearch(query);
    }
    notifyListeners();
  }

  /// Turns typed tokens into the parameters the search runs with.
  ///
  /// `in:` wins over a scope inherited from an open chat, since typing it is
  /// the more deliberate act.
  Future<void> _resolveTokens() async {
    final committedChat = _committedChat;
    if (committedChat != null) {
      _scope = ActiveConversationScope(
        chatId: committedChat.id,
        title: committedChat.title,
      );
      _model.scopeChatId = committedChat.id;
    }
    final committedSender = _committedSender;
    if (committedSender != null) _model.senderUserId = committedSender.id;

    final inQuery = _tokens.inQuery;
    if (inQuery != null && _resolvedChat == null) {
      final matches = await _suggester.suggest(
        ChatSearchActiveToken(
          kind: ChatSearchTokenKind.chat,
          value: inQuery,
          start: 0,
          end: 0,
        ),
      );
      if (_disposed) return;
      _resolvedChat = matches.firstOrNull;
    }
    final resolvedChat = _resolvedChat;
    if (inQuery != null && resolvedChat != null) {
      _scope = ActiveConversationScope(
        chatId: resolvedChat.id,
        title: resolvedChat.title,
      );
    } else if (inQuery == null && _scopeFromToken && committedChat == null) {
      _scope = null;
      _scopeFromToken = false;
    }
    if (inQuery != null) _scopeFromToken = true;
    _model.scopeChatId = _scope?.chatId;

    final fromQuery = _tokens.fromQuery;
    if (fromQuery != null && _resolvedSender == null) {
      final matches = await _suggester.suggest(
        ChatSearchActiveToken(
          kind: ChatSearchTokenKind.from,
          value: fromQuery,
          start: 0,
          end: 0,
        ),
        scopeChatId: _scope?.chatId,
      );
      if (_disposed) return;
      _resolvedSender = matches.firstOrNull;
    }
    if (committedSender == null) {
      _model.senderUserId = fromQuery == null ? null : _resolvedSender?.id;
    }
  }

  void _startSuggestions() {
    _suggestDebounce?.cancel();
    final token = _activeToken;
    final runId = ++_suggestRunId;
    if (token == null) {
      _suggestions = const [];
      return;
    }
    // Every keystroke inside an `in:`/`from:` token fans out into a search plus
    // one round trip per candidate id, so coalesce it the way _runSearch is.
    // An empty token is the affordance shown the moment `in:` is typed, and it
    // has nothing to coalesce, so it stays immediate.
    if (token.value.isEmpty) {
      _fetchSuggestions(token, runId);
      return;
    }
    _suggestDebounce = Timer(const Duration(milliseconds: 240), () {
      if (_disposed || runId != _suggestRunId) return;
      _fetchSuggestions(token, runId);
    });
  }

  void _fetchSuggestions(ChatSearchActiveToken token, int runId) {
    unawaited(() async {
      final results = await _suggester.suggest(
        token,
        scopeChatId: _scope?.chatId,
      );
      if (_disposed || runId != _suggestRunId) return;
      _suggestions = results;
      notifyListeners();
    }());
  }

  /// Commits a picked suggestion to a badge and takes its text out of the
  /// field, so the filter is stated once rather than twice.
  void applySuggestion(ChatSearchTokenSuggestion suggestion) {
    final token = _activeToken;
    if (_disposed || token == null) return;
    if (token.kind == ChatSearchTokenKind.chat) {
      _committedChat = suggestion;
      _scope = ActiveConversationScope(
        chatId: suggestion.id,
        title: suggestion.title,
      );
      _scopeFromToken = true;
    } else {
      _committedSender = suggestion;
    }
    final applied = removeChatSearchToken(_query, token);
    textController.value = TextEditingValue(
      text: applied.text,
      selection: TextSelection.collapsed(offset: applied.caret),
    );
    focusNode.requestFocus();
    updateQuery(applied.text);
  }

  /// Starts a token in the field from the hint list.
  void startToken(String token) {
    if (_disposed) return;
    final text = _query.isEmpty || _query.endsWith(' ')
        ? '$_query$token'
        : '$_query $token';
    textController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    focusNode.requestFocus();
    updateQuery(text);
  }

  /// Drops the committed `from:` badge.
  void clearSender() {
    if (_disposed || _committedSender == null) return;
    _committedSender = null;
    _resolvedSender = null;
    _model.senderUserId = null;
    focusNode.requestFocus();
    _restartSearch();
  }

  void _restartSearch() {
    _debounce?.cancel();
    _model.clearTabs(_searchTabs);
    _invalidateMiniApps();
    _debouncing = _hasSearch;
    if (_hasSearch) {
      _debounce = Timer(
        const Duration(milliseconds: 240),
        () => _disposed ? null : unawaited(_runSearch()),
      );
    }
    notifyListeners();
  }

  void clear() {
    if (_disposed) return;
    _debounce?.cancel();
    textController.clear();
    _query = '';
    _tokens = const ChatSearchTokens(text: '');
    _activeToken = null;
    _suggestions = const [];
    _suggestRunId++;
    _resolvedChat = null;
    _resolvedSender = null;
    _committedChat = null;
    _committedSender = null;
    _model.senderUserId = null;
    _panelVisible = false;
    _debouncing = false;
    _model.clearTabs(_searchTabs);
    _invalidateMiniApps();
    focusNode.requestFocus();
    notifyListeners();
  }

  void dismiss() {
    if (_disposed) return;
    if (!_panelVisible && !focusNode.hasFocus && _scope == null) return;
    _panelVisible = false;
    // The scope belongs to one search session. Keeping it would silently
    // narrow the next search, long after the chat that set it is gone.
    _scope = null;
    _scopeFromToken = false;
    _activeToken = null;
    _suggestions = const [];
    _suggestRunId++;
    _resolvedChat = null;
    _resolvedSender = null;
    _committedChat = null;
    _committedSender = null;
    _model.scopeChatId = null;
    _model.senderUserId = null;
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
    _suggestDebounce?.cancel();
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

  /// A scoped field carries an `in: <chat>` chip, so it grows to keep a usable
  /// amount of room for the query itself.
  static const double scopedWidth = 348;
  static const double height = 28;

  static double widthFor(DesktopInlineSearchController controller) {
    final chips =
        (controller.scope == null ? 0 : 1) +
        (controller.resolvedSender == null ? 0 : 1);
    return chips == 0 ? width : width + chips * (scopedWidth - width);
  }

  final DesktopInlineSearchController controller;
  final FutureOr<void> Function(String query) onSearchAll;

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      final c = context.colors;
      final scope = controller.scope;
      return Focus(
        onKeyEvent: (_, event) {
          if (event is! KeyDownEvent) return KeyEventResult.ignored;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            controller.dismiss();
            return KeyEventResult.handled;
          }
          // Backspace at the start of an empty query removes the chip, the way
          // every other token field behaves.
          if (event.logicalKey == LogicalKeyboardKey.backspace &&
              controller.scope != null &&
              controller.textController.text.isEmpty) {
            controller.clearScope();
            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        // The width changes in the same frame the chip appears. Animating it
        // would leave the chip overflowing a still-narrow field for the length
        // of the transition.
        child: Container(
          key: const ValueKey('desktop-title-bar-search'),
          width: widthFor(controller),
          height: height,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: c.searchFill,
            borderRadius: BorderRadius.circular(AppRadius.md),
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
              if (scope != null) ...[
                Flexible(
                  child: _DesktopInlineSearchTokenChip(
                    key: const ValueKey('desktop-title-bar-search-scope'),
                    labelKey: AppStringKeys.desktopSearchScopeIn,
                    value: scope.title,
                    onRemove: controller.clearScope,
                    removeKey: const ValueKey(
                      'desktop-title-bar-search-scope-remove',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              if (controller.resolvedSender case final sender?) ...[
                Flexible(
                  child: _DesktopInlineSearchTokenChip(
                    key: const ValueKey('desktop-title-bar-search-from'),
                    labelKey: AppStringKeys.chatSearchTokenFrom,
                    value: sender.title,
                    onRemove: controller.clearSender,
                    removeKey: const ValueKey(
                      'desktop-title-bar-search-from-remove',
                    ),
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: CupertinoTextField(
                  key: const ValueKey('desktop-title-bar-search-input'),
                  controller: controller.textController,
                  focusNode: controller.focusNode,
                  autocorrect: false,
                  textInputAction: TextInputAction.search,
                  style: TextStyle(fontSize: 13, color: c.textPrimary),
                  placeholder: AppStrings.t(
                    scope == null
                        ? AppStringKeys.chatsSearchPlaceholder
                        : AppStringKeys.desktopSearchScopePlaceholder,
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
                  borderRadius: BorderRadius.circular(AppRadius.control),
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

/// A committed token inside the search field.
///
/// It reads as one filter rather than typed text: the whole chip is tinted,
/// and its own control removes it without disturbing the query beside it.
class _DesktopInlineSearchTokenChip extends StatelessWidget {
  const _DesktopInlineSearchTokenChip({
    super.key,
    required this.labelKey,
    required this.value,
    required this.onRemove,
    this.removeKey,
  });

  static const double maxValueWidth = 132;

  final String labelKey;
  final String value;
  final VoidCallback onRemove;
  final Key? removeKey;

  @override
  Widget build(BuildContext context) {
    final labelStyle = TextStyle(
      fontSize: 12,
      fontWeight: _searchEmphasisWeight,
      color: AppTheme.brand,
    );
    return Container(
      height: 20,
      padding: const EdgeInsets.only(left: 6, right: 2),
      decoration: BoxDecoration(
        color: AppTheme.brand.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            labelKey.l10n(context),
            style: labelStyle.copyWith(
              color: AppTheme.brand.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(width: 3),
          // Flexible as well as bounded: a name gets at most [maxValueWidth],
          // and still gives way if the field itself is squeezed narrower.
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxValueWidth),
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: labelStyle,
              ),
            ),
          ),
          AppInteractiveSurface(
            key: removeKey,
            semanticLabel: AppStringKeys.desktopSearchScopeRemove.l10n(context),
            onTap: onRemove,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox.square(
              dimension: 16,
              child: Center(
                child: AppIcon(
                  HeroAppIcons.xmark,
                  size: 10,
                  color: AppTheme.brand,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
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
    this.onOpenTelegramLink,
  });

  static const double width = 440;
  static const double maxResultsHeight = 464;

  final DesktopInlineSearchController controller;
  final FutureOr<void> Function(String query) onSearchAll;

  /// Section-header chevron: run the full search scoped to that category.
  /// Falls back to [onSearchAll] when null.
  final FutureOr<void> Function(String query, SearchTab tab)? onSearchCategory;
  final FutureOr<void> Function(TelegramMiniAppRecent app)? onOpenMiniApp;
  final DesktopTelegramLinkOpener? onOpenTelegramLink;

  void _openCategory(BuildContext context, SearchTab tab) {
    final query = controller.query.trim();
    if (query.isEmpty) return;
    // Scoped results are all one chat's messages; a per-category full search
    // has nothing narrower to offer than that chat's own history.
    if (controller.scope != null) {
      _openFooterSearch(context);
      return;
    }
    controller.dismiss();
    final scoped = onSearchCategory;
    if (scoped != null) {
      unawaited(Future<void>.sync(() => scoped(query, tab)));
    } else {
      unawaited(Future<void>.sync(() => onSearchAll(query)));
    }
  }

  String _footerLabel(BuildContext context) => controller.scope == null
      ? AppStringKeys.desktopSearchAll.l10n(context)
      : AppStringKeys.desktopSearchScopePlaceholder.l10n(context);

  /// The footer honours the `in:` chip: a scoped query opens that chat's own
  /// full history search instead of quietly widening back to every chat.
  void _openFooterSearch(BuildContext context) {
    final query = controller.query.trim();
    if (query.isEmpty) return;
    final scope = controller.scope;
    final host = desktopInlineSearchHostContext(context);
    controller.dismiss();
    if (scope == null) {
      unawaited(Future<void>.sync(() => onSearchAll(query)));
      return;
    }
    if (host == null) return;
    unawaited(_openScopedChatSearch(host, scope, query));
  }

  /// The panel's chrome, shared by the results list and the token suggestions
  /// so a token being typed does not change the shape under the field.
  Widget _panelShell(BuildContext context, {required Widget child}) {
    final c = context.colors;
    return Container(
      key: const ValueKey('desktop-inline-search-panel'),
      width: width,
      constraints: const BoxConstraints(maxHeight: 540),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(AppRadius.card),
        border: Border.all(color: c.divider, width: 0.75),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF000000).withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: controller,
    builder: (context, _) {
      if (!controller.panelVisible) return const SizedBox.shrink();
      final c = context.colors;
      final sections = controller._visibleSections;
      final miniApps = controller._visibleMiniApps;
      // A token being typed is a question about who or where, so the panel
      // answers that one instead of showing results for a half-written filter.
      final token = controller.activeToken;
      if (token != null) {
        return _panelShell(
          context,
          child: SearchTokenSuggestionList(
            suggestions: controller.suggestions,
            onPick: controller.applySuggestion,
          ),
        );
      }
      if (controller.showsTokenHints) {
        return _panelShell(
          context,
          child: SearchTokenHints(
            hints: const [
              searchTokenFromHint,
              searchTokenInHint,
              searchTokenHasHint,
            ],
            onPick: controller.startToken,
          ),
        );
      }
      return _panelShell(
        context,
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
              semanticLabel: _footerLabel(context),
              onTap: () => _openFooterSearch(context),
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
                          '${_footerLabel(context)}  ${controller.query.trim()}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: _searchEmphasisWeight,
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
          onOpenCategory: () => _openCategory(context, section.tab),
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
              // dismiss() unmounts this row, and opening a chat awaits the
              // desktop handoff before using its context — an unmounted one
              // makes it bail, so the tap did nothing.
              final host = desktopInlineSearchHostContext(context);
              controller.dismiss();
              if (host == null) return;
              unawaited(
                _openSearchHit(
                  host,
                  hit,
                  onOpenTelegramLink: onOpenTelegramLink,
                ),
              );
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
          onOpenCategory: () => _openCategory(context, SearchTab.miniApps),
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
              // Same as the chat rows: this one is unmounted by dismiss().
              final host = desktopInlineSearchHostContext(context);
              controller.dismiss();
              final override = onOpenMiniApp;
              if (override != null) {
                unawaited(Future<void>.sync(() => override(app)));
                return;
              }
              if (host == null) return;
              unawaited(_openDesktopInlineMiniApp(host, app));
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

/// The context the inline panel routes through.
///
/// The panel is mounted by `MaterialApp.builder`, which puts it *above* the
/// app Navigator — so `Navigator.of` on the panel's own context finds nothing
/// and throws before a row can open anything. The app navigator's overlay
/// context can push and outlives the row that
/// [DesktopInlineSearchController.dismiss] unmounts.
BuildContext? desktopInlineSearchHostContext(BuildContext context) {
  final navigator = appNavigatorKey.currentState ?? Navigator.maybeOf(context);
  return navigator?.overlay?.context ?? navigator?.context;
}

/// Opens one chat's full history search, then jumps to whatever hit was picked.
Future<void> _openScopedChatSearch(
  BuildContext context,
  ActiveConversationScope scope,
  String query,
) async {
  final navigator = Navigator.maybeOf(context);
  if (navigator == null) return;
  final messageId = await navigator.push<int>(
    AppPageRoute<int>(
      pageBuilder: (_, _, _) => ChatSearchView(
        chatId: scope.chatId,
        title: scope.title,
        initialQuery: query,
      ),
    ),
  );
  if (messageId == null || !context.mounted) return;
  await openChatFromCurrentWindow(
    context,
    chatId: scope.chatId,
    title: scope.title,
    initialMessageId: messageId,
  );
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
  if (opened || !context.mounted) return;
  // The host context is the navigator's own overlay, which `Overlay.of` cannot
  // find by walking ancestors — resolve that overlay directly so the failure
  // is still reported instead of silently dropped.
  final overlay =
      Overlay.maybeOf(context, rootOverlay: true) ??
      appNavigatorKey.currentState?.overlay;
  if (overlay == null) return;
  showToastOverlay(overlay, AppStrings.t(AppStringKeys.miniAppCannotStart));
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
                fontWeight: _searchEmphasisWeight,
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
    key: hit.telegramLink == null
        ? null
        : const ValueKey('desktop-inline-search-deeplink'),
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
                      fontWeight: _searchEmphasisWeight,
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
      fontWeight: _searchEmphasisWeight,
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
                            fontWeight: _searchEmphasisWeight,
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
        borderRadius: BorderRadius.circular(AppRadius.control),
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
        borderRadius: BorderRadius.circular(AppRadius.control),
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
  Timer? _searchDebounce;

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
    _searchDebounce?.cancel();
    _controller.dispose();
    _focus.dispose();
    _vm.dispose();
    super.dispose();
  }

  /// A keystroke fans out into searchChats + searchContacts + searchPublicChats
  /// and up to 60 per-result round trips each, so coalesce a burst of typing
  /// the way the desktop controller already does.
  void _scheduleSearch(String q) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 240), () {
      if (mounted) _vm.search(q, _tab);
    });
  }

  void _searchNow(String q, SearchTab tab) {
    _searchDebounce?.cancel();
    _vm.search(q, tab);
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
      padding: EdgeInsets.only(
        top:
            MediaQuery.of(context).padding.top +
            iPadWindowChromeInsetOf(context),
      ),
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
                                _scheduleSearch(q);
                              },
                            ),
                          ),
                          if (_query.isNotEmpty)
                            GestureDetector(
                              onTap: () {
                                _controller.clear();
                                setState(() => _query = '');
                                _searchNow('', _tab);
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
                    fontWeight: _searchEmphasisWeight,
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
        borderRadius: BorderRadius.circular(AppRadius.control),
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
        borderRadius: BorderRadius.circular(AppRadius.control),
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
        _searchNow(_query, tab);
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
                  fontWeight: selected
                      ? _searchEmphasisWeight
                      : AppTextWeight.regular,
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

Future<void> _openSearchHit(
  BuildContext context,
  _SearchHit hit, {
  DesktopTelegramLinkOpener? onOpenTelegramLink,
}) async {
  final telegramLink = hit.telegramLink;
  if (telegramLink != null) {
    final opener = onOpenTelegramLink;
    if (opener != null) await opener(context, telegramLink);
    return;
  }
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
  /// When set, message categories query this chat's history instead of every
  /// chat list — the `in: <chat>` scope of the desktop inline search.
  int? scopeChatId;

  /// When set, only this user's messages count — the `from:` token.
  ///
  /// TDLib can filter by sender per chat but not across a chat list, so an
  /// unscoped sender search runs over the chats that user and the account
  /// actually share. That is a bounded set and each request is still filtered
  /// by the server, so counts stay honest.
  int? senderUserId;

  final Map<int, List<int>> _commonChatCache = {};

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

  Future<ChatSummary?> _fetchChat(int id) async {
    try {
      return TDParse.chat(
        await TdClient.shared.query({'@type': 'getChat', 'chat_id': id}),
      );
    } catch (_) {
      return null;
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
      if (!_isCurrent(tab, runId, trimmed)) return;
      // The local ids always fit inside resultLimit, so every one of them would
      // be fetched anyway — do it concurrently instead of paying up to 60
      // sequential round trips before the first result can paint. Future.wait
      // keeps index order, so the hit order is unchanged.
      final localIds = <int>[
        for (final id in (local.int64Array('chat_ids') ?? const <int>[]).take(
          resultLimit,
        ))
          if (seenChats.add(id)) id,
      ];
      final localChats = await Future.wait(localIds.map(_fetchChat));
      if (!_isCurrent(tab, runId, trimmed)) return;
      for (final s in localChats) {
        if (s == null || out.length >= resultLimit) continue;
        out.add(_SearchHit.chat(s));
        final uid = s.peerUserId;
        if (uid != null) seenUsers.add(uid);
      }

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
    final scopeChatId = this.scopeChatId;
    final senderUserId = this.senderUserId;
    try {
      final List<List<Map<String, dynamic>>> pages;
      if (scopeChatId != null) {
        pages = [
          await _searchMessagesInChat(
            chatId: scopeChatId,
            query: trimmed,
            filter: filter,
            limit: resultLimit,
            senderUserId: senderUserId,
          ),
        ];
      } else if (senderUserId != null) {
        final chatIds = await _commonChatIds(senderUserId);
        if (!_isCurrent(tab, runId, trimmed)) return;
        pages = await Future.wait([
          for (final chatId in chatIds)
            _searchMessagesInChat(
              chatId: chatId,
              query: trimmed,
              filter: filter,
              limit: resultLimit,
              senderUserId: senderUserId,
            ),
        ]);
      } else {
        pages = await Future.wait([
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
      }
      if (!_isCurrent(tab, runId, trimmed)) return;
      final raw = <Map<String, dynamic>>[for (final page in pages) ...page]
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

  /// Every chat the account and [userId] share, plus their private chat.
  ///
  /// A private chat's id is the user's own id in TDLib, so it needs no lookup.
  Future<List<int>> _commonChatIds(int userId) async {
    final cached = _commonChatCache[userId];
    if (cached != null) return cached;
    final ids = <int>[userId];
    try {
      final response = await TdClient.shared.query({
        '@type': 'getGroupsInCommon',
        'user_id': userId,
        'offset_chat_id': 0,
        'limit': 100,
      });
      ids.addAll(response.int64Array('chat_ids') ?? const <int>[]);
    } catch (_) {
      // No shared groups readable; the private chat alone is still a result.
    }
    final unique = List<int>.unmodifiable(ids.toSet());
    _commonChatCache[userId] = unique;
    return unique;
  }

  Future<List<Map<String, dynamic>>> _searchMessagesInChat({
    required int chatId,
    required String query,
    required String filter,
    required int limit,
    int? senderUserId,
  }) async {
    try {
      final res = await TdClient.shared.query({
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'query': query,
        'sender_id': senderUserId == null
            ? null
            : {'@type': 'messageSenderUser', 'user_id': senderUserId},
        'from_message_id': 0,
        'offset': 0,
        'limit': limit,
        'filter': {'@type': filter},
      });
      return res.objects('messages') ?? const <Map<String, dynamic>>[];
    } catch (_) {
      return const <Map<String, dynamic>>[];
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

  static final RegExp _handleLink = RegExp(
    r'(?:https?://)?(?:t\.me|telegram\.me)/(@?[A-Za-z0-9_]+)',
    caseSensitive: false,
  );
  static final RegExp _handleShape = RegExp(r'^[A-Za-z0-9_]{3,32}$');

  String? _usernameOf(String q) {
    var s = q.trim();
    final link = _handleLink.firstMatch(s);
    if (link != null) s = link.group(1)!;
    if (s.startsWith('@')) s = s.substring(1);
    return _handleShape.hasMatch(s) ? s : null;
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
    this.telegramLink,
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

  factory _SearchHit.telegramLink({
    required String displayValue,
    required String link,
  }) => _SearchHit(
    title: AppStrings.t(AppStringKeys.linkHandlerOpenChat),
    subtitle: displayValue,
    telegramLink: link,
    icon: HeroAppIcons.link,
    tint: AppTheme.brand,
  );

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
  final String? telegramLink;
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
      return AppStrings.t(AppStringKeys.sharedMediaVoiceMessages);
    }
    if (message.video != null) {
      final text = message.text.trim();
      return text.isEmpty ||
              text == AppStrings.t(AppStringKeys.chatVideoPlaceholder)
          ? AppStrings.t(AppStringKeys.chatVideoPlaceholder)
          : text;
    }
    if (message.image != null) {
      final text = message.text.trim();
      return text.isEmpty ||
              text == AppStrings.t(AppStringKeys.composerImagePreview)
          ? AppStrings.t(AppStringKeys.composerImagePreview)
          : text;
    }
    return message.text.trim().isEmpty
        ? AppStrings.t(AppStringKeys.chatSearchMessageResultLabel)
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
        text != AppStrings.t(AppStringKeys.composerImagePreview) &&
        text != AppStrings.t(AppStringKeys.chatVideoPlaceholder)) {
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
