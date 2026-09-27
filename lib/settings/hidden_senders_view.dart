//
//  hidden_senders_view.dart
//
//  The members whose messages are hidden on this device, with where each
//  applies (one group, or all chats) and a Show button to undo it. Opened
//  from Content Filters for every entry, or from a group's info for the
//  entries that affect that group.
//

import 'package:flutter/widgets.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'hidden_sender_store.dart';

class HiddenSendersView extends StatelessWidget {
  const HiddenSendersView({super.key, this.chatId, this.store});

  /// Only the entries that affect this chat; null lists them all.
  final int? chatId;
  final HiddenSenderStore? store;

  @override
  Widget build(BuildContext context) {
    final store = this.store ?? HiddenSenderStore.shared;
    return SettingsPageScaffold(
      title: AppStringKeys.hiddenSendersTitle.l10n(context),
      onBack: () => Navigator.of(context).pop(),
      child: ListenableBuilder(
        listenable: store,
        builder: (context, _) {
          final chatId = this.chatId;
          final entries = chatId == null
              ? store.entries
              : store.entriesFor(chatId);
          return SettingsListView(
            children: [
              if (entries.isEmpty)
                const _EmptyState()
              else
                SettingsCard.rows(
                  rows: [
                    for (final entry in entries)
                      _HiddenSenderRow(
                        key: ValueKey(
                          'hidden-sender-${entry.senderId}-${entry.chatId}',
                        ),
                        entry: entry,
                        onShow: () {
                          store.unhide(entry);
                          showToast(
                            context,
                            AppStrings.t(AppStringKeys.hiddenSendersShown, {
                              'value1': entry.name,
                            }),
                          );
                        },
                      ),
                  ],
                ),
              const SettingsNote(text: AppStringKeys.hiddenSendersNote),
            ],
          );
        },
      ),
    );
  }
}

class _HiddenSenderRow extends StatelessWidget {
  const _HiddenSenderRow({
    super.key,
    required this.entry,
    required this.onShow,
  });

  final HiddenSender entry;
  final VoidCallback onShow;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scope = entry.everywhere
        ? AppStrings.t(AppStringKeys.hiddenSendersEverywhere)
        : (entry.chatTitle?.trim().isNotEmpty ?? false)
        ? entry.chatTitle!.trim()
        : AppStrings.t(AppStringKeys.hideSenderInThisGroup);
    final initial = entry.name.trim().isEmpty
        ? '?'
        : entry.name.trim().characters.first.toUpperCase();
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 56),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: c.searchFill,
                shape: BoxShape.circle,
              ),
              child: Text(
                initial,
                style: TextStyle(
                  fontSize: AppTextSize.callout,
                  fontWeight: AppTextWeight.semibold,
                  color: c.textSecondary,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: AppTextSize.body,
                      fontWeight: AppTextWeight.medium,
                      color: c.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      AppIcon(
                        entry.everywhere
                            ? HeroAppIcons.globe
                            : HeroAppIcons.users,
                        size: 12,
                        color: c.textTertiary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          scope,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: AppTextSize.caption,
                            color: c.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            AppInteractiveSurface(
              key: ValueKey(
                'hidden-sender-show-${entry.senderId}-${entry.chatId}',
              ),
              onTap: onShow,
              isButton: true,
              semanticLabel: AppStrings.t(AppStringKeys.hiddenSendersShow),
              borderRadius: BorderRadius.circular(AppRadius.lg),
              child: Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: c.linkBlue.withValues(alpha: 0.13),
                  borderRadius: BorderRadius.circular(AppRadius.lg),
                ),
                child: Text(
                  AppStrings.t(AppStringKeys.hiddenSendersShow),
                  style: TextStyle(
                    fontSize: AppTextSize.footnote,
                    fontWeight: AppTextWeight.semibold,
                    color: c.linkBlue,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 16),
      child: Column(
        children: [
          AppIcon(HeroAppIcons.eyeSlash, size: 30, color: c.textTertiary),
          const SizedBox(height: 10),
          Text(
            AppStrings.t(AppStringKeys.hiddenSendersEmpty),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: AppTextSize.callout,
              color: c.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
