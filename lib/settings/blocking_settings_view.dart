import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../components/app_icons.dart';
import '../components/ui_components.dart';
import '../l10n/app_localizations.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';
import 'blocked_user_service.dart';
import 'country_message_filter.dart';
import 'country_message_filter_view.dart';
import 'keyword_blocker_view.dart';
import 'privacy_detail_views.dart';

class BlockingSettingsView extends StatelessWidget {
  const BlockingSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = context.watch<ThemeController>();
    final country = CountryMessageFilter.shared;
    return ColoredBox(
      color: c.groupedBackground,
      child: Column(
        children: [
          NavHeader(
            title: AppStringKeys.blockingTitle.l10n(context),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListenableBuilder(
              listenable: country,
              builder: (context, _) => ListView(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
                children: [
                  _card(context, [
                    SettingsSwitchRow(
                      title: AppStringKeys.appearanceHideBlockedUserMessages,
                      value: theme.hideBlockedUserMessages,
                      leading: AppIcon(
                        HeroAppIcons.eyeSlash,
                        size: 20,
                        color: AppTheme.brand,
                      ),
                      onChanged: (value) {
                        theme.hideBlockedUserMessages = value;
                        BlockedUserService.shared.enabled = value;
                        if (value) {
                          BlockedUserService.shared.loadBlockedUsers();
                        }
                      },
                    ),
                    const InsetDivider(leadingInset: 52),
                    SettingsRow(
                      title: AppStringKeys.blockingBlocklist,
                      leading: AppIcon(
                        HeroAppIcons.users,
                        size: 20,
                        color: AppTheme.brand,
                      ),
                      onTap: () => Navigator.of(context).push(
                        PageRouteBuilder<void>(
                          pageBuilder: (_, _, _) => const BlockedUsersView(),
                        ),
                      ),
                    ),
                    const InsetDivider(leadingInset: 52),
                    SettingsRow(
                      title: AppStringKeys.keywordBlockerTitle,
                      leading: AppIcon(
                        HeroAppIcons.ban,
                        size: 20,
                        color: AppTheme.brand,
                      ),
                      onTap: () => Navigator.of(context).push(
                        PageRouteBuilder<void>(
                          pageBuilder: (_, _, _) => const KeywordBlockerView(),
                        ),
                      ),
                    ),
                  ]),
                  const SizedBox(height: 14),
                  _label(context, AppStringKeys.blockingCountry),
                  _card(context, [
                    SettingsRow(
                      title: AppStringKeys.blockingCountry,
                      value: country.selectedCountries.isEmpty
                          ? AppStringKeys.blockingCountryOff
                          : AppStrings.t(
                              AppStringKeys.blockingCountrySelected,
                              {'value1': country.selectedCountries.length},
                            ),
                      leading: AppIcon(
                        HeroAppIcons.globe,
                        size: 20,
                        color: AppTheme.brand,
                      ),
                      onTap: () => Navigator.of(context).push(
                        PageRouteBuilder<void>(
                          pageBuilder: (_, _, _) =>
                              const CountryMessageFilterView(),
                        ),
                      ),
                    ),
                  ]),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 7, 16, 0),
                    child: Text(
                      AppStringKeys.blockingCountryDescription.l10n(context),
                      style: TextStyle(fontSize: 12, color: c.textTertiary),
                    ),
                  ),
                  const SizedBox(height: 14),
                  _label(context, AppStringKeys.blockingExemptions),
                  _card(context, [
                    SettingsSwitchRow(
                      title: AppStringKeys.blockingExemptCommonPrivateGroup,
                      value: country.exemptCommonPrivateGroup,
                      onChanged: country.setExemptCommonPrivateGroup,
                    ),
                    const InsetDivider(leadingInset: 16),
                    SettingsSwitchRow(
                      title: AppStringKeys.blockingExemptThreeCommonGroups,
                      value: country.exemptThreeCommonGroups,
                      onChanged: country.setExemptThreeCommonGroups,
                    ),
                    const InsetDivider(leadingInset: 16),
                    SettingsSwitchRow(
                      title: AppStringKeys.blockingExemptPlainText,
                      value: country.exemptPlainText,
                      onChanged: country.setExemptPlainText,
                    ),
                    const InsetDivider(leadingInset: 16),
                    SettingsSwitchRow(
                      title: AppStringKeys.blockingExemptNonDefaultAvatar,
                      value: country.exemptNonDefaultAvatar,
                      onChanged: country.setExemptNonDefaultAvatar,
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _card(BuildContext context, List<Widget> children) => Container(
    decoration: BoxDecoration(
      color: context.colors.card,
      borderRadius: BorderRadius.circular(12),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(children: children),
  );

  Widget _label(BuildContext context, String key) => Padding(
    padding: const EdgeInsets.only(left: 16, bottom: 6),
    child: Text(
      key.l10n(context),
      style: TextStyle(fontSize: 13, color: context.colors.textTertiary),
    ),
  );
}
