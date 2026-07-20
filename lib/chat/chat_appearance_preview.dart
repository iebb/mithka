import 'package:flutter/widgets.dart';

import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../tdlib/td_models.dart';

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
    this.showSenderNamePlate = false,
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
  final bool showSenderNamePlate;

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
          showNamePlate: showSenderNamePlate,
          outgoing: false,
        ),
        const SizedBox(height: 11),
        _PreviewMessage(
          name: outgoingName,
          message: outgoingMessage,
          bubbleColor: outgoingBubbleColor,
          textColor: outgoingTextColor,
          nameColor: outgoingNameColor ?? outgoingTextColor,
          showNamePlate: showSenderNamePlate,
          outgoing: true,
        ),
      ],
    );
  }
}

/// Adds a bubble-colored plate and soft shadow behind a sender name. Keeping
/// this as a shared widget makes the appearance preview match real messages.
class SenderNameReadabilityPlate extends StatelessWidget {
  const SenderNameReadabilityPlate({
    super.key,
    required this.enabled,
    required this.bubbleColor,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
    this.connectedToLeading = false,
  });

  final bool enabled;
  final Color bubbleColor;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool connectedToLeading;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
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
    required this.enabled,
    required this.bubbleColor,
    required this.name,
    required this.nameStyle,
    this.role,
    this.roleTitle,
  });

  final bool enabled;
  final Color bubbleColor;
  final String name;
  final TextStyle nameStyle;
  final MemberRole? role;
  final String? roleTitle;

  @override
  Widget build(BuildContext context) {
    final connected = enabled && role != null;
    return Row(
      key: connected ? const ValueKey('connectedSenderIdentityPills') : null,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (role != null) ...[
          RoleTag(
            role: role!,
            title: roleTitle,
            connectedToTrailing: connected,
            fontSize: connected ? nameStyle.fontSize : null,
          ),
          if (!connected) const SizedBox(width: 4),
        ],
        Flexible(
          child: SenderNameReadabilityPlate(
            enabled: enabled,
            bubbleColor: bubbleColor,
            connectedToLeading: connected,
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: nameStyle,
            ),
          ),
        ),
      ],
    );
  }
}

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
      : BorderRadius.circular(8),
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
    required this.showNamePlate,
    required this.outgoing,
  });

  final String name;
  final String message;
  final Color bubbleColor;
  final Color textColor;
  final Color nameColor;
  final bool showNamePlate;
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
          enabled: showNamePlate,
          bubbleColor: bubbleColor,
          name: name,
          nameStyle: TextStyle(
            color: nameColor,
            fontSize: 11,
            fontWeight: FontWeight.w700,
            shadows: showNamePlate
                ? null
                : const [Shadow(color: Color(0x66000000), blurRadius: 4)],
          ),
          role: showNamePlate
              ? (outgoing ? MemberRole.owner : MemberRole.admin)
              : null,
        ),
        const SizedBox(height: 3),
        Container(
          constraints: const BoxConstraints(maxWidth: 235),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(15),
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
