//
//  content_view.dart
//
//  Auth gate: shows the tab bar once TDLib reports ready, otherwise login.
//  Port of the Swift `ContentView` / `SplashView`.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../auth/auth_manager.dart';
import '../auth/login_view.dart';
import '../theme/app_theme.dart';
import 'main_tab_view.dart';

class ContentView extends StatelessWidget {
  const ContentView({super.key});

  @override
  Widget build(BuildContext context) {
    final step = context.watch<AuthManager>().step;
    final Widget child = switch (step) {
      AuthReady() => const MainTabView(),
      AuthInitializing() || AuthLoggingOut() => const SplashView(),
      _ => const LoginView(),
    };
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(key: ValueKey(child.runtimeType), child: child),
    );
  }
}

class SplashView extends StatelessWidget {
  const SplashView({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(gradient: AppTheme.brandGradient),
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Image(
              image: AssetImage('assets/penguin.png'),
              width: AppMetric.splashPenguinSize,
              height: AppMetric.splashPenguinSize,
            ),
            SizedBox(height: AppSpacing.lg + AppSpacing.sm),
            SizedBox(
              width: AppMetric.splashSpinnerSize,
              height: AppMetric.splashSpinnerSize,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                valueColor: AlwaysStoppedAnimation(Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
