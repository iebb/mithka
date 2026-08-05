import 'package:flutter/widgets.dart';

import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

/// A compact, realistic conversation sample used by appearance pickers.
///
/// The preview deliberately uses local initials instead of remote photos so it
/// remains stable offline and never starts network work while a theme grid is
/// scrolling.
class ChatAppearancePreview extends StatelessWidget {
  const ChatAppearancePreview({
    super.key,
    required this.incomingBubbleColor,
    required this.incomingTextColor,
    required this.outgoingBubbleColor,
    required this.outgoingTextColor,
    required this.incomingMessage,
    required this.outgoingMessage,
    this.incomingName = 'Bob Harris',
    this.outgoingName = 'Jessica',
    this.incomingNameColor,
    this.outgoingNameColor,
    this.senderNameReadabilityMode = SenderNameReadabilityMode.blend,
  });

  final Color incomingBubbleColor;
  final Color incomingTextColor;
  final Color outgoingBubbleColor;
  final Color outgoingTextColor;
  final String incomingMessage;
  final String outgoingMessage;
  final String incomingName;
  final String outgoingName;
  final Color? incomingNameColor;
  final Color? outgoingNameColor;
  final SenderNameReadabilityMode senderNameReadabilityMode;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PreviewMessage(
          name: incomingName,
          message: incomingMessage,
          bubbleColor: incomingBubbleColor,
          textColor: incomingTextColor,
          nameColor: incomingNameColor ?? incomingTextColor,
          readabilityMode: senderNameReadabilityMode,
          outgoing: false,
        ),
        const SizedBox(height: 11),
        _PreviewMessage(
          name: outgoingName,
          message: outgoingMessage,
          bubbleColor: outgoingBubbleColor,
          textColor: outgoingTextColor,
          nameColor: outgoingNameColor ?? outgoingTextColor,
          readabilityMode: senderNameReadabilityMode,
          outgoing: true,
        ),
      ],
    );
  }
}

/// Applies the selected readability treatment behind a sender name.
class SenderNameReadabilityPlate extends StatelessWidget {
  const SenderNameReadabilityPlate({
    super.key,
    required this.mode,
    required this.bubbleColor,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    this.connectedToLeading = false,
  });

  final SenderNameReadabilityMode mode;
  final Color bubbleColor;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool connectedToLeading;

  @override
  Widget build(BuildContext context) {
    if (mode == SenderNameReadabilityMode.none) return child;
    // Blend carries no decoration of its own — it is a colour applied to the
    // name, which senderNameReadabilityColor resolves for the caller.
    if (mode == SenderNameReadabilityMode.blend) {
      return KeyedSubtree(
        key: const ValueKey('senderNameReadabilityBlend'),
        child: child,
      );
    }
    return DecoratedBox(
      key: const ValueKey('senderNameReadabilityPlate'),
      decoration: senderNameReadabilityDecoration(
        bubbleColor,
        connectedToLeading: connectedToLeading,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

/// Renders a role tag and sender name as touching, color-separated pills when
/// the readability background is enabled. The shared component keeps live
/// messages and appearance previews geometrically identical.
class SenderIdentityPills extends StatelessWidget {
  const SenderIdentityPills({
    super.key,
    required this.readabilityMode,
    required this.bubbleColor,
    required this.name,
    required this.nameStyle,
    this.textColor,
    this.role,
    this.roleTitle,
    this.roleAfterName = false,
    this.trailing,
  });

  final SenderNameReadabilityMode readabilityMode;
  final Color bubbleColor;
  final String name;
  final TextStyle nameStyle;

  /// The bubble's own text colour, which the blend mode meets halfway.
  final Color? textColor;
  final MemberRole? role;
  final String? roleTitle;
  final bool roleAfterName;

  /// Sits directly after the name, before any trailing role tag — an emoji
  /// status belongs to the person, so it reads ahead of their badge.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final resolvedColor = senderNameReadabilityColor(
      mode: readabilityMode,
      senderColor: nameStyle.color ?? const Color(0xFF000000),
      textColor: textColor ?? nameStyle.color ?? const Color(0xFF000000),
    );
    final effectiveNameStyle = nameStyle.copyWith(
      fontWeight: FontWeight.w500,
      color: resolvedColor,
    );
    // The background treatment is one continuous pill — tag, then name joined
    // to it. That geometry only reads as a single object with the tag leading,
    // so it overrides the platform's preference for a trailing tag and desktop
    // matches mobile here.
    final tagAfterName =
        roleAfterName &&
        readabilityMode != SenderNameReadabilityMode.background;
    final connected =
        !tagAfterName &&
        readabilityMode == SenderNameReadabilityMode.background &&
        role != null;
    return Row(
      key: connected ? const ValueKey('connectedSenderIdentityPills') : null,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (role != null && !tagAfterName) ...[
          RoleTag(
            role: role!,
            title: roleTitle,
            connectedToTrailing: connected,
            fontSize: connected ? effectiveNameStyle.fontSize : null,
          ),
          if (!connected) const SizedBox(width: 4),
        ],
        Flexible(
          child: SenderNameReadabilityPlate(
            mode: readabilityMode,
            bubbleColor: bubbleColor,
            connectedToLeading: connected,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: effectiveNameStyle,
            ),
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 3), trailing!],
        if (role != null && tagAfterName) ...[
          const SizedBox(width: 4),
          RoleTag(role: role!, title: roleTitle),
        ],
      ],
    );
  }
}

/// The colour a sender's name renders in under [mode].
///
/// [SenderNameReadabilityMode.blend] meets the bubble's own text colour
/// halfway, which keeps the sender's hue recognisable while holding contrast
/// over a wallpaper — the job a shadow used to do, without the halo.
Color senderNameReadabilityColor({
  required SenderNameReadabilityMode mode,
  required Color senderColor,
  required Color textColor,
}) => mode == SenderNameReadabilityMode.blend
    ? Color.lerp(textColor, senderColor, 0.5) ?? senderColor
    : senderColor;

BoxDecoration senderNameReadabilityDecoration(
  Color bubbleColor, {
  bool connectedToLeading = false,
}) => BoxDecoration(
  color: bubbleColor,
  borderRadius: connectedToLeading
      ? const BorderRadiusDirectional.only(
          topEnd: Radius.circular(8),
          bottomEnd: Radius.circular(8),
        )
      : BorderRadius.circular(AppRadius.control),
  boxShadow: const [
    BoxShadow(color: Color(0x33000000), blurRadius: 5, offset: Offset(0, 2)),
  ],
);

class _PreviewMessage extends StatelessWidget {
  const _PreviewMessage({
    required this.name,
    required this.message,
    required this.bubbleColor,
    required this.textColor,
    required this.nameColor,
    required this.readabilityMode,
    required this.outgoing,
  });

  final String name;
  final String message;
  final Color bubbleColor;
  final Color textColor;
  final Color nameColor;
  final SenderNameReadabilityMode readabilityMode;
  final bool outgoing;

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: outgoing
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        SenderIdentityPills(
          readabilityMode: readabilityMode,
          bubbleColor: bubbleColor,
          textColor: textColor,
          name: name,
          nameStyle: TextStyle(
            color: nameColor,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
          role: readabilityMode == SenderNameReadabilityMode.background
              ? (outgoing ? MemberRole.owner : MemberRole.admin)
              : null,
        ),
        const SizedBox(height: 3),
        Container(
          constraints: const BoxConstraints(maxWidth: 235),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            boxShadow: const [
              BoxShadow(
                color: Color(0x22000000),
                blurRadius: 5,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            message,
            style: TextStyle(color: textColor, fontSize: 14),
          ),
        ),
      ],
    );

    return Row(
      mainAxisAlignment: outgoing
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!outgoing) ...[
          PhotoAvatar(title: name, size: 34),
          const SizedBox(width: 8),
        ],
        Flexible(child: content),
        if (outgoing) ...[
          const SizedBox(width: 8),
          PhotoAvatar(title: name, size: 34),
        ],
      ],
    );
  }
}
