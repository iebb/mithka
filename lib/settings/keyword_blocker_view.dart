//
//  keyword_blocker_view.dart
//
//  关键词屏蔽 settings: user-managed local keyword list.
//

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/app_interactive_surface.dart';
import '../components/toast.dart';
import '../components/ui_components.dart';
import '../theme/app_theme.dart';
import 'keyword_blocker.dart';

class KeywordBlockerView extends StatefulWidget {
  const KeywordBlockerView({super.key});

  @override
  State<KeywordBlockerView> createState() => _KeywordBlockerViewState();
}

class _KeywordBlockerViewState extends State<KeywordBlockerView> {
  final _controller = TextEditingController();
  final _urlController = TextEditingController();
  final _blocker = KeywordBlocker.shared;
  bool _refreshing = false;

  @override
  void initState() {
    super.initState();
    _blocker.addListener(_onChanged);
    _urlController.text = _blocker.listUrl;
  }

  @override
  void dispose() {
    _blocker.removeListener(_onChanged);
    _controller.dispose();
    _urlController.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  void _add() {
    final text = _controller.text;
    _blocker.add(text);
    _controller.clear();
  }

  Future<void> _refreshUrl() async {
    _blocker.setListUrl(_urlController.text);
    setState(() => _refreshing = true);
    try {
      final added = await _blocker.refreshFromUrl();
      if (mounted) {
        showToast(
          context,
          added > 0
              ? AppStrings.t(AppStringKeys.keywordBlockerRulesAdded, {
                  'value1': added,
                })
              : AppStrings.t(AppStringKeys.keywordBlockerRulesUpToDate),
        );
      }
    } catch (_) {
      if (mounted) {
        showToast(
          context,
          AppStrings.t(AppStringKeys.keywordBlockerDownloadFailed),
        );
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final keywords = _blocker.keywords;
    return SettingsPageScaffold(
      title: AppStrings.t(AppStringKeys.keywordBlockerTitle),
      onBack: () => Navigator.of(context).pop(),
      child: SettingsListView(
        children: [
          _inputCard(),
          const SizedBox(height: AppSpacing.lg),
          _urlCard(),
          const SizedBox(height: AppSpacing.lg),
          if (keywords.isEmpty)
            SettingsNote(
              text: AppStrings.t(AppStringKeys.keywordBlockerDescription),
            )
          else
            _keywordCard(keywords),
        ],
      ),
    );
  }

  Widget _inputCard() {
    final c = context.colors;
    return SettingsPanel(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _add(),
              style: TextStyle(fontSize: 16, color: c.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: AppStrings.t(
                  AppStringKeys.keywordBlockerInputPlaceholder,
                ),
                hintStyle: TextStyle(color: c.textTertiary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _add,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppTheme.brand,
                borderRadius: BorderRadius.circular(17),
              ),
              child: Text(
                AppStrings.t(AppStringKeys.imageEditAdd),
                style: TextStyle(
                  fontSize: 14,
                  color: AppTheme.onBrand,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _urlCard() {
    final c = context.colors;
    return SettingsPanel(
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          AppIcon(HeroAppIcons.link, size: 19, color: AppTheme.brand),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: _urlController,
              keyboardType: TextInputType.url,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _refreshing ? null : _refreshUrl(),
              style: TextStyle(fontSize: 15, color: c.textPrimary),
              decoration: InputDecoration(
                border: InputBorder.none,
                isCollapsed: true,
                hintText: AppStrings.t(AppStringKeys.keywordBlockerListUrl),
                hintStyle: TextStyle(color: c.textTertiary),
              ),
            ),
          ),
          const SizedBox(width: 10),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _refreshing ? null : _refreshUrl,
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _refreshing ? c.searchFill : AppTheme.brand,
                borderRadius: BorderRadius.circular(AppRadius.lg),
              ),
              child: _refreshing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      AppStrings.t(AppStringKeys.keywordBlockerDownload),
                      style: TextStyle(
                        fontSize: 14,
                        color: AppTheme.onBrand,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _keywordCard(List<String> keywords) {
    final c = context.colors;
    return SettingsCard.rows(
      rows: [
        for (final keyword in keywords)
          SettingsRow(
            title: keyword,
            leading: SettingsLeadingIcon(
              icon: HeroAppIcons.ban,
              color: AppTheme.tagRed,
            ),
            showChevron: false,
            trailing: AppInteractiveSurface(
              semanticLabel: AppStrings.t(AppStringKeys.chatInfoRemove),
              onTap: () => _blocker.remove(keyword),
              borderRadius: BorderRadius.circular(AppRadius.control),
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: AppIcon(
                  HeroAppIcons.xmark,
                  size: 16,
                  color: c.textTertiary,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
