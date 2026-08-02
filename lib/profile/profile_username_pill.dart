import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

typedef ProfileUsernamePillPalette = ({
  Color capFill,
  Color bodyFill,
  Color capInk,
  Color bodyInk,
});

ProfileUsernamePillPalette profileUsernamePillPalette(AppColors colors) {
  final surface = colors.card.withValues(alpha: 1);
  final capFill = colors.linkBlue.withValues(alpha: 1);
  var bodyFill = Color.alphaBlend(capFill.withValues(alpha: 0.24), surface);
  if (!_pillColorsAreDistinct(capFill, bodyFill)) {
    bodyFill = Color.alphaBlend(
      colors.textPrimary.withValues(alpha: 0.12),
      surface,
    );
  }
  if (!_pillColorsAreDistinct(capFill, bodyFill)) {
    bodyFill = Color.alphaBlend(
      colors.textSecondary.withValues(alpha: 0.24),
      surface,
    );
  }
  return (
    capFill: capFill,
    bodyFill: bodyFill,
    capInk: readableForeground(capFill),
    bodyInk: readableForeground(bodyFill),
  );
}

bool _pillColorsAreDistinct(Color a, Color b) {
  final aValue = a.toARGB32();
  final bValue = b.toARGB32();
  final red = ((aValue >> 16) & 0xFF) - ((bValue >> 16) & 0xFF);
  final green = ((aValue >> 8) & 0xFF) - ((bValue >> 8) & 0xFF);
  final blue = (aValue & 0xFF) - (bValue & 0xFF);
  return [red.abs(), green.abs(), blue.abs()].reduce((a, b) => a > b ? a : b) >=
      6;
}

class ProfileUsernamePill extends StatelessWidget {
  const ProfileUsernamePill({super.key, required this.username});

  final String username;

  @override
  Widget build(BuildContext context) {
    final normalized = username.trim().replaceFirst(RegExp(r'^@+'), '');
    final palette = profileUsernamePillPalette(context.colors);
    return Semantics(
      label: '@$normalized',
      container: true,
      child: ExcludeSemantics(
        child: Container(
          key: const ValueKey('profileUsernamePill'),
          constraints: const BoxConstraints(minHeight: 20),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(999)),
          child: Directionality(
            textDirection: TextDirection.ltr,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  key: const ValueKey('profileUsernamePillAt'),
                  color: palette.capFill,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  child: Text(
                    '@',
                    style: TextStyle(
                      color: palette.capInk,
                      fontSize: 13,
                      height: 1.15,
                      fontWeight: context.appFontWeight(AppTextWeight.semibold),
                    ),
                  ),
                ),
                Flexible(
                  child: Container(
                    key: const ValueKey('profileUsernamePillValue'),
                    color: palette.bodyFill,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    child: Text(
                      normalized,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.bodyInk,
                        fontSize: 13,
                        height: 1.15,
                        fontWeight: context.appFontWeight(AppTextWeight.medium),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
