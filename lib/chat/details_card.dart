//
//  details_card.dart
//
//  The grouped label / value card on the read-only detail sheets (gift,
//  Gram transfer): rows on `card` with inset dividers, each a 96pt label
//  column beside its value, or the label above the value at large text.
//

import 'package:flutter/material.dart';

import '../components/photo_avatar.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

/// The card around [rows], with a divider between each two. Callers leave a
/// row out when its data is missing and the card out when no row is left.
class DetailsCard extends StatelessWidget {
  const DetailsCard({super.key, required this.rows});

  final List<Widget> rows;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = 0; index < rows.length; index++) ...[
            if (index > 0)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.xxl),
                child: Divider(height: 1, color: c.divider),
              ),
            rows[index],
          ],
        ],
      ),
    );
  }
}

/// Builds a row's value for the alignment its layout calls for.
typedef DetailsRowValue = Widget Function(TextAlign align);

/// One label / value row. The value sits right-aligned beside a 96pt label
/// column; when the label would not fit there, or text is scaled to 130 % or
/// more, the label moves above the value instead of being cut.
///
/// With [onTap] the whole row is one button; [trailing] then usually shows
/// what the tap does, at the row's end.
class DetailsRow extends StatelessWidget {
  const DetailsRow({
    super.key,
    required this.label,
    required this.value,
    required this.semanticValue,
    this.trailing,
    this.onTap,
  });

  final String label;
  final DetailsRowValue value;
  final String semanticValue;
  final Widget? trailing;
  final VoidCallback? onTap;

  static const double avatarSize = 22;
  static const double _labelWidth = 96;
  static const double _labelGap = 10;
  static const double _verticalPadding = 13;
  static const double _stackedTextScale = 1.3;

  /// A plain text value.
  static DetailsRowValue textValue(String text, {TextStyle? style}) =>
      (align) => Builder(
        builder: (context) => Text(
          text,
          textAlign: align,
          style: style ?? AppTextStyle.body(context.colors.textPrimary),
        ),
      );

  /// A person or chat: their avatar, then [name]. [avatarTitle] picks the
  /// avatar's initials and colour when it differs from [name].
  static DetailsRowValue partyValue(
    String name,
    TdFileRef? photo, {
    String? avatarTitle,
  }) =>
      (align) => Builder(
        builder: (context) => Row(
          mainAxisAlignment: align == TextAlign.end
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          children: [
            PhotoAvatar(
              title: avatarTitle ?? name,
              photo: photo,
              size: avatarSize,
            ),
            const SizedBox(width: AppSpacing.md),
            Flexible(
              child: Text(
                name,
                textAlign: align,
                style: AppTextStyle.body(context.colors.textPrimary),
              ),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final scaler = MediaQuery.textScalerOf(context);
    final labelStyle = AppTextStyle.body(c.textSecondary);
    final painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: Directionality.of(context),
      textScaler: scaler,
      maxLines: 1,
    )..layout();
    final stacked =
        painter.width > _labelWidth || scaler.scale(1) >= _stackedTextScale;
    painter.dispose();
    final trailing = this.trailing;
    Widget withTrailing(Widget value) => trailing == null
        ? value
        : Row(
            children: [
              Expanded(child: value),
              const SizedBox(width: AppSpacing.md),
              trailing,
            ],
          );
    final Widget content = stacked
        ? Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(label, style: AppTextStyle.footnote(c.textSecondary)),
              const SizedBox(height: AppSpacing.xxs),
              withTrailing(value(TextAlign.start)),
            ],
          )
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: _labelWidth,
                child: Text(label, style: labelStyle),
              ),
              const SizedBox(width: _labelGap),
              Expanded(child: withTrailing(value(TextAlign.end))),
            ],
          );
    final padded = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xxl,
        vertical: _verticalPadding,
      ),
      child: content,
    );
    final onTap = this.onTap;
    return Semantics(
      container: true,
      button: onTap != null ? true : null,
      label: '$label, $semanticValue',
      onTap: onTap,
      excludeSemantics: true,
      child: onTap == null
          ? padded
          : GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTap,
              child: padded,
            ),
    );
  }
}
