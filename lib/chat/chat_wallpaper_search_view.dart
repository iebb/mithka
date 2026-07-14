import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'chat_wallpaper.dart';

class ChatWallpaperSearchView extends StatefulWidget {
  const ChatWallpaperSearchView({super.key, required this.controller});

  final ChatWallpaperController controller;

  @override
  State<ChatWallpaperSearchView> createState() =>
      _ChatWallpaperSearchViewState();
}

class _ChatWallpaperSearchViewState extends State<ChatWallpaperSearchView> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();
  final _scrollController = ScrollController();
  final _results = <ChatWallpaperSearchResult>[];
  Timer? _debounce;
  String _nextOffset = '';
  String _activeQuery = '';
  String _provider = 'pic';
  bool _loading = false;
  bool _loadingMore = false;
  bool _failed = false;
  int _generation = 0;
  String? _downloadingId;

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onQueryChanged);
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _textController.removeListener(_onQueryChanged);
    _textController.dispose();
    _focusNode.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    _debounce?.cancel();
    final query = _textController.text.trim();
    if (query.isEmpty) {
      _generation++;
      setState(() {
        _activeQuery = '';
        _results.clear();
        _nextOffset = '';
        _failed = false;
        _loading = false;
      });
      return;
    }
    setState(() {});
    _debounce = Timer(const Duration(milliseconds: 350), () => _search(query));
  }

  void _onScroll() {
    if (!_scrollController.hasClients ||
        _scrollController.position.extentAfter > 480 ||
        _nextOffset.isEmpty ||
        _loading ||
        _loadingMore) {
      return;
    }
    unawaited(_search(_activeQuery, loadMore: true));
  }

  Future<void> _search(String query, {bool loadMore = false}) async {
    if (query.isEmpty) return;
    final generation = loadMore ? _generation : ++_generation;
    setState(() {
      if (loadMore) {
        _loadingMore = true;
      } else {
        _activeQuery = query;
        _loading = true;
        _failed = false;
        _nextOffset = '';
        _results.clear();
      }
    });
    try {
      final page = await widget.controller.searchBackgroundImages(
        query,
        offset: loadMore ? _nextOffset : '',
      );
      if (!mounted || generation != _generation || query != _activeQuery) {
        return;
      }
      final existing = _results.map((item) => item.id).toSet();
      setState(() {
        _provider = page.providerUsername;
        for (final result in page.results) {
          if (existing.add(result.id)) _results.add(result);
        }
        _nextOffset = page.nextOffset;
        _loading = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _failed = true;
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  Future<void> _select(ChatWallpaperSearchResult result) async {
    if (_downloadingId != null) return;
    setState(() => _downloadingId = result.id);
    try {
      final path = await widget.controller.downloadSearchResult(result);
      if (!mounted) return;
      if (path == null || path.isEmpty) {
        setState(() => _downloadingId = null);
        return;
      }
      Navigator.of(context).pop(ChatWallpaper.image(path));
    } catch (_) {
      if (mounted) setState(() => _downloadingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.chatWallpaperSearchTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 9),
            child: _searchField(),
          ),
          Expanded(child: _body()),
          if (_activeQuery.isNotEmpty)
            SafeArea(
              top: false,
              minimum: const EdgeInsets.fromLTRB(16, 6, 16, 10),
              child: Text(
                context.l10n.t(AppStringKeys.chatWallpaperSearchPowered, {
                  'value1': '@$_provider',
                }),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: c.textTertiary),
              ),
            ),
        ],
      ),
    );
  }

  Widget _searchField() {
    final c = context.colors;
    return Container(
      height: 42,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: c.searchFill,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          AppIcon(
            HeroAppIcons.magnifyingGlass,
            size: 18,
            color: c.textTertiary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: EditableText(
              controller: _textController,
              focusNode: _focusNode,
              style: TextStyle(fontSize: 16, color: c.textPrimary),
              cursorColor: c.linkBlue,
              backgroundCursorColor: c.textTertiary,
              textInputAction: TextInputAction.search,
              onSubmitted: (value) => _search(value.trim()),
              selectionColor: c.linkBlue.withValues(alpha: 0.25),
            ),
          ),
          if (_textController.text.isNotEmpty)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _textController.clear,
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: AppIcon(
                  HeroAppIcons.solidCircleXmark,
                  size: 17,
                  color: c.textTertiary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _body() {
    final c = context.colors;
    if (_activeQuery.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(HeroAppIcons.images, size: 42, color: c.textTertiary),
              const SizedBox(height: 12),
              Text(
                AppStringKeys.chatWallpaperSearchHint.l10n(context),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, color: c.textSecondary),
              ),
            ],
          ),
        ),
      );
    }
    if (_loading) return const Center(child: _WallpaperSearchSpinner());
    if (_failed && _results.isEmpty) {
      return Center(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _search(_activeQuery),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              AppStringKeys.chatWallpaperSearchFailed.l10n(context),
              style: TextStyle(fontSize: 14, color: c.linkBlue),
            ),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          AppStringKeys.chatWallpaperSearchEmpty.l10n(context),
          style: TextStyle(fontSize: 14, color: c.textSecondary),
        ),
      );
    }
    return GridView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 4,
        mainAxisSpacing: 4,
        childAspectRatio: 0.72,
      ),
      itemCount: _results.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _results.length) {
          return const Center(child: _WallpaperSearchSpinner());
        }
        final result = _results[index];
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _select(result),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(9),
            child: Stack(
              fit: StackFit.expand,
              children: [
                ColoredBox(color: c.panelBackground),
                TDImage(photo: result.preview, cornerRadius: 0),
                if (_downloadingId == result.id)
                  const ColoredBox(
                    color: Color(0x66000000),
                    child: Center(child: _WallpaperSearchSpinner()),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _WallpaperSearchSpinner extends StatefulWidget {
  const _WallpaperSearchSpinner();

  @override
  State<_WallpaperSearchSpinner> createState() =>
      _WallpaperSearchSpinnerState();
}

class _WallpaperSearchSpinnerState extends State<_WallpaperSearchSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RotationTransition(
      turns: _controller,
      child: AppIcon(
        HeroAppIcons.circleNotch,
        size: 22,
        color: context.colors.linkBlue,
      ),
    );
  }
}
