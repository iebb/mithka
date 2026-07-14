import 'package:flutter/widgets.dart';

/// Dismisses the keyboard when a pointer lands outside the focused text field.
///
/// Flutter groups text fields, selection handles, and text-selection toolbars
/// in a [TextFieldTapRegion]. Overriding the framework's outside-tap intent
/// preserves that grouping, so system actions can run before focus changes.
class AppKeyboardDismissOnTap extends StatelessWidget {
  const AppKeyboardDismissOnTap({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Actions(
      actions: <Type, Action<Intent>>{
        EditableTextTapOutsideIntent:
            CallbackAction<EditableTextTapOutsideIntent>(
              onInvoke: (intent) {
                intent.focusNode.unfocus();
                return null;
              },
            ),
      },
      child: child,
    );
  }
}
