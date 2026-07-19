import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mithka/l10n/app_localizations.dart';

import '../components/app_icons.dart';
import '../components/photo_avatar.dart';
import '../components/ui_components.dart';
import '../tdlib/json_helpers.dart';
import '../tdlib/td_client.dart';
import '../tdlib/td_models.dart';
import '../theme/app_theme.dart';

class PollResultsView extends StatefulWidget {
  const PollResultsView({
    super.key,
    required this.chatId,
    required this.message,
  });

  final int chatId;
  final ChatMessage message;

  @override
  State<PollResultsView> createState() => _PollResultsViewState();
}

class _PollVoter {
  const _PollVoter({required this.id, required this.title, this.photo});

  final int id;
  final String title;
  final TdFileRef? photo;
}

class _PollResultsViewState extends State<PollResultsView> {
  final _client = TdClient.shared;
  final _search = TextEditingController();
  final Map<int, List<_PollVoter>> _voters = {};
  final Set<int> _loading = {};
  int _selected = 0;
  Map<String, dynamic>? _statistics;
  String? _error;

  MessagePoll get _poll => widget.message.poll!;

  @override
  void initState() {
    super.initState();
    _search.addListener(_refresh);
    unawaited(_loadSelected());
    unawaited(_loadStatistics());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  Future<void> _loadStatistics() async {
    try {
      final properties = await _client.query({
        '@type': 'getMessageProperties',
        'chat_id': widget.chatId,
        'message_id': widget.message.id,
      });
      if (properties.boolean('can_get_poll_vote_statistics') != true) return;
      final result = await _client.query({
        '@type': 'getPollVoteStatistics',
        'chat_id': widget.chatId,
        'message_id': widget.message.id,
        'is_dark':
            WidgetsBinding.instance.platformDispatcher.platformBrightness ==
            Brightness.dark,
      });
      if (mounted) setState(() => _statistics = result);
    } catch (_) {
      // Vote lists still remain useful when detailed statistics are private.
    }
  }

  Future<void> _loadSelected() async {
    final index = _selected;
    if (_voters.containsKey(index) || !_poll.canGetVoters) return;
    if (!_loading.add(index)) return;
    setState(() {});
    try {
      final response = await _client.query({
        '@type': 'getPollVoters',
        'chat_id': widget.chatId,
        'message_id': widget.message.id,
        'option_id': index,
        'offset': 0,
        'limit': 50,
      });
      final senders =
          response.objects('voters') ?? const <Map<String, dynamic>>[];
      final voters = await Future.wait(senders.map(_resolveSender));
      if (!mounted) return;
      setState(() {
        _voters[index] = voters.whereType<_PollVoter>().toList(growable: false);
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading.remove(index));
    }
  }

  Future<_PollVoter?> _resolveSender(Map<String, dynamic> sender) async {
    try {
      if (sender.type == 'messageSenderUser') {
        final id = sender.int64('user_id') ?? 0;
        final user = await _client.query({'@type': 'getUser', 'user_id': id});
        return _PollVoter(
          id: id,
          title: TDParse.userName(user),
          photo: TDParse.smallPhoto(user.obj('profile_photo')),
        );
      }
      if (sender.type == 'messageSenderChat') {
        final id = sender.int64('chat_id') ?? 0;
        final chat = await _client.query({'@type': 'getChat', 'chat_id': id});
        return _PollVoter(
          id: id,
          title: chat.str('title') ?? 'Chat',
          photo: TDParse.smallPhoto(chat.obj('photo')),
        );
      }
    } catch (_) {}
    return null;
  }

  void _select(int index) {
    setState(() => _selected = index);
    unawaited(_loadSelected());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final query = _search.text.trim().toLowerCase();
    final voters = (_voters[_selected] ?? const <_PollVoter>[])
        .where(
          (voter) => query.isEmpty || voter.title.toLowerCase().contains(query),
        )
        .toList(growable: false);
    return Scaffold(
      backgroundColor: colors.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStrings.t(AppStringKeys.pollResultsPollResults),
            onBack: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 14),
              children: [
                Container(
                  color: colors.card,
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _poll.question,
                        style: TextStyle(
                          color: colors.textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        AppStrings.t(
                          _statistics == null
                              ? AppStringKeys.messagePollVotes
                              : AppStringKeys
                                    .pollResultsVotesWithDetailedStatistics,
                          {'value1': _poll.totalVoterCount},
                        ),
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 46,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _poll.options.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final option = _poll.options[index];
                      final selected = index == _selected;
                      return GestureDetector(
                        key: ValueKey('pollResultOption-$index'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => _select(index),
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 92),
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: selected ? AppTheme.brand : colors.card,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selected ? AppTheme.brand : colors.divider,
                            ),
                          ),
                          child: Text(
                            '${option.text} · ${option.voterCount}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: selected
                                  ? Colors.white
                                  : colors.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 12),
                if (_poll.canGetVoters) ...[
                  Container(
                    color: colors.card,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 9,
                    ),
                    child: Container(
                      height: 38,
                      padding: const EdgeInsets.symmetric(horizontal: 11),
                      decoration: BoxDecoration(
                        color: colors.searchFill,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Row(
                        children: [
                          AppIcon(
                            HeroAppIcons.magnifyingGlass,
                            size: 17,
                            color: colors.textTertiary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _search,
                              decoration: InputDecoration.collapsed(
                                hintText: AppStrings.t(
                                  AppStringKeys.pollResultsFilterVoters,
                                ),
                              ),
                              style: TextStyle(
                                color: colors.textPrimary,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (_loading.contains(_selected))
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: AppActivityIndicator(size: 22)),
                    )
                  else if (_error != null)
                    _empty('Unable to load voters')
                  else if (voters.isEmpty)
                    _empty(query.isEmpty ? 'No visible voters' : 'No matches')
                  else
                    Container(
                      color: colors.card,
                      child: Column(
                        children: [
                          for (
                            var index = 0;
                            index < voters.length;
                            index++
                          ) ...[
                            _voterRow(voters[index]),
                            if (index != voters.length - 1)
                              const InsetDivider(leadingInset: 64),
                          ],
                        ],
                      ),
                    ),
                ] else
                  _empty(
                    _poll.isAnonymous
                        ? 'This poll is anonymous'
                        : 'The voter list is unavailable',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _voterRow(_PollVoter voter) => SizedBox(
    height: 58,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          PhotoAvatar(title: voter.title, photo: voter.photo, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              voter.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: context.colors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _empty(String text) => Padding(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: context.colors.textSecondary, fontSize: 14),
      ),
    ),
  );
}
