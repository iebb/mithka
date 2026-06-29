//
//  chat_picker_view.dart
//
//  A searchable chat chooser. Pushed when the user forwards a message or shares
//  content; returns the picked `ChatSummary` via Navigator.pop. Reuses
//  `ChatListViewModel` so it shows the same live, sorted chat list as 消息.
//

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../chats/chat_list_view_model.dart';
import '../components/photo_avatar.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';
import '../theme/theme_controller.dart';

class ChatPickerView extends StatefulWidget {
  const ChatPickerView({super.key, this.title = '选择聊天'});
  final String title;

  @override
  State<ChatPickerView> createState() => _ChatPickerViewState();
}

class _ChatPickerViewState extends State<ChatPickerView> {
  final ChatListViewModel _vm = ChatListViewModel();
  final _controller = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _vm.addListener(_onModel);
    _vm.onAppear();
  }

  void _onModel() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _vm.removeListener(_onModel);
    _vm.dispose();
    _controller.dispose();
    super.dispose();
  }

  List<ChatSummary> get _filtered {
    final all = [..._vm.chats, ..._vm.archived];
    if (_query.trim().isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((c) => c.title.toLowerCase().contains(q)).toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.background,
      body: Column(
        children: [
          _header(),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.zero,
              itemCount: _filtered.length,
              itemBuilder: (context, i) => _row(_filtered[i]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header() {
    final c = context.colors;
    return Container(
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      decoration: BoxDecoration(
        color: c.navBar,
        border: Border(bottom: BorderSide(color: c.divider, width: 0.5)),
      ),
      child: Column(
        children: [
          SizedBox(
            height: 48,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).pop(),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: FaIcon(
                        FontAwesomeIcons.chevronLeft,
                        size: 22,
                        color: c.textPrimary,
                      ),
                    ),
                  ),
                ),
                Text(
                  widget.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: c.textPrimary,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 8),
            child: Container(
              height: 34,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: c.searchFill,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  FaIcon(
                    FontAwesomeIcons.magnifyingGlass,
                    size: 15,
                    color: c.textTertiary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      autocorrect: false,
                      style: TextStyle(fontSize: 15, color: c.textPrimary),
                      decoration: const InputDecoration(
                        hintText: '搜索',
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                      onChanged: (q) => setState(() => _query = q),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(ChatSummary chat) {
    final c = context.colors;
    final circleGroups = context.watch<ThemeController>().circularGroupAvatars;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.of(context).pop(chat),
      child: Container(
        height: 60,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        color: c.background,
        child: Row(
          children: [
            PhotoAvatar(
              title: chat.title,
              photo: chat.photo,
              size: 44,
              square: chat.usesSquareAvatar && !circleGroups,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                chat.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: c.textPrimary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
