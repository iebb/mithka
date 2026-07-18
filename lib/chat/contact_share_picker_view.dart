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

class ContactSharePickerView extends StatefulWidget {
  const ContactSharePickerView({super.key});

  @override
  State<ContactSharePickerView> createState() => _ContactSharePickerViewState();
}

class _ContactSharePickerViewState extends State<ContactSharePickerView> {
  final _search = TextEditingController();
  List<_ShareContact> _contacts = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _search.addListener(_rebuild);
    unawaited(_load());
  }

  @override
  void dispose() {
    _search
      ..removeListener(_rebuild)
      ..dispose();
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final loaded = <_ShareContact>[];
    try {
      final result = await TdClient.shared.query({'@type': 'getContacts'});
      for (final id in result.int64Array('user_ids') ?? const <int>[]) {
        try {
          final user = await TdClient.shared.query({
            '@type': 'getUser',
            'user_id': id,
          });
          final phone = user.str('phone_number') ?? '';
          if (phone.trim().isEmpty) continue;
          loaded.add(
            _ShareContact(
              card: MessageContactCard(
                phoneNumber: phone,
                firstName: user.str('first_name') ?? '',
                lastName: user.str('last_name') ?? '',
                vcard: '',
                userId: id,
              ),
              photo: TDParse.smallPhoto(user.obj('profile_photo')),
            ),
          );
        } catch (_) {}
      }
      loaded.sort(
        (a, b) => a.card.displayName.toLowerCase().compareTo(
          b.card.displayName.toLowerCase(),
        ),
      );
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _contacts = loaded;
      _loading = false;
    });
  }

  List<_ShareContact> get _visible {
    final query = _search.text.trim().toLowerCase();
    if (query.isEmpty) return _contacts;
    return _contacts
        .where(
          (contact) =>
              contact.card.displayName.toLowerCase().contains(query) ||
              contact.card.phoneNumber.toLowerCase().contains(query),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final visible = _visible;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      body: Column(
        children: [
          NavHeader(
            title: AppStringKeys.contactShareTitle,
            onBack: () => Navigator.of(context).pop(),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 11),
              decoration: BoxDecoration(
                color: c.searchFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  AppIcon(
                    HeroAppIcons.magnifyingGlass,
                    size: 17,
                    color: c.textTertiary,
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      decoration: InputDecoration.collapsed(
                        hintText: AppStringKeys.contactShareSearch.l10n(
                          context,
                        ),
                      ),
                      style: TextStyle(fontSize: 15, color: c.textPrimary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: AppActivityIndicator(size: 24))
                : visible.isEmpty
                ? Center(
                    child: Text(
                      AppStringKeys.contactShareEmpty.l10n(context),
                      style: TextStyle(fontSize: 14, color: c.textSecondary),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.only(bottom: 18),
                    itemCount: visible.length,
                    separatorBuilder: (_, _) =>
                        const InsetDivider(leadingInset: 70),
                    itemBuilder: (context, index) {
                      final contact = visible[index];
                      return GestureDetector(
                        key: ValueKey('shareContact-${contact.card.userId}'),
                        behavior: HitTestBehavior.opaque,
                        onTap: () => Navigator.of(context).pop(contact.card),
                        child: Container(
                          height: 64,
                          color: c.card,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          child: Row(
                            children: [
                              PhotoAvatar(
                                title: contact.card.displayName,
                                photo: contact.photo,
                                size: 44,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      contact.card.displayName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w500,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      contact.card.phoneNumber,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 13,
                                        color: c.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              AppIcon(
                                HeroAppIcons.paperPlane,
                                size: 18,
                                color: AppTheme.brand,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _ShareContact {
  const _ShareContact({required this.card, this.photo});

  final MessageContactCard card;
  final TdFileRef? photo;
}
