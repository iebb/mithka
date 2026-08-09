import 'package:flutter/material.dart';

import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../l10n/app_localizations.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

/// Rich transcript presentation for a group being added to a community.
class ChatCommunityServiceCard extends StatelessWidget {
  const ChatCommunityServiceCard({
    super.key,
    required this.preview,
    required this.label,
    this.onView,
  });

  final MessageCommunityPreview preview;
  final String label;
  final VoidCallback? onView;

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final title = preview.name.isEmpty
        ? AppStringKeys.communityTitle.l10n(context)
        : preview.name;
    final view = onView != null && preview.id != 0 ? onView : null;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.sm,
      ),
      child: Center(
        child: Container(
          key: const ValueKey('chat-community-service-card'),
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 336),
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
          decoration: BoxDecoration(
            color: colors.bubbleIncoming,
            borderRadius: BorderRadius.circular(AppRadius.xl),
            border: Border.all(color: colors.divider, width: 0.5),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.08),
                blurRadius: 18,
                offset: const Offset(0, 7),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              PhotoAvatar(
                key: const ValueKey('chat-community-service-avatar'),
                title: title,
                photo: preview.photo,
                size: 88,
                square: true,
                allowAnimation: false,
              ),
              const SizedBox(height: 18),
              Text(
                label,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: colors.bubbleIncomingText,
                  fontSize: AppTextSize.body,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (view != null) ...[
                const SizedBox(height: 18),
                AppInteractiveSurface(
                  key: const ValueKey('chat-community-service-view'),
                  semanticLabel: AppStringKeys.communityViewAction.l10n(
                    context,
                  ),
                  onTap: view,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  child: Container(
                    constraints: const BoxConstraints(
                      minWidth: 112,
                      minHeight: 42,
                    ),
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 22),
                    decoration: BoxDecoration(
                      color: colors.accentButton,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                    ),
                    child: Text(
                      AppStringKeys.communityViewAction.l10n(context),
                      style: TextStyle(
                        color: colors.accentButtonText,
                        fontSize: AppTextSize.body,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
