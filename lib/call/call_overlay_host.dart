import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import 'call_manager.dart';
import 'call_screen.dart';
import 'group_call_screen.dart';

/// Renders call surfaces above the app navigator so calls remain visible from
/// tab roots, conversations, and every other pushed page.
class GlobalCallOverlayHost extends StatelessWidget {
  const GlobalCallOverlayHost({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<CallManager>(
      builder: (context, calls, _) {
        if (calls.groups.session != null) {
          if (calls.groups.isMinimized) {
            return Stack(
              children: [
                Positioned(
                  top: MediaQuery.paddingOf(context).top + 12,
                  right: 16,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: calls.groups.restore,
                    child: Container(
                      width: 58,
                      height: 58,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF253442),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.55),
                          width: 2,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x55000000),
                            blurRadius: 16,
                            offset: Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const AppIcon(
                        HeroAppIcons.users,
                        size: 26,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ],
            );
          }
          return GroupCallScreen(controller: calls.groups);
        }
        if (calls.call != null) return CallScreen(manager: calls);
        return const SizedBox.shrink();
      },
    );
  }
}
