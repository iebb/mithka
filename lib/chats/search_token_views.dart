//
//  search_token_views.dart
//
//  The two things a search field shows about its tokens: the syntax it accepts
//  while nothing is typed, and the chats or people to pick from once a token
//  is. Both searches — the desktop title bar and a single chat — draw them from
//  here so the affordance reads the same wherever it appears.
//

import 'package:flutter/material.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/photo_avatar.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'search_token_suggestions.dart';

/// One token the field understands, offered before anything is typed.
class SearchTokenHint {
  const SearchTokenHint({
    required this.token,
    required this.titleKey,
    required this.icon,
    this.exampleKey,
  });

  final String token;
  final String titleKey;
  final AppIconData icon;

  /// Values the token accepts, for a token whose vocabulary is closed.
  final String? exampleKey;
}

const searchTokenFromHint = SearchTokenHint(
  token: 'from:',
  titleKey: AppStringKeys.searchTokenFromTitle,
  icon: HeroAppIcons.circleUser,
);

const searchTokenInHint = SearchTokenHint(
  token: 'in:',
  titleKey: AppStringKeys.searchTokenInTitle,
  icon: HeroAppIcons.comment,
);

const searchTokenHasHint = SearchTokenHint(
  token: 'has:',
  titleKey: AppStringKeys.searchTokenHasTitle,
  icon: HeroAppIcons.link,
  exampleKey: AppStringKeys.searchTokenHasExample,
);

/// What a field accepts, shown while it is focused and empty.
///
/// A token syntax nobody can see is a token syntax nobody uses, so an empty
/// field spends its space teaching rather than sitting blank.
class SearchTokenHints extends StatelessWidget {
  const SearchTokenHints({
    super.key,
    required this.hints,
    required this.onPick,
  });

  final List<SearchTokenHint> hints;

  /// Receives the token text, so tapping a hint starts it in the field.
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      key: const ValueKey('searchTokenHints'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.xl,
            AppSpacing.lg,
            AppSpacing.xl,
            AppSpacing.sm,
          ),
          child: Text(
            AppStringKeys.searchTokenHintsTitle.l10n(context),
            style: AppTextStyle.footnote(
              c.textTertiary,
              weight: AppTextWeight.semibold,
            ),
          ),
        ),
        for (final hint in hints)
          AppInteractiveSurface(
            key: ValueKey('searchTokenHint-${hint.token}'),
            semanticLabel: hint.titleKey.l10n(context),
            onTap: () => onPick(hint.token),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xl,
                vertical: AppSpacing.md,
              ),
              child: Row(
                children: [
                  AppIcon(hint.icon, size: AppIconSize.lg, color: c.textTertiary),
                  const SizedBox(width: AppSpacing.lg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          hint.titleKey.l10n(context),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.callout(
                            c.textPrimary,
                            weight: AppTextWeight.medium,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: hint.token,
                                style: AppTextStyle.caption(
                                  AppTheme.brand,
                                  weight: AppTextWeight.semibold,
                                ),
                              ),
                              if (hint.exampleKey case final example?)
                                TextSpan(
                                  text: ' ${example.l10n(context)}',
                                  style: AppTextStyle.caption(c.textTertiary),
                                ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Chats or people to pick from while a token is being typed.
class SearchTokenSuggestionList extends StatelessWidget {
  const SearchTokenSuggestionList({
    super.key,
    required this.suggestions,
    required this.onPick,
    this.shrinkWrap = true,
  });

  final List<ChatSearchTokenSuggestion> suggestions;
  final ValueChanged<ChatSearchTokenSuggestion> onPick;
  final bool shrinkWrap;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    if (suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.section,
          vertical: AppSpacing.section,
        ),
        child: Text(
          AppStringKeys.chatsSearchNoResults.l10n(context),
          textAlign: TextAlign.center,
          style: AppTextStyle.footnote(c.textTertiary),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('searchTokenSuggestions'),
      shrinkWrap: shrinkWrap,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      itemCount: suggestions.length,
      itemBuilder: (context, index) {
        final suggestion = suggestions[index];
        return AppInteractiveSurface(
          key: ValueKey('searchTokenSuggestion-${suggestion.id}'),
          semanticLabel: suggestion.title,
          onTap: () => onPick(suggestion),
          child: SizedBox(
            height: 48,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              child: Row(
                children: [
                  PhotoAvatar(
                    title: suggestion.title,
                    photo: suggestion.photo,
                    size: 32,
                    allowAnimation: false,
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          suggestion.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyle.callout(
                            c.textPrimary,
                            weight: AppTextWeight.semibold,
                          ),
                        ),
                        if (suggestion.subtitle case final subtitle?) ...[
                          const SizedBox(height: AppSpacing.xxs),
                          Text(
                            subtitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyle.caption(c.textSecondary),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
