//
//  desktop_chat_context_pane.dart
//
//  Lightweight group context for wide chat layouts. Full chat settings live
//  in their own surface; this pane contains only the current announcement and
//  a locally searchable member list.
//

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_motion.dart';
import '../theme/app_theme.dart';
import 'chat_info_view.dart';

/// Read-only group context intended for the trailing pane in a wide chat.
///
/// By default the pane owns and loads its [ChatInfoViewModel]. Tests and
/// specialized owners can inject [viewModel]. The pane never mutates group
/// state; member search is applied only to the already loaded local list.
class DesktopChatContextPane extends StatefulWidget {
  const DesktopChatContextPane({
    super.key,
    required this.chatId,
    required this.title,
    this.onOpenAnnouncement,
    this.onOpenMembers,
    this.onOpenMember,
    this.viewModel,
  });

  final int chatId;
  final String title;
  final VoidCallback? onOpenAnnouncement;
  final VoidCallback? onOpenMembers;
  final ValueChanged<ChatMember>? onOpenMember;

  /// Tests and specialized owners may inject an already-loaded model. Normal
  /// integration should omit this so the pane owns the read-only model load.
  @visibleForTesting
  final ChatInfoViewModel? viewModel;

  @override
  State<DesktopChatContextPane> createState() => _DesktopChatContextPaneState();
}

class _DesktopChatContextPaneState extends State<DesktopChatContextPane> {
  late ChatInfoViewModel _viewModel;
  late bool _ownsViewModel;

  @override
  void initState() {
    super.initState();
    _installViewModel();
  }

  @override
  void didUpdateWidget(DesktopChatContextPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId == widget.chatId &&
        oldWidget.title == widget.title &&
        identical(oldWidget.viewModel, widget.viewModel)) {
      return;
    }
    if (_ownsViewModel) _viewModel.dispose();
    _installViewModel();
  }

  void _installViewModel() {
    _ownsViewModel = widget.viewModel == null;
    _viewModel =
        widget.viewModel ??
        ChatInfoViewModel(chatId: widget.chatId, title: widget.title);
    if (_ownsViewModel) _viewModel.load();
  }

  void _openAnnouncement() {
    final callback = widget.onOpenAnnouncement;
    if (callback != null) {
      callback();
      return;
    }
    Navigator.of(context).push<void>(
      AppPageRoute<void>(
        pageBuilder: (_, _, _) => GroupAnnouncementView(
          announcement: _viewModel.description,
          entities: _viewModel.descriptionEntities,
        ),
      ),
    );
  }

  @override
  void dispose() {
    if (_ownsViewModel) _viewModel.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _viewModel,
    builder: (context, _) {
      if (!_viewModel.isGroup) return const SizedBox.shrink();
      return _DesktopChatContextPaneBody(
        viewModel: _viewModel,
        onOpenAnnouncement: _openAnnouncement,
        onOpenMembers: widget.onOpenMembers,
        onOpenMember: widget.onOpenMember,
      );
    },
  );
}

class _DesktopChatContextPaneBody extends StatelessWidget {
  const _DesktopChatContextPaneBody({
    required this.viewModel,
    required this.onOpenAnnouncement,
    required this.onOpenMembers,
    required this.onOpenMember,
  });

  final ChatInfoViewModel viewModel;
  final VoidCallback onOpenAnnouncement;
  final VoidCallback? onOpenMembers;
  final ValueChanged<ChatMember>? onOpenMember;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return ColoredBox(
      key: const ValueKey('desktopChatContextPane'),
      color: c.panelBackground,
      child: Column(
        children: [
          _AnnouncementSection(
            announcement: viewModel.description,
            onTap: onOpenAnnouncement,
          ),
          Divider(height: 1, thickness: 1, color: c.divider),
          Expanded(
            child: _MemberSection(
              memberCount: viewModel.memberCount,
              members: viewModel.members,
              onOpenMembers: onOpenMembers,
              onOpenMember: onOpenMember,
            ),
          ),
        ],
      ),
    );
  }
}

class _AnnouncementSection extends StatelessWidget {
  const _AnnouncementSection({required this.announcement, required this.onTap});

  final String announcement;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final empty = announcement.trim().isEmpty;
    return AppInteractiveSurface(
      key: const ValueKey('desktopChatContextAnnouncement'),
      semanticLabel: AppStringKeys.chatInfoGroupAnnouncement.l10n(context),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppStringKeys.chatInfoGroupAnnouncement.l10n(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyle.callout(
                      c.textPrimary,
                      weight: AppTextWeight.semibold,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                AppIcon(
                  HeroAppIcons.chevronRight,
                  size: AppIconSize.md,
                  color: c.textTertiary,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              empty
                  ? AppStringKeys.chatInfoGroupAnnouncementEmpty.l10n(context)
                  : announcement,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyle.caption(
                empty ? c.textTertiary : c.textSecondary,
              ).copyWith(height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

class _MemberSection extends StatefulWidget {
  const _MemberSection({
    required this.memberCount,
    required this.members,
    required this.onOpenMembers,
    required this.onOpenMember,
  });

  final int memberCount;
  final List<ChatMember> members;
  final VoidCallback? onOpenMembers;
  final ValueChanged<ChatMember>? onOpenMember;

  @override
  State<_MemberSection> createState() => _MemberSectionState();
}

class _MemberSectionState extends State<_MemberSection> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_searchChanged);
  }

  void _searchChanged() => setState(() {});

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _searchController.clear();
    _searchFocus.unfocus();
    setState(() => _searching = false);
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_searchChanged)
      ..dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final resolvedCount = widget.memberCount > 0
        ? widget.memberCount
        : widget.members.length;
    final query = _searchController.text.trim().toLowerCase();
    final shownMembers = query.isEmpty
        ? widget.members
        : widget.members
              .where((member) => member.name.toLowerCase().contains(query))
              .toList(growable: false);
    return Column(
      key: const ValueKey('desktopChatContextMembers'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 40,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: _searching
                ? _MemberSearchField(
                    controller: _searchController,
                    focusNode: _searchFocus,
                    onClose: _closeSearch,
                  )
                : Row(
                    children: [
                      Expanded(
                        child: AppInteractiveSurface(
                          key: const ValueKey(
                            'desktopChatContextMembersHeader',
                          ),
                          onTap: widget.onOpenMembers,
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              '${AppStringKeys.chatInfoGroupMembers.l10n(context)} '
                              '$resolvedCount',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyle.callout(
                                c.textPrimary,
                                weight: AppTextWeight.semibold,
                              ),
                            ),
                          ),
                        ),
                      ),
                      _PaneIconAction(
                        key: const ValueKey(
                          'desktopChatContextMemberSearchToggle',
                        ),
                        label: AppStringKeys.topicChatSearch.l10n(context),
                        icon: HeroAppIcons.magnifyingGlass,
                        onTap: _openSearch,
                      ),
                    ],
                  ),
          ),
        ),
        Expanded(
          child: shownMembers.isEmpty && query.isNotEmpty
              ? Center(
                  child: Text(
                    AppStringKeys.composerMediaSearchEmpty.l10n(context),
                    style: AppTextStyle.footnote(c.textTertiary),
                  ),
                )
              : ListView.builder(
                  key: const ValueKey('desktopChatContextMemberList'),
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.lg,
                    0,
                    AppSpacing.lg,
                    AppSpacing.lg,
                  ),
                  itemCount: shownMembers.length,
                  itemBuilder: (context, index) {
                    final member = shownMembers[index];
                    return _MemberRow(
                      member: member,
                      onTap: widget.onOpenMember == null
                          ? widget.onOpenMembers
                          : () => widget.onOpenMember!(member),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

class _MemberSearchField extends StatelessWidget {
  const _MemberSearchField({
    required this.controller,
    required this.focusNode,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Row(
      children: [
        AppIcon(
          HeroAppIcons.magnifyingGlass,
          size: AppIconSize.sm,
          color: c.textTertiary,
        ),
        const SizedBox(width: AppSpacing.sm),
        Expanded(
          child: TextField(
            key: const ValueKey('desktopChatContextMemberSearch'),
            controller: controller,
            focusNode: focusNode,
            style: AppTextStyle.footnote(c.textPrimary),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: AppStringKeys.topicChatSearch.l10n(context),
              hintStyle: AppTextStyle.footnote(c.textTertiary),
            ),
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        _PaneIconAction(
          key: const ValueKey('desktopChatContextMemberSearchClose'),
          label: AppStringKeys.countryPickerCancel.l10n(context),
          icon: HeroAppIcons.circleXmark,
          onTap: onClose,
        ),
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({required this.member, required this.onTap});

  final ChatMember member;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      key: ValueKey('desktopChatContextMember-${member.id}'),
      onTap: onTap,
      child: SizedBox(
        height: 36,
        child: Row(
          children: [
            PhotoAvatar(
              title: member.name,
              photo: member.photo,
              size: 24,
              allowAnimation: false,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Text(
                member.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyle.footnote(c.textPrimary),
              ),
            ),
            if (member.role case final role?) ...[
              const SizedBox(width: AppSpacing.sm),
              KeyedSubtree(
                key: ValueKey('desktopChatContextMemberRole-${member.id}'),
                child: RoleTag(
                  role: role,
                  title: member.roleTitle,
                  fontSize: 9,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PaneIconAction extends StatelessWidget {
  const _PaneIconAction({
    super.key,
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final AppIconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return AppInteractiveSurface(
      semanticLabel: label,
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: SizedBox(
        width: 28,
        height: 28,
        child: Center(
          child: AppIcon(icon, size: AppIconSize.sm, color: c.textSecondary),
        ),
      ),
    );
  }
}
