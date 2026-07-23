//
//  developer_settings_view.dart
//
//  Hidden diagnostics toggles used while reproducing device-only issues.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app/app_performance_controller.dart';
import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import 'api_credentials_view.dart';

class DeveloperSettingsView extends StatelessWidget {
  const DeveloperSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final performance = context.watch<AppPerformanceController>();
    final snapshot = performance.snapshot;
    final frames = snapshot.frameStats;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.developerModeTitle),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.xl,
                AppSpacing.lg,
                AppSpacing.section,
              ),
              children: [
                SettingsCard(
                  children: [
                    SettingsRow(
                      title: AppStrings.t(AppStringKeys.apiCredentialsTitle),
                      value: AppStrings.t(
                        AppStringKeys.apiCredentialsCustomClientApi,
                      ),
                      leading: AppIcon(
                        HeroAppIcons.cloudArrowDown,
                        size: 21,
                        color: AppTheme.brand,
                      ),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const ApiCredentialsView(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.section),
                SettingsCard(
                  children: [
                    SettingsSwitchRow(
                      title: AppStrings.t(
                        AppStringKeys.developerPerformanceProfiler,
                      ),
                      value: performance.profilingEnabled,
                      onChanged: (value) =>
                          context
                                  .read<AppPerformanceController>()
                                  .profilingEnabled =
                              value,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    AppStrings.t(
                      AppStringKeys.developerPerformanceProfilerDescription,
                    ),
                    style: TextStyle(
                      fontSize: AppTextSize.caption,
                      color: c.textTertiary,
                      height: 1.35,
                    ),
                  ),
                ),
                if (performance.profilingEnabled) ...[
                  const SizedBox(height: AppSpacing.section),
                  SettingsCard(
                    children: [
                      SettingsRow(
                        title: AppStrings.t(
                          AppStringKeys.developerPerformanceProcessMemory,
                        ),
                        value: _formatMiB(snapshot.processRssBytes),
                        leading: AppIcon(
                          HeroAppIcons.networkWired,
                          size: 21,
                          color: AppTheme.brand,
                        ),
                        showChevron: false,
                      ),
                      const InsetDivider(leadingInset: 48),
                      SettingsRow(
                        title: AppStrings.t(
                          AppStringKeys.developerPerformanceImageCache,
                        ),
                        value:
                            '${_formatMiB(snapshot.imageCacheBytes)} · '
                            '${snapshot.imageCacheEntries} / '
                            '${snapshot.liveImageCount}',
                        leading: AppIcon(
                          HeroAppIcons.image,
                          size: 21,
                          color: AppTheme.brand,
                        ),
                        showChevron: false,
                      ),
                      const InsetDivider(leadingInset: 48),
                      SettingsRow(
                        title: AppStrings.t(
                          AppStringKeys.developerPerformanceFrameWork,
                        ),
                        value: frames.sampleCount == 0
                            ? AppStrings.t(
                                AppStringKeys
                                    .developerPerformanceWaitingForFrames,
                              )
                            : '${frames.averageBuildMs.toStringAsFixed(1)} / '
                                  '${frames.averageRasterMs.toStringAsFixed(1)} ms',
                        leading: AppIcon(
                          HeroAppIcons.stopwatch,
                          size: 21,
                          color: AppTheme.brand,
                        ),
                        showChevron: false,
                      ),
                      const InsetDivider(leadingInset: 48),
                      SettingsRow(
                        title: AppStrings.t(
                          AppStringKeys.developerPerformanceSlowFrames,
                        ),
                        value: frames.sampleCount == 0
                            ? '—'
                            : '${frames.slowFrameCount}/${frames.sampleCount} · '
                                  'p95 ${frames.p95TotalMs.toStringAsFixed(1)} ms',
                        leading: AppIcon(
                          HeroAppIcons.triangleExclamation,
                          size: 21,
                          color: AppTheme.brand,
                        ),
                        showChevron: false,
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.section),
                  SettingsCard(
                    children: [
                      SettingsRow(
                        title: AppStrings.t(
                          AppStringKeys.developerPerformanceResetSamples,
                        ),
                        leading: AppIcon(
                          HeroAppIcons.restore,
                          size: 21,
                          color: AppTheme.brand,
                        ),
                        onTap: performance.resetFrameSamples,
                        showChevron: false,
                      ),
                      const InsetDivider(leadingInset: 48),
                      SettingsRow(
                        title: AppStrings.t(
                          AppStringKeys.developerPerformanceTrimCaches,
                        ),
                        leading: AppIcon(
                          HeroAppIcons.trash,
                          size: 21,
                          color: AppTheme.tagRed,
                        ),
                        onTap: performance.trimMemoryCaches,
                        showChevron: false,
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _formatMiB(int bytes) {
  if (bytes <= 0) return '—';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}
