//
//  keyword_blocker_view.dart
//
//  关键词屏蔽 settings: user-managed local keyword list.
//

import 'package:flutter/material.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
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
      if (mounted) showToast(context, added > 0 ? '已添加 $added 条规则' : '规则已是最新');
    } catch (_) {
      if (mounted) showToast(context, '下载关键词列表失败');
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final keywords = _blocker.keywords;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(title: '关键词屏蔽', onBack: () => Navigator.of(context).pop()),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
              children: [
                _inputCard(),
                const SizedBox(height: 14),
                _urlCard(),
                const SizedBox(height: 14),
                if (keywords.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 20,
                    ),
                    child: Text(
                      '添加关键词后，匹配的消息将不会在聊天中显示，也不会触发本地通知。支持普通关键词、re:正则、regex:正则、/正则/i。远程列表每行一条规则，# 或 // 开头为注释。',
                      style: TextStyle(fontSize: 14, color: c.textSecondary),
                    ),
                  )
                else
                  _keywordCard(keywords),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _inputCard() {
    final c = context.colors;
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
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
                hintText: '输入关键词',
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
              child: const Text(
                '添加',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.white,
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
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
      child: Row(
        children: [
          FaIcon(FontAwesomeIcons.link, size: 19, color: AppTheme.brand),
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
                hintText: '关键词列表 URL',
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
                borderRadius: BorderRadius.circular(17),
              ),
              child: _refreshing
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text(
                      '下载',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.white,
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
    return Container(
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (final keyword in keywords) ...[
            SizedBox(
              height: 52,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    FaIcon(
                      FontAwesomeIcons.ban,
                      size: 19,
                      color: AppTheme.tagRed,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        keyword,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 16, color: c.textPrimary),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _blocker.remove(keyword),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: FaIcon(
                          FontAwesomeIcons.xmark,
                          size: 16,
                          color: c.textTertiary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (keyword != keywords.last) const InsetDivider(leadingInset: 47),
          ],
        ],
      ),
    );
  }
}
