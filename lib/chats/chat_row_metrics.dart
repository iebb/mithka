import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme/app_theme.dart';
import '../theme/content_size.dart';

/// Carries the actual list pane width to both rows and extent calculations.
/// Actual entry metrics drive both row layout and cumulative scroll targets.
class ChatRowWidth extends InheritedWidget {
  const ChatRowWidth({super.key, required this.width, required super.child});
  final double width;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatRowWidth>()?.width ??
      MediaQuery.sizeOf(context).width;

  @override
  bool updateShouldNotify(ChatRowWidth oldWidget) => width != oldWidget.width;
}

class ChatRowMetrics {
  const ChatRowMetrics({
    required this.avatar,
    required this.extent,
    required this.timestampWidth,
    required this.timeBelow,
  });
  final double avatar;
  final double extent;
  final double timestampWidth;
  final bool timeBelow;

  static ChatRowMetrics resolve(
    BuildContext context, {
    bool folderTags = false,
    bool splitPreview = false,
    bool previewHasSender = false,
    double? width,
    String timestamp = '',
    int mentions = 0,
    int reactions = 0,
    bool pinned = false,
    bool muted = false,
    double trailingWidth = 0,
    double titleAccessoryWidth = 0,
  }) {
    final data = ContentSizeScope.of(context);
    final scale = data.appScale;
    final base = DefaultTextStyle.of(context).style;
    Size measure(
      String text,
      double size, {
      double? height,
      FontWeight? weight,
      TextScaler? textScaler,
    }) {
      final painter = TextPainter(
        text: TextSpan(
          text: text,
          style: base.copyWith(
            fontSize: textScaler == null
                ? data.systemTextScaler.scale(size * scale)
                : size,
            height: height,
            fontWeight: weight,
          ),
        ),
        textDirection: Directionality.of(context),
        textScaler: textScaler ?? TextScaler.noScaling,
        maxLines: 1,
      )..layout();
      final result = painter.size;
      painter.dispose();
      return result;
    }

    final calibratedTouch =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android);
    final avatar =
        AppMetric.chatListAvatarSize() *
        (calibratedTouch ? math.max(scale, 1.0) : scale);
    final time = measure(timestamp, AppTextSize.chatListTimestamp());
    final available =
        (width ?? ChatRowWidth.of(context)) -
        AppMetric.chatRowHorizontalInset() * 2 -
        avatar -
        AppSpacing.lg;
    Size counter(int count) => measure(
      count > 99 ? '99+' : '$count',
      10,
      height: 1,
      weight: AppTextWeight.semibold,
    );
    final accessories = <Size>[
      if (mentions > 0)
        Size(
          counter(mentions).width + 21,
          math.max(18.0, counter(mentions).height),
        ),
      if (reactions > 0)
        Size(
          counter(reactions).width + 21,
          math.max(18.0, counter(reactions).height),
        ),
      if (pinned) const Size(13, 13),
      if (muted) const Size(13, 13),
      if (trailingWidth > 0) Size(trailingWidth, trailingWidth),
    ];
    final accessoryWidth =
        accessories.fold<double>(0, (sum, item) => sum + item.width) +
        math.max(0, accessories.length - 1) * 4;
    final timeBelow =
        available -
            math.max(time.width, accessoryWidth) -
            8 -
            titleAccessoryWidth <
        80;
    double accessoryHeight = 0;
    if (timeBelow) {
      double lineWidth = 0;
      double lineHeight = 0;
      for (final item in accessories) {
        final itemHeight = item.height;
        final itemWidth = item.width;
        if (lineWidth > 0 && lineWidth + 4 + itemWidth > available) {
          if (accessories.isNotEmpty) accessoryHeight += lineHeight + 4;
          lineWidth = 0;
          lineHeight = 0;
        }
        lineWidth += (lineWidth > 0 ? 4 : 0) + itemWidth;
        lineHeight = math.max(lineHeight, itemHeight);
      }
      if (accessories.isNotEmpty) accessoryHeight += lineHeight + 4;
    }
    final title = measure('\u56FDAg', AppTextSize.chatListTitle()).height;
    final preview = splitPreview
        ? measure(
            '\u56FDAg',
            previewHasSender
                ? math.max(
                    AppTextSize.chatRowPreviewMessageSize(scale),
                    AppTextSize.chatRowPreviewSenderSize(scale),
                  )
                : AppTextSize.chatRowPreviewMessageSize(scale),
            textScaler: data.systemTextScaler,
          ).height
        : measure(
            '\u56FDAg',
            AppTextSize.chatListPreview(),
            textScaler: ContentSizeScope.chatListPreviewScalerOf(context),
          ).height;
    final tags = folderTags
        ? data.systemTextScaler.scale(AppTextSize.chatListFolderTag() * scale) *
                  1.35 +
              2
        : 0.0;
    final stack =
        title +
        (splitPreview ? AppMetric.chatRowPreviewGap() : AppSpacing.xs) +
        preview +
        tags +
        (timeBelow
            ? (timestamp.isEmpty ? 0 : time.height + 2) + accessoryHeight
            : 0);
    return ChatRowMetrics(
      avatar: avatar,
      extent: [
        AppMetric.chatListRowHeight() * scale,
        if (calibratedTouch) 68.0,
        // Touch rows keep 8pt above and below a scaled avatar. Do not
        // derive this inset from the new 72pt base (that would add 24pt).
        avatar +
            (calibratedTouch
                ? 16.0
                : AppMetric.chatListRowHeight() -
                      AppMetric.chatListAvatarSize()),
        stack + 16,
        if (!calibratedTouch) 44.0,
      ].reduce(math.max),
      timestampWidth: time.width,
      timeBelow: timeBelow,
    );
  }
}

/// The text column of a chat-list row: the title line with the time on its
/// trailing edge, the body (preview, folder tags) under it, and the pin /
/// mute / unread-activity indicators in the bottom trailing corner.
///
/// The title and the time form one baseline-aligned line, so the time shares
/// the name's alphabetic baseline at every content and OS text size. The title
/// line and body are centred as one stack in the row, exactly the stack
/// [ChatRowMetrics.resolve] measures (title line + body), while the indicators
/// keep a fixed inset from the row's bottom edge.
///
/// Non-text accessories in [title] (lock, status emoji, badges) should be
/// wrapped in [IgnoreBaseline] so the time follows the name rather than an
/// icon glyph's baseline.
class ChatRowTextColumn extends StatelessWidget {
  const ChatRowTextColumn({
    super.key,
    required this.title,
    required this.body,
    this.time,
    this.timeWidth = 0,
    this.indicators,
  });

  /// The name line; it gets whatever the time leaves of the width.
  final Widget title;

  /// Everything under the title line, including its leading gap.
  final Widget body;

  /// Trailing time on the title's baseline; null when it is not drawn there.
  final Widget? time;

  /// Measured width of [time] ([ChatRowMetrics.timestampWidth]); the body
  /// keeps that much clear under the time, as the old time column did.
  final double timeWidth;

  /// Pinned to the bottom trailing corner, beside the body.
  final Widget? indicators;

  /// Space between the name or body and the trailing time / indicators.
  static const double trailingGap = 8;

  /// Distance from the row's bottom edge to the indicators.
  static const double indicatorInset = AppSpacing.md + AppSpacing.xxs;

  @override
  Widget build(BuildContext context) {
    final time = this.time;
    final indicators = this.indicators;
    return CustomMultiChildLayout(
      delegate: _ChatRowTextLayout(
        textDirection: Directionality.of(context),
        reserveTrailing: time != null || indicators != null,
        timeWidth: time == null ? 0 : timeWidth,
      ),
      children: [
        LayoutId(
          id: _ChatRowTextSlot.header,
          child: time == null
              ? title
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Expanded(child: title),
                    const SizedBox(width: trailingGap),
                    time,
                  ],
                ),
        ),
        LayoutId(id: _ChatRowTextSlot.body, child: body),
        if (indicators != null)
          LayoutId(id: _ChatRowTextSlot.indicators, child: indicators),
      ],
    );
  }
}

enum _ChatRowTextSlot { header, body, indicators }

class _ChatRowTextLayout extends MultiChildLayoutDelegate {
  _ChatRowTextLayout({
    required this.textDirection,
    required this.reserveTrailing,
    required this.timeWidth,
  });

  final TextDirection textDirection;
  final bool reserveTrailing;
  final double timeWidth;

  @override
  void performLayout(Size size) {
    final width = size.width;
    final rtl = textDirection == TextDirection.rtl;
    final indicators = hasChild(_ChatRowTextSlot.indicators)
        ? layoutChild(
            _ChatRowTextSlot.indicators,
            BoxConstraints(maxWidth: width),
          )
        : null;
    final trailing = reserveTrailing
        ? math.max(timeWidth, indicators?.width ?? 0) +
              ChatRowTextColumn.trailingGap
        : 0.0;
    final header = layoutChild(
      _ChatRowTextSlot.header,
      BoxConstraints.tightFor(width: width),
    );
    final bodyWidth = math.max(0.0, width - trailing);
    final body = layoutChild(
      _ChatRowTextSlot.body,
      BoxConstraints.tightFor(width: bodyWidth),
    );
    final top = math.max(0.0, (size.height - header.height - body.height) / 2);
    positionChild(_ChatRowTextSlot.header, Offset(0, top));
    positionChild(
      _ChatRowTextSlot.body,
      Offset(rtl ? width - bodyWidth : 0, top + header.height),
    );
    if (indicators != null) {
      positionChild(
        _ChatRowTextSlot.indicators,
        Offset(
          rtl ? 0 : width - indicators.width,
          size.height - ChatRowTextColumn.indicatorInset - indicators.height,
        ),
      );
    }
  }

  @override
  bool shouldRelayout(_ChatRowTextLayout oldDelegate) =>
      textDirection != oldDelegate.textDirection ||
      reserveTrailing != oldDelegate.reserveTrailing ||
      timeWidth != oldDelegate.timeWidth;
}

/// Sum real rendered item extents, including only separators actually present.
double chatRowCumulativeOffset(
  Iterable<double> precedingExtents, {
  double leadingExtent = 0,
  double separatorExtent = 0,
}) =>
    leadingExtent +
    precedingExtents.fold<double>(
      0,
      (sum, extent) => sum + extent + separatorExtent,
    );
