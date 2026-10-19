//
//  chat_message_search_controller.dart
//
//  In-chat message search. The transcript never leaves the screen, so this
//  owns only the query, the paged `searchChatMessages` results, and the cursor
//  the search header, navigator, and results pane step through. Moving the
//  transcript to a hit stays the chat view's job; the controller announces it
//  through [ChatMessageSearchController.onActivateResult].
//

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../app/adaptive_split_layout.dart';
import '../chats/search_token_suggestions.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import 'chat_search_query.dart';
import 'telegram_link.dart';

/// Width of the trailing results pane in a wide chat.
const double chatSearchResultsPaneWidth = 300;

/// A wide chat lists every hit beside the transcript and keeps the composer;
/// anything narrower steps through hits from a bottom navigator so the
/// transcript keeps the full width.
bool chatSearchUsesResultsPane({
  required Size windowSize,
  required double conversationWidth,
  TargetPlatform? platform,
  bool isWeb = kIsWeb,
}) =>
    usesSplitSelectionLayout(windowSize, platform: platform, isWeb: isWeb) &&
    conversationWidth >=
        chatSearchResultsPaneWidth + desktopConversationMinWidth;

/// Splits [text] around every occurrence of [query] so a result row can weight
/// the matched runs. Returns a single unstyled span when nothing matches.
List<InlineSpan> chatSearchHighlightSpans({
  required String text,
  required String query,
  required TextStyle matchStyle,
}) {
  final needle = query.trim();
  if (needle.isEmpty || text.isEmpty) return [TextSpan(text: text)];
  final haystack = text.toLowerCase();
  final lowerNeedle = needle.toLowerCase();
  final spans = <InlineSpan>[];
  var start = 0;
  while (start < text.length) {
    final index = haystack.indexOf(lowerNeedle, start);
    if (index < 0) break;
    if (index > start) spans.add(TextSpan(text: text.substring(start, index)));
    final end = index + needle.length;
    spans.add(TextSpan(text: text.substring(index, end), style: matchStyle));
    start = end;
  }
  if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
  return spans.isEmpty ? [TextSpan(text: text)] : spans;
}

/// What one `date:` lookup established, for the search header's calendar jump.
///
/// Three outcomes are deliberately distinct, because they mean different
/// things to the user:
/// - [current] is false when the lookup was superseded (search closed,
///   disposal, a newer pick, a results restart). The answer was abandoned, so
///   the caller must neither land nor toast.
/// - [emptyDay] is true only when the picked day provably has no messages:
///   TDLib answered NOT_FOUND, or its day-boundary anchor fell outside the
///   day. It is never used for a history walk that failed or stopped early.
/// - [message], when non-null, is the first message of the picked day as
///   proven by a complete backward walk (see
///   [ChatMessageSearchController.messageAtDate]).
///
/// When [current] is true, [emptyDay] is false and [message] is null, the walk
/// could not prove which message began the day — a transport failure, a page
/// that stopped moving backwards, or a page that kept returning the boundary
/// message. That is "unresolved": the caller says so rather than claiming the
/// day is empty or presenting a mid-day message as its first.
typedef DateLookupResult = ({
  bool current,
  bool emptyDay,
  ChatMessage? message,
});

/// One step of the backward history walk. Only
/// [ChatMessageSearchController.messageAtDate] constructs these.
enum _DateHistoryStep {
  /// The page lay entirely inside the picked day and moved the cursor to an
  /// older message: keep walking.
  advanced,

  /// The page proved what lies before it: it reached a message older than the
  /// picked day, came back empty, or reached the smallest possible server
  /// message id — the only signs that nothing older exists. The earliest
  /// in-day message seen is provably the day's first.
  proved,

  /// The page neither reached the day boundary nor produced a strictly older
  /// message: it returned only newer ids (ignoring the inclusive upper bound),
  /// nothing usable, or the cursor's own message alone. TDLib chooses its own
  /// page length, so a short page proves nothing about what lies before it:
  /// the cursor is retried a bounded number of times, then the walk fails
  /// closed instead of reading this as the beginning of the day.
  stalled,
}

/// The kinds of message an in-chat search can narrow to.
///
/// Labels and TDLib filter names are the ones global search already uses, so a
/// chat's filter strip reads the same as the search screen's category tabs.
enum ChatSearchFilter {
  all,
  media,
  links,
  files,
  music,
  voice;

  String get labelKey => switch (this) {
    ChatSearchFilter.all => AppStringKeys.sharedMediaFilterAll,
    ChatSearchFilter.media => AppStringKeys.searchTabMedia,
    ChatSearchFilter.links => AppStringKeys.searchTabLinks,
    ChatSearchFilter.files => AppStringKeys.searchTabFiles,
    ChatSearchFilter.music => AppStringKeys.searchTabMusic,
    ChatSearchFilter.voice => AppStringKeys.searchTabVoiceMessages,
  };

  String get tdlibFilter => switch (this) {
    ChatSearchFilter.all => 'searchMessagesFilterEmpty',
    ChatSearchFilter.media => 'searchMessagesFilterPhotoAndVideo',
    ChatSearchFilter.links => 'searchMessagesFilterUrl',
    ChatSearchFilter.files => 'searchMessagesFilterDocument',
    ChatSearchFilter.music => 'searchMessagesFilterAudio',
    ChatSearchFilter.voice => 'searchMessagesFilterVoiceNote',
  };
}

/// Sender identity for a hit, resolved once per sender and shared by every
/// result row that quotes them.
class _SearchSender {
  const _SearchSender({required this.name, this.photo});

  final String name;
  final TdFileRef? photo;
}

/// Query, results, and cursor for search inside one open chat.
///
/// Results arrive newest-first, matching TDLib. "Older" therefore walks
/// forward through [results] and "newer" walks back, which is also the
/// direction the up/down controls point in the transcript.
class ChatMessageSearchController extends ChangeNotifier {
  ChatMessageSearchController({
    required this.chatId,
    TdClient? client,
    this.onActivateResult,
    this.autoActivateFirstResult = true,
  }) : _client = client ?? TdClient.shared {
    textController.addListener(_handleSelectionChanged);
  }

  static const Duration _debounceDelay = Duration(milliseconds: 280);
  static const int _pageSize = 40;

  final int chatId;
  final TdClient _client;

  /// Called whenever the cursor lands on a hit.
  ///
  /// `automatic` marks the landing a fresh query performs on its own, which a
  /// caller must treat differently from a deliberate step: it happens on every
  /// keystroke's worth of results.
  final void Function(ChatMessage message, {required bool automatic})?
  onActivateResult;

  /// Whether a fresh query moves the cursor to its newest hit.
  ///
  /// A transcript wants that — the view follows what was typed. A surface that
  /// only lists hits does not: there is nothing to follow, and a marked first
  /// row would read as a choice the user did not make.
  final bool autoActivateFirstResult;

  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode();

  final Map<int, _SearchSender> _senders = {};
  Timer? _debounce;
  Timer? _suggestDebounce;
  int _runId = 0;

  /// Ownership token for calendar-jump lookups; a newer pick (or any run
  /// invalidation) abandons the older one so a stale response never lands.
  int _datePickId = 0;

  /// Monotonic session counter bumped by [open] and [close], so a picker sheet
  /// or lookup started in an older session is dropped after close/reopen.
  int _sessionId = 0;

  /// Current session token, or 0 when the search session is closed/disposed.
  int get sessionToken => _disposed || !_active ? 0 : _sessionId;

  /// Whether [token] still identifies the currently open search session.
  bool isCurrentSession(int token) =>
      !_disposed && _active && token != 0 && token == _sessionId;

  bool _disposed = false;
  bool _active = false;
  bool _loading = false;
  bool _loadingMore = false;
  String _query = '';
  int _totalCount = 0;
  int _nextFromMessageId = 0;
  int _activeIndex = -1;
  List<ChatMessage> _results = const [];
  ChatSearchFilter _filter = ChatSearchFilter.all;
  ChatSearchTokens _tokens = const ChatSearchTokens(text: '');
  _SearchSenderFilter? _senderFilter;
  late final ChatSearchTokenSuggester _suggester = ChatSearchTokenSuggester(
    client: _client,
  );
  ChatSearchActiveToken? _activeToken;

  /// Picked from the suggestion list rather than typed; it outlives the text,
  /// because its token has been taken out of it.
  _SearchSenderFilter? _committedSender;
  List<ChatSearchTokenSuggestion> _suggestions = const [];
  int _suggestRunId = 0;

  bool get isActive => _active;
  String get query => _query;
  List<ChatMessage> get results => _results;
  int get activeIndex => _activeIndex;
  ChatMessage? get activeResult =>
      _activeIndex >= 0 && _activeIndex < _results.length
      ? _results[_activeIndex]
      : null;
  int? get activeMessageId => activeResult?.id;

  /// The filter in force: a `has:` token wins over the chip while it is typed,
  /// because it is the more specific thing the user just said.
  ChatSearchFilter get filter => _tokens.filter ?? _filter;

  /// The resolved `from:` sender, once a member matched the token.
  int? get senderUserId => (_committedSender ?? _senderFilter)?.userId;
  String? get senderName => (_committedSender ?? _senderFilter)?.name;

  /// The `from:` text as typed, resolved or not.
  String? get senderQuery => _tokens.fromQuery;

  /// The token the caret is in, if it is one that offers suggestions.
  ChatSearchActiveToken? get activeToken => _activeToken;
  List<ChatSearchTokenSuggestion> get suggestions => _suggestions;

  /// A run is in flight, or one is queued behind the debounce.
  bool get isLoading => _loading || _debounce?.isActive == true;
  bool get hasQuery => _query.trim().isNotEmpty;

  /// Whether anything is being searched for. A narrowed filter, a typed
  /// `from:` token, or a sender committed from the suggestion list counts on
  /// its own — "every photo Bob sent" is a useful result set with no words
  /// typed.
  bool get hasSearch =>
      _tokens.text.trim().isNotEmpty ||
      filter != ChatSearchFilter.all ||
      _tokens.fromQuery != null ||
      _committedSender != null;

  /// Whether the field itself states a search, leaving out a sender committed
  /// as a badge: the hint card stays available beside the badge so `has:` can
  /// still be combined with it.
  bool get _hasFieldSearch =>
      _tokens.text.trim().isNotEmpty ||
      filter != ChatSearchFilter.all ||
      _tokens.fromQuery != null;
  bool get hasResults => _results.isNotEmpty;
  bool get hasMore => _nextFromMessageId != 0;

  /// TDLib reports the full match count even while only the first page is
  /// loaded; a short or exhausted response can still exceed it.
  int get matchCount => math.max(_totalCount, _results.length);

  /// The cursor's 1-based position, or 0 before anything is selected.
  int get matchPosition => _activeIndex < 0 ? 0 : _activeIndex + 1;

  bool get canStepOlder =>
      _activeIndex + 1 < _results.length || (hasMore && hasResults);
  bool get canStepNewer => _activeIndex > 0;

  void open({String? initialQuery}) {
    if (_disposed) return;
    final seed = initialQuery?.trim() ?? '';
    if (!_active) {
      _active = true;
      _sessionId++;
      notifyListeners();
    }
    if (seed.isNotEmpty && seed != _query) {
      textController.value = TextEditingValue(
        text: seed,
        selection: TextSelection.collapsed(offset: seed.length),
      );
      updateQuery(seed);
    }
    focusNode.requestFocus();
  }

  void close() {
    if (_disposed || !_active) return;
    _cancelRun();
    _sessionId++;
    _active = false;
    _query = '';
    _results = const [];
    _activeIndex = -1;
    _totalCount = 0;
    _nextFromMessageId = 0;
    _loading = false;
    _loadingMore = false;
    _filter = ChatSearchFilter.all;
    _tokens = const ChatSearchTokens(text: '');
    _senderFilter = null;
    _activeToken = null;
    _committedSender = null;
    _suggestions = const [];
    _suggestDebounce?.cancel();
    _suggestDebounce = null;
    _suggestRunId++;
    textController.clear();
    focusNode.unfocus();
    notifyListeners();
  }

  void updateQuery(String value) {
    if (_disposed) return;
    _query = value;
    _tokens = parseChatSearchQuery(value);
    final caret = textController.selection.baseOffset;
    // `in:` means nothing inside one chat — the chat is already decided — so
    // only a sender token offers suggestions here.
    final token = activeChatSearchToken(
      value,
      caret < 0 ? value.length : caret,
    );
    _activeToken =
        token?.kind == ChatSearchTokenKind.from ||
            token?.kind == ChatSearchTokenKind.has
        ? token
        : null;
    // A sender resolved for a different token no longer applies.
    if (_senderFilter?.query != _tokens.fromQuery) _senderFilter = null;
    _startSuggestions();
    _restart();
  }

  void _handleSelectionChanged() {
    if (_disposed || !_active || textController.text != _query) return;
    final caret = textController.selection.baseOffset;
    final candidate = activeChatSearchToken(
      _query,
      caret < 0 ? _query.length : caret,
    );
    final next =
        candidate?.kind == ChatSearchTokenKind.from ||
            candidate?.kind == ChatSearchTokenKind.has
        ? candidate
        : null;
    final previous = _activeToken;
    if ((next?.kind, next?.value, next?.start, next?.end) ==
        (previous?.kind, previous?.value, previous?.start, previous?.end)) {
      return;
    }
    _activeToken = next;
    _startSuggestions();
    notifyListeners();
  }

  void _startSuggestions() {
    _suggestDebounce?.cancel();
    final token = _activeToken;
    final runId = ++_suggestRunId;
    if (token == null) {
      _suggestions = const [];
      return;
    }
    // Every keystroke inside a `from:` token fans out into searchChatMembers
    // plus one round trip per candidate id, so coalesce it the way the message
    // search itself is. An empty token is the affordance shown the moment
    // `from:` is typed, and it has nothing to coalesce, so it stays immediate.
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
      final results = await _suggester.suggest(token, scopeChatId: chatId);
      if (_disposed || runId != _suggestRunId) return;
      _suggestions = results;
      notifyListeners();
    }());
  }

  /// Whether the field is asking to be taught its syntax: focused, with no
  /// search of its own stated.
  ///
  /// A committed sender does not close the lesson — `has:` still combines with
  /// it — but results on the pane outrank the lesson, and any typed word,
  /// filter, or `from:` token closes it outright.
  bool get showsTokenHints =>
      focusNode.hasFocus && !_hasFieldSearch && _results.isEmpty;

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

  /// Commits a picked suggestion to a badge and takes its text out of the
  /// field, so the filter is stated once rather than twice.
  void applySuggestion(ChatSearchTokenSuggestion suggestion) {
    final token = _activeToken;
    if (_disposed || token == null) return;
    if (token.kind == ChatSearchTokenKind.has) {
      // A `has:` kind is complete text, not a badge — the field keeps the
      // token so the stated filter stays visible and editable.
      final applied = applyChatSearchToken(_query, token, suggestion.token);
      textController.value = TextEditingValue(
        text: applied.text,
        selection: TextSelection.collapsed(offset: applied.caret),
      );
      focusNode.requestFocus();
      updateQuery(applied.text);
      return;
    }
    _committedSender = _SearchSenderFilter(
      query: suggestion.token,
      userId: suggestion.id,
      name: suggestion.title,
    );
    final applied = removeChatSearchToken(_query, token);
    textController.value = TextEditingValue(
      text: applied.text,
      selection: TextSelection.collapsed(offset: applied.caret),
    );
    focusNode.requestFocus();
    updateQuery(applied.text);
  }

  /// Narrows the search to one kind of message, keeping whatever is typed.
  void setFilter(ChatSearchFilter filter) {
    if (_disposed || filter == _filter) return;
    _filter = filter;
    _restart();
  }

  /// The first message sent on [date] (local-time day bounds `[dayStart, dayEnd)`),
  /// as far as the history walk could prove it.
  ///
  /// This is the `date:` jump. TDLib's `getChatMessageByDate` answers "the
  /// latest message sent no later than the timestamp", so `dayEnd - 1` (the
  /// last second of [date], `23:59:59` local) is queried first:
  /// - If the anchor is outside `[dayStart, dayEnd)` (e.g. an older message
  ///   from a previous day, or a `dayEnd` next-midnight message), the picked
  ///   day has no messages and [DateLookupResult.emptyDay] is set. A success
  ///   response that is not a message is unresolved, not evidence of an empty
  ///   day.
  /// - Otherwise `getChatHistory` pages backwards from the anchor while
  ///   messages remain in `[dayStart, dayEnd)`, tracking the earliest message
  ///   on [date] so a multi-message day lands on its first message rather than
  ///   its last.
  ///
  /// `getChatHistory`'s `from_message_id` is an inclusive upper bound, its
  /// `offset` must be non-positive (TDLib answers a positive offset with
  /// `400 Parameter offset must be non-positive`), and the id itself must be a
  /// real TDLib message id: server ids are packed as `server_id << 20`, and
  /// `MessageId::is_valid` rejects every other low-bit pattern, so a derived id
  /// such as `anchor.id - 1` — which sets the low type bits — is answered with
  /// `400 Invalid value of parameter from_message_id specified`. The walk
  /// therefore never does arithmetic on ids: its cursor is always an id TDLib
  /// itself returned, starting at the anchor and then following each page's
  /// oldest message, with `offset` kept at `0`. The page echoes the cursor's
  /// own message (inclusive upper bound); that echo is skipped when scoring.
  ///
  /// The walk must prove that nothing earlier in the day exists: it succeeds
  /// only on a message older than the day, an empty history page, or the
  /// smallest possible server message id. A short cursor-only page is not
  /// proof of exhaustion. A page that returns only
  /// newer messages (ignoring the inclusive bound), a page with no usable
  /// message, or a transport error leaves the day unresolved:
  /// [DateLookupResult.message] is null and [DateLookupResult.emptyDay] is
  /// false. A short page that does move backwards proves nothing about what
  /// lies before it — TDLib chooses its own page length — so the walk
  /// continues from its oldest message. There is deliberately no fixed page
  /// budget: a busy day is walked to its actual first message, and a cut-off
  /// walk is reported as unresolved instead of returning a mid-day message.
  ///
  /// `current` is false when the lookup was superseded — closed search
  /// session, disposal, a results restart, or a newer pick — and the caller
  /// must drop the answer without toasting: a mounted context and a live
  /// controller cannot tell a stale response from a current one, ownership is
  /// checked at every await seam here.
  Future<DateLookupResult> messageAtDate(DateTime date) async {
    if (_disposed || !_active) {
      return (current: false, emptyDay: false, message: null);
    }
    final dayStart =
        DateTime(date.year, date.month, date.day).millisecondsSinceEpoch ~/
        1000;
    final dayEnd =
        DateTime(date.year, date.month, date.day + 1).millisecondsSinceEpoch ~/
        1000;
    final pick = ++_datePickId;
    final runIdAtStart = _runId;
    final sessionAtStart = _sessionId;
    bool isStillCurrent() =>
        !_disposed &&
        _active &&
        _sessionId == sessionAtStart &&
        pick == _datePickId &&
        _runId == runIdAtStart;
    bool inPickedDay(ChatMessage message) =>
        message.date >= dayStart && message.date < dayEnd;
    DateLookupResult superseded() =>
        (current: false, emptyDay: false, message: null);
    DateLookupResult unresolved() =>
        (current: true, emptyDay: false, message: null);
    DateLookupResult emptyDay() =>
        (current: true, emptyDay: true, message: null);
    DateLookupResult found(ChatMessage message) =>
        (current: true, emptyDay: false, message: message);

    final ChatMessage anchor;
    try {
      final response = await _client.query({
        '@type': 'getChatMessageByDate',
        'chat_id': chatId,
        'date': dayEnd - 1,
      });
      if (!isStillCurrent()) return superseded();
      final parsed = TDParse.message(response);
      if (parsed == null) {
        // A success response that is not a message proves nothing about the
        // day; only the day-boundary anchor itself can prove it empty.
        return unresolved();
      }
      if (!inPickedDay(parsed)) {
        // The anchor is outside the picked day: that day provably has no
        // messages, which is different from a failed walk.
        return emptyDay();
      }
      anchor = parsed;
    } catch (error) {
      if (!isStillCurrent()) return superseded();
      // TDLib answers NOT_FOUND for a day without messages at or before it —
      // a real empty answer, not a stale one. Anything else is transport or
      // client noise: unresolved, so the caller can say the jump failed
      // instead of claiming the day is empty.
      final notFound = error is TdError && error.code == 404;
      return notFound ? emptyDay() : unresolved();
    }

    var earliest = anchor;
    // The cursor is always a message id TDLib returned — the anchor first,
    // then each page's oldest message. Server ids are packed as
    // `server_id << 20`; deriving an id (`anchor.id - 1`) would set the low
    // type bits and TDLib rejects it with `400 Invalid value of parameter
    // from_message_id specified`. `from_message_id` is inclusive, so the page
    // starts with the cursor's own message; `offset` stays 0 (it must be
    // non-positive).
    var cursor = anchor.id;
    // A page that does not move the cursor backwards is retried this many
    // times in total before the walk fails closed: TDLib may return fewer
    // messages than requested while it loads the older ones in the
    // background, so one cursor-only page does not end the chat's history.
    var attempts = 0;
    const maxAttemptsPerCursor = 3;
    // The smallest server message id: no chat can hold an older message, so
    // a page that returns it proves nothing precedes it.
    const firstServerMessageId = 1 << 20;
    const pageLimit = 100;
    // Walk backwards until the day boundary is proven: a message older than
    // the picked day, an empty page, or the smallest server message id —
    // the only signs that nothing older exists. A short or cursor-only page
    // proves nothing: TDLib chooses the page length for performance.
    // `earliest` is reported only after such proof.
    while (cursor > 0) {
      final Map<String, dynamic> history;
      try {
        history = await _client.query({
          '@type': 'getChatHistory',
          'chat_id': chatId,
          'from_message_id': cursor,
          'offset': 0,
          'limit': pageLimit,
          'only_local': false,
        });
      } catch (_) {
        // Transport failure mid-walk: the day boundary was never proven.
        if (!isStillCurrent()) return superseded();
        return unresolved();
      }
      if (!isStillCurrent()) return superseded();
      final rawMessages = history.objects('messages');
      if (rawMessages == null) {
        // A response without a message list is malformed, not proof that the
        // chat's history ended here.
        return unresolved();
      }
      if (rawMessages.isEmpty) {
        // Nothing at or before the cursor exists — the walk is complete.
        return found(earliest);
      }
      // The page is newest→oldest and bounded by the cursor. Only ids
      // strictly below it are older messages; the cursor's own message was
      // already scored (the anchor on the first page, the previous page's
      // oldest after that).
      int? oldestOlderId;
      int? oldestAnyId;
      var reachedBeforeDay = false;
      for (final raw in rawMessages) {
        final msg = TDParse.message(raw);
        if (msg == null) continue;
        if (oldestAnyId == null || msg.id < oldestAnyId) {
          oldestAnyId = msg.id;
        }
        if (msg.id == cursor) continue;
        if (msg.id > cursor) continue; // ignores the inclusive bound
        if (oldestOlderId == null || msg.id < oldestOlderId) {
          oldestOlderId = msg.id;
        }
        if (msg.date < dayStart) {
          reachedBeforeDay = true;
          continue;
        }
        if (inPickedDay(msg)) {
          if (msg.date < earliest.date ||
              (msg.date == earliest.date && msg.id < earliest.id)) {
            earliest = msg;
          }
        }
      }
      final step =
          reachedBeforeDay ||
              // Server message ids start at 1: reaching it means nothing
              // older can exist in this chat, whatever the page length.
              oldestAnyId == firstServerMessageId
          ? _DateHistoryStep.proved
          : oldestOlderId == null
          // Nothing strictly older came back. TDLib chooses its own page
          // length for performance, so neither a short page nor an echoed
          // cursor proves that the chat's history ends there: the same cursor
          // is retried a bounded number of times, and if the page still does
          // not move backwards the walk fails closed instead of presenting a
          // mid-day message as the day's first.
          ? _DateHistoryStep.stalled
          : _DateHistoryStep.advanced;
      switch (step) {
        case _DateHistoryStep.proved:
          return found(earliest);
        case _DateHistoryStep.stalled:
          attempts++;
          if (attempts < maxAttemptsPerCursor) continue;
          return unresolved();
        case _DateHistoryStep.advanced:
          cursor = oldestOlderId!;
          attempts = 0;
      }
    }
    // The cursor left the id space without an end-of-history page.
    return unresolved();
  }

  /// Drops the current results and queues a fresh first page. Hits from the
  /// previous query or filter describe a different set, so they are discarded
  /// rather than filtered down.
  void _restart() {
    _cancelRun();
    _results = const [];
    _activeIndex = -1;
    _totalCount = 0;
    _nextFromMessageId = 0;
    _loadingMore = false;
    _loading = false;
    if (hasSearch) {
      final runId = _runId;
      _debounce = Timer(
        _debounceDelay,
        () => _runFirstPage(_tokens.text.trim(), runId),
      );
    }
    notifyListeners();
  }

  /// Drops the committed `from:` badge.
  void clearSender() {
    if (_disposed || _committedSender == null) return;
    _committedSender = null;
    focusNode.requestFocus();
    _restart();
  }

  void clear() {
    if (_disposed) return;
    textController.clear();
    updateQuery('');
    focusNode.requestFocus();
  }

  /// Moves the cursor to [index] and announces the hit. Out-of-range indexes
  /// are ignored so callers can step without bounds-checking twice.
  void selectIndex(int index, {bool automatic = false}) {
    if (_disposed || index < 0 || index >= _results.length) return;
    _activeIndex = index;
    notifyListeners();
    onActivateResult?.call(_results[index], automatic: automatic);
  }

  void selectResult(ChatMessage message) {
    final index = _results.indexWhere((result) => result.id == message.id);
    if (index >= 0) selectIndex(index);
  }

  /// Steps one hit further back in time, loading the next page first when the
  /// cursor is sitting on the oldest loaded hit.
  Future<void> stepOlder() async {
    if (_disposed || _results.isEmpty) return;
    if (_activeIndex + 1 >= _results.length) {
      if (!hasMore) return;
      await loadMore();
      if (_disposed || _activeIndex + 1 >= _results.length) return;
    }
    selectIndex(_activeIndex + 1);
  }

  void stepNewer() {
    if (_disposed || _activeIndex <= 0) return;
    selectIndex(_activeIndex - 1);
  }

  Future<void> loadMore() async {
    if (_disposed || _loadingMore || !hasMore || !hasSearch) return;
    final trimmed = _tokens.text.trim();
    final runId = _runId;
    _loadingMore = true;
    notifyListeners();
    final page = await _fetchPage(trimmed, from: _nextFromMessageId);
    if (_disposed || runId != _runId) return;
    _loadingMore = false;
    if (page == null) {
      notifyListeners();
      return;
    }
    _appendPage(page, runId: runId);
  }

  Future<void> _runFirstPage(String trimmed, int runId) async {
    if (_disposed || runId != _runId) return;
    _loading = true;
    notifyListeners();
    // The sender has to be resolved before the first page, or the page would
    // be run unfiltered and then replaced a moment later.
    await _resolveSenderFilter(runId);
    if (_disposed || runId != _runId) return;
    final page = await _fetchPage(trimmed, from: 0);
    if (_disposed || runId != _runId) return;
    _loading = false;
    if (page == null) {
      notifyListeners();
      return;
    }
    _appendPage(page, runId: runId, activateFirst: true);
  }

  void _appendPage(
    _SearchPage page, {
    required int runId,
    bool activateFirst = false,
  }) {
    final known = {for (final result in _results) result.id};
    final merged = <ChatMessage>[
      ..._results,
      ...page.messages.where((message) => known.add(message.id)),
    ];
    final grew = merged.length > _results.length;
    _results = List<ChatMessage>.unmodifiable(merged);
    _totalCount = page.totalCount;
    // A page that adds nothing new cannot advance the cursor, so treat it as
    // the end of the results rather than paging the same window forever.
    _nextFromMessageId = grew ? page.nextFromMessageId : 0;
    notifyListeners();
    unawaited(_hydrateSenders(page.messages, runId));
    // Typing lands on the newest hit so the transcript follows the query
    // without a second gesture; later pages never move the cursor.
    if (activateFirst && autoActivateFirstResult && _results.isNotEmpty) {
      selectIndex(0, automatic: true);
    }
  }

  Future<_SearchPage?> _fetchPage(String query, {required int from}) async {
    final userId = senderUserId;
    try {
      final response = await _client.query({
        '@type': 'searchChatMessages',
        'chat_id': chatId,
        'query': query,
        'sender_id': userId == null
            ? null
            : {'@type': 'messageSenderUser', 'user_id': userId},
        'from_message_id': from,
        'offset': 0,
        'limit': _pageSize,
        'filter': {'@type': filter.tdlibFilter},
      });
      final raw =
          response.objects('messages') ?? const <Map<String, dynamic>>[];
      final messages = raw
          .map(TDParse.message)
          .whereType<ChatMessage>()
          .where((message) => !message.isService)
          .toList(growable: false);
      // A zero cursor means TDLib reached the beginning of the chat. Without
      // one, the oldest hit in the page is the only usable cursor, and a short
      // page is the only proof that paging is done.
      final nextFromMessageId =
          response.int64('next_from_message_id') ??
          (raw.length < _pageSize ? 0 : (messages.lastOrNull?.id ?? 0));
      return _SearchPage(
        messages: messages,
        totalCount: response.integer('total_count') ?? messages.length,
        nextFromMessageId: nextFromMessageId,
      );
    } catch (_) {
      return null;
    }
  }

  /// Turns the `from:` text into a member of this chat.
  ///
  /// TDLib matches names and usernames itself, so the token behaves like the
  /// member picker rather than an exact-name match. An unresolvable name
  /// leaves the filter off — the search still runs on the remaining words.
  Future<void> _resolveSenderFilter(int runId) async {
    if (_committedSender != null) return;
    final query = _tokens.fromQuery;
    if (query == null) {
      _senderFilter = null;
      return;
    }
    if (_senderFilter?.query == query) return;
    final lookupUserId = telegramUserIdFromQuery(query);
    if (lookupUserId != null) {
      final resolved = await _resolveSender(lookupUserId);
      if (_disposed || runId != _runId) return;
      _senderFilter = _SearchSenderFilter(
        query: query,
        userId: lookupUserId,
        name: resolved?.name ?? '$lookupUserId',
      );
      return;
    }
    try {
      final response = await _client.query({
        '@type': 'searchChatMembers',
        'chat_id': chatId,
        'query': query,
        'limit': 1,
        'filter': null,
      });
      if (_disposed || runId != _runId) return;
      final member = (response.objects('members') ?? const []).firstOrNull;
      final sender = member?.obj('member_id');
      final userId = sender?.type == 'messageSenderUser'
          ? sender?.int64('user_id')
          : null;
      if (userId == null || userId == 0) {
        _senderFilter = null;
        return;
      }
      final resolved = await _resolveSender(userId);
      if (_disposed || runId != _runId) return;
      _senderFilter = _SearchSenderFilter(
        query: query,
        userId: userId,
        name: resolved?.name ?? query,
      );
    } catch (_) {
      if (!_disposed && runId == _runId) _senderFilter = null;
    }
  }

  /// Search hits arrive without a resolved sender, so a group would otherwise
  /// attribute every row to the chat itself.
  Future<void> _hydrateSenders(List<ChatMessage> batch, int runId) async {
    var changed = false;
    for (final message in batch) {
      if (_disposed || runId != _runId) return;
      final senderId = message.senderId;
      if (senderId == null || senderId == 0) continue;
      if (message.isOutgoing && !message.senderIsChat) continue;
      if (message.senderName != null) continue;
      var sender = _senders[senderId];
      if (sender == null) {
        sender = await _resolveSender(senderId);
        if (_disposed || runId != _runId) return;
        if (sender == null) continue;
        _senders[senderId] = sender;
      }
      message.senderName ??= sender.name;
      message.senderPhoto ??= sender.photo;
      changed = true;
    }
    if (changed && !_disposed && runId == _runId) notifyListeners();
  }

  Future<_SearchSender?> _resolveSender(int senderId) async {
    try {
      if (senderId > 0) {
        final user = await _client.query({
          '@type': 'getUser',
          'user_id': senderId,
        });
        return _SearchSender(
          name: TDParse.userName(user),
          photo: TDParse.smallPhoto(user.obj('profile_photo')),
        );
      }
      final chat = await _client.query({
        '@type': 'getChat',
        'chat_id': senderId,
      });
      final title = chat.str('title')?.trim();
      // An untitled sender chat keeps the row's own peer-title fallback rather
      // than showing a placeholder name.
      if (title == null || title.isEmpty) return null;
      return _SearchSender(
        name: title,
        photo: TDParse.smallPhoto(chat.obj('photo')),
      );
    } catch (_) {
      return null;
    }
  }

  /// Invalidates every in-flight page so a stale response can never repopulate
  /// the list behind a newer query.
  void _cancelRun() {
    _debounce?.cancel();
    _debounce = null;
    _runId++;
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelRun();
    _suggestDebounce?.cancel();
    _suggestDebounce = null;
    textController.dispose();
    focusNode.dispose();
    super.dispose();
  }
}

/// A `from:` token that resolved to a real member.
class _SearchSenderFilter {
  const _SearchSenderFilter({
    required this.query,
    required this.userId,
    required this.name,
  });

  /// The token text this was resolved from, so a retyped name re-resolves.
  final String query;
  final int userId;
  final String name;
}

class _SearchPage {
  const _SearchPage({
    required this.messages,
    required this.totalCount,
    required this.nextFromMessageId,
  });

  final List<ChatMessage> messages;
  final int totalCount;
  final int nextFromMessageId;
}
