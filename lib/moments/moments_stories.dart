part of 'moments_view.dart';

class StoryShelf extends StatelessWidget {
  const StoryShelf({
    super.key,
    required this.model,
    required this.canPublish,
    required this.onCreate,
    required this.onManage,
  });

  final MomentsViewModel model;
  final bool canPublish;
  final VoidCallback onCreate;
  final VoidCallback onManage;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final groups = model.groups;
    final showLoader = model.loading && groups.isEmpty;
    return Container(
      color: c.background,
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(
                  AppStringKeys.momentsStories.l10n(context),
                  style: TextStyle(
                    color: c.textPrimary,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            height: 91,
            // Lazy: the eager children form built a tile per friend with active
            // stories on every rebuild, and paging emits one update per friend.
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: 1 + groups.length + (showLoader ? 1 : 0),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _StoryActionTile(
                    key: const ValueKey('my-story-action'),
                    label: AppStringKeys.storiesMy.l10n(context),
                    icon: HeroAppIcons.inbox,
                    photo: model.selfPhoto,
                    photoTitle: model.selfName,
                    onTap: model.ownGroup == null
                        ? onManage
                        : () => _openStory(context, model.ownGroup!),
                    onBadgeTap: canPublish ? onCreate : null,
                    showBadge: canPublish,
                    prominent: model.ownGroup == null && canPublish,
                  );
                }
                if (i > groups.length) {
                  return const SizedBox(
                    width: 66,
                    child: Center(child: AppActivityIndicator(size: 24)),
                  );
                }
                final group = groups[i - 1];
                return _StoryGroupTile(
                  key: ValueKey('story-group-${group.chatId}'),
                  group: group,
                  onTap: () => _openStory(context, group),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static void _openStory(BuildContext context, StoryGroup group) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        fullscreenDialog: true,
        pageBuilder: (_, _, _) =>
            StoryViewerView(chatId: group.chatId, storyIds: group.storyIds),
      ),
    );
  }
}

class _StoryActionTile extends StatelessWidget {
  const _StoryActionTile({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.prominent = false,
    this.photo,
    this.photoTitle = '',
    this.onBadgeTap,
    this.showBadge = true,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;
  final bool prominent;
  final TdFileRef? photo;
  final String photoTitle;
  final VoidCallback? onBadgeTap;
  final bool showBadge;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              SizedBox(
                width: 62,
                height: 62,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      padding: const EdgeInsets.all(2.5),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: prominent ? AppTheme.brandGradient : null,
                        border: prominent
                            ? null
                            : Border.all(color: c.divider, width: 1.5),
                      ),
                      child: photo != null
                          ? PhotoAvatar(
                              title: photoTitle,
                              photo: photo,
                              size: 57,
                              allowAnimation: false,
                            )
                          : DecoratedBox(
                              decoration: BoxDecoration(
                                color: prominent
                                    ? c.background
                                    : c.groupedBackground,
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: AppIcon(
                                  icon,
                                  size: 25,
                                  color: prominent
                                      ? AppTheme.brand
                                      : c.textSecondary,
                                ),
                              ),
                            ),
                    ),
                    if (showBadge)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: GestureDetector(
                          key: const ValueKey('story-create-badge'),
                          behavior: HitTestBehavior.opaque,
                          onTap: onBadgeTap,
                          child: Container(
                            constraints: const BoxConstraints(
                              minWidth: 21,
                              minHeight: 21,
                            ),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppTheme.brand,
                              borderRadius: BorderRadius.circular(
                                AppRadius.card,
                              ),
                              border: Border.all(color: c.background, width: 2),
                            ),
                            child: const AppIcon(
                              HeroAppIcons.plus,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 7),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(color: c.textSecondary, fontSize: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StoryGroupTile extends StatelessWidget {
  const _StoryGroupTile({super.key, required this.group, required this.onTap});

  final StoryGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      button: true,
      label:
          '${group.name}, ${context.l10n.t(group.hasUnread ? AppStringKeys.storiesCountNew : AppStringKeys.storiesCountViewed, {'value1': group.storyIds.length})}',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: SizedBox(
          width: 76,
          child: Column(
            children: [
              Container(
                width: 62,
                height: 62,
                padding: const EdgeInsets.all(2.5),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: group.hasUnread ? AppTheme.brandGradient : null,
                  border: group.hasUnread
                      ? null
                      : Border.all(color: c.divider, width: 1.5),
                ),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: c.background,
                    shape: BoxShape.circle,
                  ),
                  child: PhotoAvatar(
                    title: group.name,
                    photo: group.photo,
                    size: 53,
                    allowAnimation: false,
                  ),
                ),
              ),
              const SizedBox(height: 7),
              Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: group.hasUnread ? c.textPrimary : c.textSecondary,
                  fontSize: 12,
                  fontWeight: group.hasUnread
                      ? FontWeight.w600
                      : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class StoriesView extends StatefulWidget {
  const StoriesView({super.key, this.showBackButton = true, this.service});

  final bool showBackButton;
  final StoryService? service;

  @override
  State<StoriesView> createState() => _StoriesViewState();
}

class _StoriesViewState extends State<StoriesView> {
  final _model = MomentsViewModel();
  late final StoryService _service = widget.service ?? StoryService();
  bool _canPublish = false;

  Future<void> _loadPublishingPermission() async {
    var allowed = false;
    try {
      allowed = await _service.canPostAnyStory();
    } catch (_) {}
    if (mounted) setState(() => _canPublish = allowed);
  }

  Future<void> _createStory() async {
    if (!_canPublish) return;
    final changed = await Navigator.of(context, rootNavigator: true).push<bool>(
      AppPageRoute<bool>(
        fullscreenDialog: true,
        pageBuilder: (_, _, _) => StoryAuthoringView(service: _service),
      ),
    );
    if (changed == true) _model.refresh();
    await _loadPublishingPermission();
  }

  Future<void> _manageStories() async {
    try {
      final chatId = await _service.savedMessagesChatId();
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              StoryManagementView(chatId: chatId, service: _service),
        ),
      );
      _model.refresh();
    } catch (error) {
      if (mounted) {
        showToast(
          context,
          context.l10n.t(AppStringKeys.storiesOpenFailed, {'value1': error}),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _model.addListener(() {
      if (mounted) setState(() {});
    });
    _model.start();
    unawaited(_loadPublishingPermission());
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Material(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.momentsStories,
            onBack: widget.showBackButton
                ? () => Navigator.of(context).pop()
                : null,
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _model.refresh,
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: AppIcon(
                      HeroAppIcons.arrowsRotate,
                      size: 20,
                      color: AppTheme.brand,
                    ),
                  ),
                ),
                if (_canPublish) ...[
                  const SizedBox(width: 12),
                  GestureDetector(
                    key: const ValueKey('stories-publish-action'),
                    behavior: HitTestBehavior.opaque,
                    onTap: _createStory,
                    child: Padding(
                      padding: const EdgeInsets.all(5),
                      child: AppIcon(
                        HeroAppIcons.plus,
                        size: 22,
                        color: AppTheme.brand,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          Expanded(child: _content()),
        ],
      ),
    );
  }

  Widget _content() {
    final c = context.colors;
    final groups = _model.groups;
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 28),
      children: [
        Row(
          children: [
            if (_canPublish) ...[
              Expanded(
                child: _primaryAction(
                  icon: HeroAppIcons.camera,
                  title: AppStringKeys.storiesNew.l10n(context),
                  subtitle: AppStringKeys.storiesPhotoVideo.l10n(context),
                  onTap: _createStory,
                  prominent: true,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: _primaryAction(
                icon: HeroAppIcons.inbox,
                title: AppStringKeys.storiesMy.l10n(context),
                subtitle: AppStringKeys.storiesProfileArchive.l10n(context),
                onTap: _manageStories,
              ),
            ),
          ],
        ),
        if (_model.ownGroup case final own?) ...[
          const SizedBox(height: 12),
          _ownStoryCard(own),
        ],
        const SizedBox(height: 22),
        Row(
          children: [
            Text(
              AppStringKeys.storiesRecent.l10n(context),
              style: TextStyle(
                color: c.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            if (_model.loading) const AppActivityIndicator(size: 18),
          ],
        ),
        const SizedBox(height: 10),
        if (groups.isEmpty && _model.loading)
          _loadingCard()
        else if (groups.isEmpty)
          _emptyCard()
        else
          for (final group in groups) ...[
            _row(group),
            if (group != groups.last) const SizedBox(height: 8),
          ],
      ],
    );
  }

  Widget _primaryAction({
    required AppIconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool prominent = false,
  }) {
    final c = context.colors;
    return Semantics(
      button: true,
      label: title,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          height: 84,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: prominent ? AppTheme.brandGradient : null,
            color: prominent ? null : c.background,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: prominent ? null : Border.all(color: c.divider),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: prominent
                      ? Colors.white.withValues(alpha: 0.2)
                      : AppTheme.brand.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: AppIcon(
                  icon,
                  size: 22,
                  color: prominent ? Colors.white : AppTheme.brand,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: prominent ? Colors.white : c.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: prominent
                            ? Colors.white.withValues(alpha: 0.78)
                            : c.textSecondary,
                        fontSize: 11,
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

  Widget _ownStoryCard(StoryGroup group) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openGroup(group),
      child: Container(
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppTheme.brand.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(AppRadius.card),
          border: Border.all(color: AppTheme.brand.withValues(alpha: 0.22)),
        ),
        child: Row(
          children: [
            PhotoAvatar(
              title: _model.selfName,
              photo: _model.selfPhoto,
              size: 42,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStringKeys.storiesYourActive.l10n(context),
                    style: TextStyle(
                      color: c.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.t(AppStringKeys.storiesActiveCount, {
                      'value1': group.storyIds.length,
                    }),
                    style: TextStyle(color: c.textSecondary, fontSize: 12),
                  ),
                ],
              ),
            ),
            AppIcon(HeroAppIcons.chevronRight, size: 17, color: c.textTertiary),
          ],
        ),
      ),
    );
  }

  Widget _loadingCard() => Container(
    height: 150,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: context.colors.background,
      borderRadius: BorderRadius.circular(AppRadius.lg),
    ),
    child: const AppActivityIndicator(size: 30),
  );

  Widget _emptyCard() {
    final c = context.colors;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 28, 24, 24),
      decoration: BoxDecoration(
        color: c.background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Column(
        children: [
          Container(
            width: 58,
            height: 58,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppTheme.brand.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: AppIcon(
              HeroAppIcons.images,
              size: 28,
              color: AppTheme.brand,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            AppStringKeys.storiesEmptyTitle.l10n(context),
            style: TextStyle(
              color: c.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            AppStringKeys.storiesEmptyDescription.l10n(context),
            textAlign: TextAlign.center,
            style: TextStyle(
              color: c.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          if (_canPublish) ...[
            const SizedBox(height: 18),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _createStory,
              child: Container(
                height: 42,
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                decoration: BoxDecoration(
                  color: AppTheme.brand,
                  borderRadius: BorderRadius.circular(AppRadius.card),
                ),
                child: Text(
                  AppStringKeys.storiesCreate.l10n(context),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _row(StoryGroup group) {
    final c = context.colors;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _openGroup(group),
      child: Container(
        height: 78,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        foregroundDecoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: c.divider),
        ),
        decoration: BoxDecoration(
          color: c.background,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(2.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: group.hasUnread ? AppTheme.brandGradient : null,
                border: group.hasUnread
                    ? null
                    : Border.all(color: c.divider, width: 1.5),
              ),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: c.background,
                  shape: BoxShape.circle,
                ),
                child: PhotoAvatar(
                  title: group.name,
                  photo: group.photo,
                  allowAnimation: false,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    group.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    group.hasUnread
                        ? context.l10n.t(AppStringKeys.storiesCountNew, {
                            'value1': group.storyIds.length,
                          })
                        : context.l10n.t(AppStringKeys.storiesCountViewed, {
                            'value1': group.storyIds.length,
                          }),
                    style: TextStyle(
                      fontSize: 12,
                      color: group.hasUnread ? AppTheme.brand : c.textSecondary,
                      fontWeight: group.hasUnread
                          ? FontWeight.w600
                          : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  // order is a sort weight with flag bits, not a timestamp.
                  DateText.listLabel(group.date),
                  style: TextStyle(fontSize: 11, color: c.textTertiary),
                ),
                const SizedBox(height: 7),
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: 16,
                  color: c.textTertiary,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _openGroup(StoryGroup group) {
    Navigator.of(context).push(
      AppPageRoute<void>(
        fullscreenDialog: true,
        pageBuilder: (_, _, _) =>
            StoryViewerView(chatId: group.chatId, storyIds: group.storyIds),
      ),
    );
  }
}
