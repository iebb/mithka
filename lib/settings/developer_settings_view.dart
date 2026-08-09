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
    final performance = context.watch<AppPerformanceController>();
    final snapshot = performance.snapshot;
    final frames = snapshot.frameStats;
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.developerModeTitle),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          SettingsCard.rows(
            rows: [
              SettingsRow(
                title: AppStrings.t(AppStringKeys.apiCredentialsTitle),
                value: AppStrings.t(
                  AppStringKeys.apiCredentialsCustomClientApi,
                ),
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.cloudArrowDown,
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const ApiCredentialsView()),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.section),
          SettingsCard.rows(
            rows: [
              SettingsSwitchRow(
                title: AppStrings.t(AppStringKeys.developerPerformanceProfiler),
                value: performance.profilingEnabled,
                leading: const SettingsLeadingIcon(
                  icon: HeroAppIcons.stopwatch,
                ),
                onChanged: (value) =>
                    context.read<AppPerformanceController>().profilingEnabled =
                        value,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          SettingsNote(
            text: AppStrings.t(
              AppStringKeys.developerPerformanceProfilerDescription,
            ),
          ),
          if (performance.profilingEnabled) ...[
            const SizedBox(height: AppSpacing.section),
            SettingsCard.rows(
              rows: [
                SettingsRow(
                  title: AppStrings.t(
                    AppStringKeys.developerPerformanceProcessMemory,
                  ),
                  value: _formatMiB(snapshot.processRssBytes),
                  leading: const SettingsLeadingIcon(
                    icon: HeroAppIcons.networkWired,
                  ),
                  showChevron: false,
                ),
                SettingsRow(
                  title: AppStrings.t(
                    AppStringKeys.developerPerformanceImageCache,
                  ),
                  value:
                      '${_formatMiB(snapshot.imageCacheBytes)} · '
                      '${snapshot.imageCacheEntries} / '
                      '${snapshot.liveImageCount}',
                  leading: const SettingsLeadingIcon(icon: HeroAppIcons.image),
                  showChevron: false,
                ),
                SettingsRow(
                  title: AppStrings.t(
                    AppStringKeys.developerPerformanceFrameWork,
                  ),
                  value: frames.sampleCount == 0
                      ? AppStrings.t(
                          AppStringKeys.developerPerformanceWaitingForFrames,
                        )
                      : '${frames.averageBuildMs.toStringAsFixed(1)} / '
                            '${frames.averageRasterMs.toStringAsFixed(1)} ms',
                  leading: const SettingsLeadingIcon(
                    icon: HeroAppIcons.stopwatch,
                  ),
                  showChevron: false,
                ),
                SettingsRow(
                  title: AppStrings.t(
                    AppStringKeys.developerPerformanceSlowFrames,
                  ),
                  value: frames.sampleCount == 0
                      ? '—'
                      : '${frames.slowFrameCount}/${frames.sampleCount} · '
                            'p95 ${frames.p95TotalMs.toStringAsFixed(1)} ms',
                  leading: const SettingsLeadingIcon(
                    icon: HeroAppIcons.triangleExclamation,
                  ),
                  showChevron: false,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.section),
            SettingsCard.rows(
              rows: [
                SettingsRow(
                  title: AppStrings.t(
                    AppStringKeys.developerPerformanceResetSamples,
                  ),
                  leading: const SettingsLeadingIcon(
                    icon: HeroAppIcons.restore,
                  ),
                  onTap: performance.resetFrameSamples,
                  showChevron: false,
                ),
                SettingsRow(
                  title: AppStrings.t(
                    AppStringKeys.developerPerformanceTrimCaches,
                  ),
                  leading: SettingsLeadingIcon(
                    icon: HeroAppIcons.trash,
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
    );
  }
}

String _formatMiB(int bytes) {
  if (bytes <= 0) return '—';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MiB';
}
