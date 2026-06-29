//
//  country_picker.dart
//
//  Country/region model + picker sheet for the Telegram-style phone login.
//  The Swift app sources its list from libphonenumber; to stay dependency-light
//  cross-platform we embed a comprehensive dialable-region table (Chinese names,
//  ISO codes, dial codes) and compute flags from the ISO code — the same
//  presentation, match, and flag logic as the Swift `Country`.
//

import 'package:dlibphonenumber/dlibphonenumber.dart';
import 'package:flutter/material.dart';

import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import '../theme/app_theme.dart';

class Country {
  const Country(this.name, this.iso, this.dial);
  final String name; // Chinese display name
  final String iso; // ISO 3166-1 alpha-2
  final String dial; // dial code, digits only

  /// Flag emoji derived from the ISO code (regional-indicator scalars).
  String get flag {
    const base = 0x1F1E6;
    final buf = StringBuffer();
    for (final c in iso.toUpperCase().codeUnits) {
      if (c >= 65 && c <= 90) buf.writeCharCode(base + (c - 65));
    }
    return buf.toString();
  }

  static const Country china = Country('中国', 'CN', '86');

  /// Every dialable region we ship (names localized to Chinese). Comprehensive
  /// across distinct country calling codes; shared calling codes use
  /// libphonenumber leading-digit metadata before falling back to a canonical
  /// display country.
  static const List<Country> all = [
    // East Asia
    Country('中国', 'CN', '86'),
    Country('中国香港', 'HK', '852'),
    Country('中国澳门', 'MO', '853'),
    Country('中国台湾', 'TW', '886'),
    Country('日本', 'JP', '81'),
    Country('韩国', 'KR', '82'),
    Country('朝鲜', 'KP', '850'),
    Country('蒙古', 'MN', '976'),
    // Southeast Asia
    Country('新加坡', 'SG', '65'),
    Country('马来西亚', 'MY', '60'),
    Country('泰国', 'TH', '66'),
    Country('越南', 'VN', '84'),
    Country('印度尼西亚', 'ID', '62'),
    Country('菲律宾', 'PH', '63'),
    Country('柬埔寨', 'KH', '855'),
    Country('缅甸', 'MM', '95'),
    Country('老挝', 'LA', '856'),
    Country('文莱', 'BN', '673'),
    Country('东帝汶', 'TL', '670'),
    // South Asia
    Country('印度', 'IN', '91'),
    Country('巴基斯坦', 'PK', '92'),
    Country('孟加拉国', 'BD', '880'),
    Country('斯里兰卡', 'LK', '94'),
    Country('尼泊尔', 'NP', '977'),
    Country('不丹', 'BT', '975'),
    Country('马尔代夫', 'MV', '960'),
    Country('阿富汗', 'AF', '93'),
    // Central Asia
    Country('哈萨克斯坦', 'KZ', '7'),
    Country('乌兹别克斯坦', 'UZ', '998'),
    Country('土库曼斯坦', 'TM', '993'),
    Country('塔吉克斯坦', 'TJ', '992'),
    Country('吉尔吉斯斯坦', 'KG', '996'),
    // Middle East
    Country('阿联酋', 'AE', '971'),
    Country('沙特阿拉伯', 'SA', '966'),
    Country('以色列', 'IL', '972'),
    Country('巴勒斯坦', 'PS', '970'),
    Country('卡塔尔', 'QA', '974'),
    Country('科威特', 'KW', '965'),
    Country('巴林', 'BH', '973'),
    Country('阿曼', 'OM', '968'),
    Country('约旦', 'JO', '962'),
    Country('黎巴嫩', 'LB', '961'),
    Country('伊拉克', 'IQ', '964'),
    Country('伊朗', 'IR', '98'),
    Country('叙利亚', 'SY', '963'),
    Country('也门', 'YE', '967'),
    Country('土耳其', 'TR', '90'),
    Country('格鲁吉亚', 'GE', '995'),
    Country('亚美尼亚', 'AM', '374'),
    Country('阿塞拜疆', 'AZ', '994'),
    // Europe
    Country('英国', 'GB', '44'),
    Country('爱尔兰', 'IE', '353'),
    Country('法国', 'FR', '33'),
    Country('德国', 'DE', '49'),
    Country('意大利', 'IT', '39'),
    Country('西班牙', 'ES', '34'),
    Country('葡萄牙', 'PT', '351'),
    Country('荷兰', 'NL', '31'),
    Country('比利时', 'BE', '32'),
    Country('卢森堡', 'LU', '352'),
    Country('瑞士', 'CH', '41'),
    Country('奥地利', 'AT', '43'),
    Country('瑞典', 'SE', '46'),
    Country('挪威', 'NO', '47'),
    Country('丹麦', 'DK', '45'),
    Country('芬兰', 'FI', '358'),
    Country('冰岛', 'IS', '354'),
    Country('波兰', 'PL', '48'),
    Country('捷克', 'CZ', '420'),
    Country('斯洛伐克', 'SK', '421'),
    Country('匈牙利', 'HU', '36'),
    Country('罗马尼亚', 'RO', '40'),
    Country('保加利亚', 'BG', '359'),
    Country('希腊', 'GR', '30'),
    Country('俄罗斯', 'RU', '7'),
    Country('乌克兰', 'UA', '380'),
    Country('白俄罗斯', 'BY', '375'),
    Country('摩尔多瓦', 'MD', '373'),
    Country('立陶宛', 'LT', '370'),
    Country('拉脱维亚', 'LV', '371'),
    Country('爱沙尼亚', 'EE', '372'),
    Country('塞尔维亚', 'RS', '381'),
    Country('克罗地亚', 'HR', '385'),
    Country('斯洛文尼亚', 'SI', '386'),
    Country('波黑', 'BA', '387'),
    Country('北马其顿', 'MK', '389'),
    Country('阿尔巴尼亚', 'AL', '355'),
    Country('黑山', 'ME', '382'),
    Country('科索沃', 'XK', '383'),
    Country('马耳他', 'MT', '356'),
    Country('塞浦路斯', 'CY', '357'),
    Country('安道尔', 'AD', '376'),
    Country('摩纳哥', 'MC', '377'),
    Country('圣马力诺', 'SM', '378'),
    Country('列支敦士登', 'LI', '423'),
    // Africa
    Country('埃及', 'EG', '20'),
    Country('南非', 'ZA', '27'),
    Country('摩洛哥', 'MA', '212'),
    Country('阿尔及利亚', 'DZ', '213'),
    Country('突尼斯', 'TN', '216'),
    Country('利比亚', 'LY', '218'),
    Country('尼日利亚', 'NG', '234'),
    Country('加纳', 'GH', '233'),
    Country('科特迪瓦', 'CI', '225'),
    Country('塞内加尔', 'SN', '221'),
    Country('喀麦隆', 'CM', '237'),
    Country('肯尼亚', 'KE', '254'),
    Country('埃塞俄比亚', 'ET', '251'),
    Country('坦桑尼亚', 'TZ', '255'),
    Country('乌干达', 'UG', '256'),
    Country('赞比亚', 'ZM', '260'),
    Country('津巴布韦', 'ZW', '263'),
    Country('安哥拉', 'AO', '244'),
    Country('莫桑比克', 'MZ', '258'),
    Country('博茨瓦纳', 'BW', '267'),
    Country('纳米比亚', 'NA', '264'),
    Country('卢旺达', 'RW', '250'),
    Country('马里', 'ML', '223'),
    Country('布基纳法索', 'BF', '226'),
    Country('尼日尔', 'NE', '227'),
    Country('乍得', 'TD', '235'),
    Country('苏丹', 'SD', '249'),
    Country('南苏丹', 'SS', '211'),
    Country('索马里', 'SO', '252'),
    Country('马达加斯加', 'MG', '261'),
    Country('马拉维', 'MW', '265'),
    Country('加蓬', 'GA', '241'),
    Country('刚果（布）', 'CG', '242'),
    Country('刚果（金）', 'CD', '243'),
    Country('贝宁', 'BJ', '229'),
    Country('多哥', 'TG', '228'),
    Country('几内亚', 'GN', '224'),
    Country('毛里塔尼亚', 'MR', '222'),
    Country('毛里求斯', 'MU', '230'),
    // North & Central America
    Country('美国', 'US', '1'),
    Country('加拿大', 'CA', '1'),
    Country('墨西哥', 'MX', '52'),
    Country('危地马拉', 'GT', '502'),
    Country('伯利兹', 'BZ', '501'),
    Country('萨尔瓦多', 'SV', '503'),
    Country('洪都拉斯', 'HN', '504'),
    Country('尼加拉瓜', 'NI', '505'),
    Country('哥斯达黎加', 'CR', '506'),
    Country('巴拿马', 'PA', '507'),
    Country('古巴', 'CU', '53'),
    Country('海地', 'HT', '509'),
    // South America
    Country('巴西', 'BR', '55'),
    Country('阿根廷', 'AR', '54'),
    Country('智利', 'CL', '56'),
    Country('哥伦比亚', 'CO', '57'),
    Country('秘鲁', 'PE', '51'),
    Country('委内瑞拉', 'VE', '58'),
    Country('厄瓜多尔', 'EC', '593'),
    Country('玻利维亚', 'BO', '591'),
    Country('巴拉圭', 'PY', '595'),
    Country('乌拉圭', 'UY', '598'),
    Country('圭亚那', 'GY', '592'),
    Country('苏里南', 'SR', '597'),
    // Oceania
    Country('澳大利亚', 'AU', '61'),
    Country('新西兰', 'NZ', '64'),
    Country('斐济', 'FJ', '679'),
    Country('巴布亚新几内亚', 'PG', '675'),
    Country('萨摩亚', 'WS', '685'),
    Country('汤加', 'TO', '676'),
    Country('瓦努阿图', 'VU', '678'),
    Country('所罗门群岛', 'SB', '677'),
  ];

  /// `all`, sorted by Chinese display name for presentation.
  static List<Country> get sorted =>
      [...all]..sort((a, b) => a.name.compareTo(b.name));

  /// Best country whose dial code is a prefix of [digits].
  ///
  /// Longest dial wins. Shared codes use libphonenumber's leading-digit
  /// metadata, which matches Telegram's country detection behavior for ranges
  /// such as +76/+77 Kazakhstan under the shared +7 country code.
  static const _mainForCode = {'1': 'US', '7': 'RU', '44': 'GB', '86': 'CN'};

  static Country? match(String digits) {
    if (digits.isEmpty) return null;
    final candidates = all
        .where((c) => c.dial.isNotEmpty && digits.startsWith(c.dial))
        .toList();
    if (candidates.isEmpty) return null;
    final maxLen = candidates
        .map((c) => c.dial.length)
        .reduce((a, b) => a > b ? a : b);
    final best = candidates.where((c) => c.dial.length == maxLen).toList();
    if (best.length == 1) return best.first;
    final metadataMatch = _matchSharedCodeFromPhoneMetadata(digits, best);
    if (metadataMatch != null) return metadataMatch;
    final main = _mainForCode[best.first.dial];
    return best.firstWhere((c) => c.iso == main, orElse: () => best.first);
  }

  static Country? _matchSharedCodeFromPhoneMetadata(
    String digits,
    List<Country> candidates,
  ) {
    if (candidates.isEmpty || digits.length <= candidates.first.dial.length) {
      return null;
    }
    try {
      final parsed = PhoneNumberUtil.instance.parse('+$digits', null);
      final region = PhoneNumberUtil.instance.getRegionCodeForNumber(parsed);
      final match = _byIso(region, candidates);
      if (match != null) return match;
    } catch (_) {
      // Keep login typing resilient; fall through to short-prefix metadata.
    }

    // libphonenumber metadata marks Kazakhstan under +7 with national prefixes
    // 6 and 7. Keep this explicit so the UI flips to KZ immediately at "+77",
    // even if parsing rejects the very short partial number on some platforms.
    if (digits.startsWith('76') || digits.startsWith('77')) {
      return _byIso('KZ', candidates);
    }
    return null;
  }

  static Country? _byIso(String? iso, [Iterable<Country>? scope]) {
    if (iso == null || iso.isEmpty) return null;
    final upper = iso.toUpperCase();
    for (final country in scope ?? all) {
      if (country.iso == upper) return country;
    }
    return null;
  }
}

class CountryPickerView extends StatefulWidget {
  const CountryPickerView({super.key, required this.onSelect});
  final ValueChanged<Country> onSelect;

  @override
  State<CountryPickerView> createState() => _CountryPickerViewState();
}

class _CountryPickerViewState extends State<CountryPickerView> {
  final _controller = TextEditingController();
  String _query = '';

  List<Country> get _results {
    final q = _query.trim();
    if (q.isEmpty) return Country.sorted;
    final lower = q.toLowerCase();
    final digits = q.replaceAll(RegExp(r'[^0-9]'), '');
    return Country.sorted.where((c) {
      return c.name.contains(q) ||
          c.iso.toLowerCase().contains(lower) ||
          (digits.isNotEmpty && c.dial.contains(digits));
    }).toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Scaffold(
      backgroundColor: c.groupedBackground,
      appBar: AppBar(
        backgroundColor: c.navBar,
        title: Text(
          '选择国家或地区',
          style: TextStyle(fontSize: 17, color: c.textPrimary),
        ),
        centerTitle: true,
        leading: TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text('取消', style: TextStyle(color: AppTheme.brand)),
        ),
        leadingWidth: 64,
      ),
      body: Column(
        children: [
          Container(
            color: c.background,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: c.searchFill,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  FaIcon(
                    FontAwesomeIcons.magnifyingGlass,
                    size: 18,
                    color: c.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _controller,
                      onChanged: (v) => setState(() => _query = v),
                      style: TextStyle(color: c.textPrimary, fontSize: 15),
                      decoration: const InputDecoration(
                        hintText: '搜索国家 / 区号',
                        border: InputBorder.none,
                        isCollapsed: true,
                      ),
                    ),
                  ),
                  if (_query.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() {
                        _controller.clear();
                        _query = '';
                      }),
                      child: FaIcon(
                        FontAwesomeIcons.xmark,
                        size: 18,
                        color: c.textTertiary,
                      ),
                    ),
                ],
              ),
            ),
          ),
          Expanded(
            child: Container(
              color: c.background,
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, i) {
                  final country = _results[i];
                  return InkWell(
                    onTap: () {
                      widget.onSelect(country);
                      Navigator.of(context).pop();
                    },
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Text(
                            country.flag,
                            style: const TextStyle(fontSize: 26),
                          ),
                          const SizedBox(width: 12),
                          Text(
                            country.name,
                            style: TextStyle(
                              fontSize: 17,
                              color: c.textPrimary,
                            ),
                          ),
                          const Spacer(),
                          Text(
                            '+${country.dial}',
                            style: TextStyle(
                              fontSize: 16,
                              color: c.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
