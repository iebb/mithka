import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_navigator.dart';
import '../chat/chat_view.dart';
import '../components/app_icons.dart';
import '../components/confirm_dialog.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/date_text.dart';
import 'public_discovery_service.dart';

class PublicDiscoveryView extends StatefulWidget {
  const PublicDiscoveryView({super.key, this.initialQuery = ''});

  final String initialQuery;

  @override
  State<PublicDiscoveryView> createState() => _PublicDiscoveryViewState();
}

class _PublicDiscoveryViewState extends State<PublicDiscoveryView> {
  final _service = const PublicDiscoveryService();
  final _searchController = TextEditingController();
  Timer? _debounce;
  _DiscoveryTab _tab = _DiscoveryTab.channels;
  _GlobalMediaFilter _mediaFilter = _GlobalMediaFilter.photoAndVideo;
  int _generation = 0;
  bool _loading = false;
  String? _error;

  List<_DiscoveryPeer> _channels = const [];
  List<_DiscoveryPeer> _bots = const [];
  List<_DiscoveryPeer> _similar = const [];
  String _similarTitle = '';
  int? _similarSourceChatId;
  int? _similarSourceBotUserId;

  List<_DiscoveryHit> _hits = const [];
  String _nextOffset = '';
  int _requiredStarCount = 0;
  int? _agreedStarCount;

  @override
  void initState() {
    super.initState();
    _searchController.text = widget.initialQuery;
    unawaited(_run(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _queryChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 320), () {
      if (mounted) unawaited(_run(reset: true));
    });
    setState(() {});
  }

  void _selectTab(_DiscoveryTab tab) {
    if (_tab == tab) return;
    setState(() {
      _tab = tab;
      _error = null;
    });
    unawaited(_run(reset: true));
  }

  Future<void> _run({required bool reset}) async {
    if (_loading && !reset) return;
    final generation = reset ? ++_generation : _generation;
    final query = _searchController.text.trim();
    if (reset) {
      setState(() {
        _loading = true;
        _error = null;
        _nextOffset = '';
        _requiredStarCount = 0;
        _agreedStarCount = null;
        if (_tab == _DiscoveryTab.channels) {
          _channels = const [];
          _bots = const [];
          _similar = const [];
          _similarTitle = '';
          _similarSourceChatId = null;
          _similarSourceBotUserId = null;
        } else {
          _hits = const [];
        }
      });
    } else {
      setState(() => _loading = true);
    }

    try {
      switch (_tab) {
        case _DiscoveryTab.channels:
          await _loadChannels(query, generation);
        case _DiscoveryTab.posts:
          if (query.isNotEmpty) {
            await _loadPosts(query, generation, reset: reset);
          }
        case _DiscoveryTab.media:
          await _loadMedia(query, generation, reset: reset);
      }
    } catch (error) {
      if (mounted && generation == _generation) {
        setState(() => _error = error.toString());
      }
    }
    if (!mounted || generation != _generation) return;
    setState(() => _loading = false);
  }

  Future<void> _loadChannels(String query, int generation) async {
    if (query.isEmpty) {
      final ids = await _service.recommendedChannelIds();
      final channels = await _hydrateChats(ids, isBot: false);
      if (!mounted || generation != _generation) return;
      _channels = channels;
      _bots = const [];
      return;
    }
    final results = await Future.wait([
      _service.searchChannelIds(query),
      _service.searchBotChatIds(query),
    ]);
    final hydrated = await Future.wait([
      _hydrateChats(results[0], isBot: false),
      _hydrateChats(results[1], isBot: true),
    ]);
    if (!mounted || generation != _generation) return;
    _channels = hydrated[0];
    _bots = hydrated[1];
  }

  Future<List<_DiscoveryPeer>> _hydrateChats(
    Iterable<int> ids, {
    required bool isBot,
  }) async {
    final peers = await Future.wait(
      ids.take(50).map((id) async {
        try {
          final chat = await TdClient.shared.query({
            '@type': 'getChat',
            'chat_id': id,
          });
          final summary = TDParse.chat(chat);
          if (summary == null) return null;
          return _DiscoveryPeer(
            chatId: summary.id,
            title: summary.title,
            photo: summary.photo,
            isBot: isBot,
            botUserId: isBot ? summary.peerUserId : null,
          );
        } catch (_) {
          return null;
        }
      }),
    );
    return peers.whereType<_DiscoveryPeer>().toList();
  }

  Future<List<_DiscoveryPeer>> _hydrateBotUsers(Iterable<int> ids) async {
    final peers = await Future.wait(
      ids.take(50).map((id) async {
        try {
          final user = await TdClient.shared.query({
            '@type': 'getUser',
            'user_id': id,
          });
          return _DiscoveryPeer(
            chatId: 0,
            title: TDParse.userName(user),
            photo: TDParse.smallPhoto(user.obj('profile_photo')),
            isBot: true,
            botUserId: id,
          );
        } catch (_) {
          return null;
        }
      }),
    );
    return peers.whereType<_DiscoveryPeer>().toList();
  }

  Future<void> _showSimilar(_DiscoveryPeer source) async {
    setState(() {
      _loading = true;
      _error = null;
      _similar = const [];
      _similarTitle = 'Similar to ${source.title}';
      _similarSourceChatId = source.isBot ? null : source.chatId;
      _similarSourceBotUserId = source.isBot ? source.botUserId : null;
    });
    try {
      final List<_DiscoveryPeer> peers;
      if (source.isBot && source.botUserId != null) {
        final ids = await _service.similarBotUserIds(source.botUserId!);
        peers = await _hydrateBotUsers(ids);
      } else {
        final ids = await _service.similarChannelIds(source.chatId);
        peers = await _hydrateChats(ids, isBot: false);
      }
      if (!mounted) return;
      setState(() => _similar = peers);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _loadPosts(
    String query,
    int generation, {
    required bool reset,
  }) async {
    final page = await _service.searchPublicPosts(
      query: query,
      offset: reset ? '' : _nextOffset,
      agreedStarCount: reset ? _agreedStarCount : _agreedStarCount ?? 0,
    );
    if (!mounted || generation != _generation) return;
    if (page.requiresStarConfirmation) {
      _requiredStarCount = page.requiredStarCount;
      return;
    }
    if (page.limitsExceeded) {
      _error = 'The public-post search limit has been reached.';
    }
    final hits = await _hydrateMessages(page.messages);
    if (!mounted || generation != _generation) return;
    _hits = reset ? hits : [..._hits, ...hits];
    _nextOffset = page.nextOffset;
  }

  Future<void> _confirmPaidSearch() async {
    final count = _requiredStarCount;
    if (count <= 0) return;
    final confirmed = await confirmDialog(
      context,
      title: 'Paid public search',
      message: 'Telegram requires $count Stars for this search.',
      confirmText: 'Search for $count Stars',
    );
    if (!mounted || !confirmed) return;
    _agreedStarCount = count;
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _requiredStarCount = 0;
      _error = null;
    });
    try {
      await _loadPosts(_searchController.text.trim(), generation, reset: true);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    }
    if (mounted && generation == _generation) {
      setState(() => _loading = false);
    }
  }

  Future<void> _loadMedia(
    String query,
    int generation, {
    required bool reset,
  }) async {
    final page = await _service.searchGlobalMedia(
      query: query,
      filterType: _mediaFilter.apiType,
      offset: reset ? '' : _nextOffset,
    );
    final hits = await _hydrateMessages(page.messages);
    if (!mounted || generation != _generation) return;
    _hits = reset ? hits : [..._hits, ...hits];
    _nextOffset = page.nextOffset;
  }

  Future<List<_DiscoveryHit>> _hydrateMessages(
    Iterable<Map<String, dynamic>> messages,
  ) async {
    final chatCache = <int, _DiscoverySource>{};
    final hits = <_DiscoveryHit>[];
    for (final raw in messages) {
      final chatId = raw.int64('chat_id') ?? 0;
      final message = TDParse.message(raw);
      if (chatId == 0 || message == null) continue;
      var source = chatCache[chatId];
      if (source == null) {
        try {
          final chat = await TdClient.shared.query({
            '@type': 'getChat',
            'chat_id': chatId,
          });
          source = _DiscoverySource(
            title: chat.str('title') ?? 'Public channel',
            photo: TDParse.smallPhoto(chat.obj('photo')),
          );
        } catch (_) {
          source = const _DiscoverySource(title: 'Public channel', photo: null);
        }
        chatCache[chatId] = source;
      }
      hits.add(_DiscoveryHit(chatId: chatId, message: message, source: source));
    }
    return hits;
  }

  Future<void> _openPeer(
    _DiscoveryPeer peer, {
    required bool markSimilar,
  }) async {
    var chatId = peer.chatId;
    if (chatId == 0 && peer.botUserId != null) {
      try {
        final chat = await TdClient.shared.query({
          '@type': 'createPrivateChat',
          'user_id': peer.botUserId,
          'force': false,
        });
        chatId = chat.int64('id') ?? 0;
      } catch (_) {
        return;
      }
    }
    if (chatId == 0 || !mounted) return;
    try {
      final sourceChatId = markSimilar ? _similarSourceChatId : null;
      final sourceBotUserId = markSimilar ? _similarSourceBotUserId : null;
      if (sourceChatId != null) {
        await _service.markSimilarChannelOpened(
          sourceChatId: sourceChatId,
          openedChatId: chatId,
        );
      } else if (sourceBotUserId != null && peer.botUserId != null) {
        await _service.markSimilarBotOpened(
          sourceBotUserId: sourceBotUserId,
          openedBotUserId: peer.botUserId!,
        );
      }
    } catch (_) {}
    if (!mounted) return;
    await pushAppChatRoute(
      context,
      MaterialPageRoute(
        builder: (_) => ChatView(chatId: chatId, title: peer.title),
      ),
    );
  }

  Future<void> _openHit(_DiscoveryHit hit) => pushAppChatRoute(
    context,
    MaterialPageRoute(
      builder: (_) => ChatView(
        chatId: hit.chatId,
        title: hit.source.title,
        initialMessageId: hit.message.id,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: 'Discover',
            onBack: () => Navigator.of(context).pop(),
          ),
          _tabs(),
          _searchField(),
          if (_tab == _DiscoveryTab.media) _mediaFilters(),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _tabs() {
    final c = context.colors;
    return Container(
      height: 46,
      color: c.card,
      child: Row(
        children: [
          for (final tab in _DiscoveryTab.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _selectTab(tab),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Center(
                        child: Text(
                          tab.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: _tab == tab
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: _tab == tab
                                ? AppTheme.brand
                                : c.textSecondary,
                          ),
                        ),
                      ),
                    ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: _tab == tab ? 26 : 0,
                      height: 3,
                      decoration: BoxDecoration(
                        color: AppTheme.brand,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchField() {
    final c = context.colors;
    return Container(
      color: c.card,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: c.searchFill,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            AppIcon(
              HeroAppIcons.magnifyingGlass,
              size: 17,
              color: c.textTertiary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                onChanged: _queryChanged,
                textInputAction: TextInputAction.search,
                style: TextStyle(fontSize: 15, color: c.textPrimary),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  isDense: true,
                  hintText: switch (_tab) {
                    _DiscoveryTab.channels => 'Search channels and bots',
                    _DiscoveryTab.posts => 'Search public posts or #hashtag',
                    _DiscoveryTab.media => 'Search all chats',
                  },
                  hintStyle: TextStyle(fontSize: 15, color: c.textTertiary),
                ),
              ),
            ),
            if (_searchController.text.isNotEmpty)
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  _searchController.clear();
                  _queryChanged('');
                },
                child: AppIcon(
                  HeroAppIcons.circleXmark,
                  size: 18,
                  color: c.textTertiary,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _mediaFilters() {
    final c = context.colors;
    return Container(
      height: 46,
      color: c.card,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(14, 5, 14, 7),
        itemCount: _GlobalMediaFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final filter = _GlobalMediaFilter.values[index];
          final selected = filter == _mediaFilter;
          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (selected) return;
              setState(() => _mediaFilter = filter);
              unawaited(_run(reset: true));
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 13),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected
                    ? AppTheme.brand.withValues(alpha: 0.14)
                    : c.groupedBackground,
                borderRadius: BorderRadius.circular(17),
                border: Border.all(
                  color: selected ? AppTheme.brand : c.divider,
                ),
              ),
              child: Text(
                filter.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected ? AppTheme.brand : c.textSecondary,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _content() {
    if (_loading &&
        ((_tab == _DiscoveryTab.channels &&
                _channels.isEmpty &&
                _bots.isEmpty) ||
            (_tab != _DiscoveryTab.channels && _hits.isEmpty))) {
      return const Center(child: AppActivityIndicator());
    }
    if (_error != null &&
        (_tab == _DiscoveryTab.channels
            ? _channels.isEmpty && _bots.isEmpty
            : _hits.isEmpty)) {
      return _status(HeroAppIcons.triangleExclamation, 'Search failed');
    }
    return switch (_tab) {
      _DiscoveryTab.channels => _channelContent(),
      _DiscoveryTab.posts => _messageContent(publicPosts: true),
      _DiscoveryTab.media => _messageContent(publicPosts: false),
    };
  }

  Widget _channelContent() {
    final searching = _searchController.text.trim().isNotEmpty;
    if (_channels.isEmpty && _bots.isEmpty) {
      return _status(
        HeroAppIcons.towerBroadcast,
        searching ? 'No public channels or bots found' : 'No recommendations',
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 28),
      children: [
        if (_channels.isNotEmpty)
          _peerSection(
            searching ? 'Public channels' : 'Recommended channels',
            _channels,
          ),
        if (_bots.isNotEmpty) ...[
          const SizedBox(height: 14),
          _peerSection('Bots', _bots),
        ],
        if (_similarTitle.isNotEmpty) ...[
          const SizedBox(height: 14),
          _peerSection(_similarTitle, _similar, tracksSimilarOpen: true),
        ],
      ],
    );
  }

  Widget _peerSection(
    String title,
    List<_DiscoveryPeer> peers, {
    bool tracksSimilarOpen = false,
  }) {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 7),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: c.textSecondary,
              ),
            ),
          ),
          if (peers.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Text(
                _loading ? 'Loading…' : 'No similar results',
                style: TextStyle(fontSize: 14, color: c.textTertiary),
              ),
            ),
          for (var index = 0; index < peers.length; index++) ...[
            if (index > 0) Divider(height: 1, indent: 66, color: c.divider),
            _peerRow(peers[index], tracksSimilarOpen: tracksSimilarOpen),
          ],
        ],
      ),
    );
  }

  Widget _peerRow(_DiscoveryPeer peer, {required bool tracksSimilarOpen}) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openPeer(peer, markSimilar: tracksSimilarOpen),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 9, 8, 9),
        child: Row(
          children: [
            PhotoAvatar(
              title: peer.title,
              photo: peer.photo,
              size: 44,
              square: !peer.isBot,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                peer.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: c.textPrimary,
                ),
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showSimilar(peer),
              child: SizedBox(
                width: 44,
                height: 42,
                child: Center(
                  child: AppIcon(
                    HeroAppIcons.objectGroup,
                    size: 19,
                    color: AppTheme.brand,
                  ),
                ),
              ),
            ),
            AppIcon(HeroAppIcons.chevronRight, size: 15, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _messageContent({required bool publicPosts}) {
    final query = _searchController.text.trim();
    if (publicPosts && query.isEmpty) {
      return _status(
        HeroAppIcons.magnifyingGlass,
        'Search public posts by text, #hashtag, or cashtag',
      );
    }
    if (_requiredStarCount > 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppIcon(HeroAppIcons.solidStar, size: 38),
              const SizedBox(height: 12),
              Text(
                'This search costs $_requiredStarCount Telegram Stars.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  color: context.colors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _confirmPaidSearch,
                child: Container(
                  height: 40,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppTheme.brand,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }
    if (_hits.isEmpty) {
      return _status(
        publicPosts ? HeroAppIcons.message : _mediaFilter.icon,
        publicPosts ? 'No public posts found' : 'No matching media found',
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: _hits.length + (_nextOffset.isNotEmpty ? 1 : 0),
      separatorBuilder: (_, _) =>
          Divider(height: 1, indent: 70, color: context.colors.divider),
      itemBuilder: (context, index) {
        if (index == _hits.length) {
          return _loadMoreButton();
        }
        return _messageRow(_hits[index]);
      },
    );
  }

  Widget _messageRow(_DiscoveryHit hit) {
    final c = context.colors;
    final text = hit.message.text.trim();
    final fallback = (hit.message.contentType ?? 'message').replaceFirst(
      'message',
      '',
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openHit(hit),
      child: Container(
        color: c.card,
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 10),
        child: Row(
          children: [
            PhotoAvatar(
              title: hit.source.title,
              photo: hit.source.photo,
              size: 44,
              square: true,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          hit.source.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                      ),
                      Text(
                        DateText.listLabel(hit.message.date),
                        style: TextStyle(fontSize: 12, color: c.textTertiary),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    text.isEmpty ? fallback : text.replaceAll('\n', ' '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.3,
                      color: c.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppIcon(_messageIcon(hit.message), size: 19, color: AppTheme.brand),
          ],
        ),
      ),
    );
  }

  AppIconData _messageIcon(ChatMessage message) {
    if (message.video != null) return HeroAppIcons.video;
    if (message.image != null) return HeroAppIcons.image;
    if (message.music != null) return HeroAppIcons.music;
    if (message.voice != null) return HeroAppIcons.microphone;
    if (message.document != null) return HeroAppIcons.file;
    if (message.poll != null) return HeroAppIcons.listCheck;
    if (message.linkPreview != null) return HeroAppIcons.link;
    return HeroAppIcons.message;
  }

  Widget _loadMoreButton() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _loading ? null : () => _run(reset: false),
      child: Container(
        height: 54,
        color: context.colors.card,
        alignment: Alignment.center,
        child: _loading
            ? const AppActivityIndicator(size: 20)
            : Text(
                'Load more',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.brand,
                ),
              ),
      ),
    );
  }

  Widget _status(AppIconData icon, String text) {
    final c = context.colors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon(icon, size: 38, color: c.textTertiary),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

enum _DiscoveryTab {
  channels('Channels'),
  posts('Public posts'),
  media('Global media');

  const _DiscoveryTab(this.label);
  final String label;
}

enum _GlobalMediaFilter {
  photoAndVideo(
    'Photos & videos',
    'searchMessagesFilterPhotoAndVideo',
    HeroAppIcons.image,
  ),
  photo('Photos', 'searchMessagesFilterPhoto', HeroAppIcons.image),
  video('Videos', 'searchMessagesFilterVideo', HeroAppIcons.video),
  animation('GIFs', 'searchMessagesFilterAnimation', HeroAppIcons.gif),
  document('Files', 'searchMessagesFilterDocument', HeroAppIcons.file),
  audio('Music', 'searchMessagesFilterAudio', HeroAppIcons.music),
  link('Links', 'searchMessagesFilterUrl', HeroAppIcons.link),
  voice('Voice', 'searchMessagesFilterVoiceNote', HeroAppIcons.microphone),
  videoNote('Video notes', 'searchMessagesFilterVideoNote', HeroAppIcons.video),
  poll('Polls', 'searchMessagesFilterPoll', HeroAppIcons.listCheck);

  const _GlobalMediaFilter(this.label, this.apiType, this.icon);
  final String label;
  final String apiType;
  final AppIconData icon;
}

class _DiscoveryPeer {
  const _DiscoveryPeer({
    required this.chatId,
    required this.title,
    required this.photo,
    required this.isBot,
    required this.botUserId,
  });

  final int chatId;
  final String title;
  final TdFileRef? photo;
  final bool isBot;
  final int? botUserId;
}

class _DiscoverySource {
  const _DiscoverySource({required this.title, required this.photo});
  final String title;
  final TdFileRef? photo;
}

class _DiscoveryHit {
  const _DiscoveryHit({
    required this.chatId,
    required this.message,
    required this.source,
  });

  final int chatId;
  final ChatMessage message;
  final _DiscoverySource source;
}
