//
//  date_text.dart
//
//  Locale-aware compact chat timestamps.
//

import 'package:intl/intl.dart';

class DateText {
  // 星期日 … 星期六, indexed by DateTime.weekday (Mon=1 … Sun=7).
  static const _weekdays = {
    'zhHans': ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
    'zhHant': ['星期一', '星期二', '星期三', '星期四', '星期五', '星期六', '星期日'],
    'ja': ['月曜日', '火曜日', '水曜日', '木曜日', '金曜日', '土曜日', '日曜日'],
    'ko': ['월요일', '화요일', '수요일', '목요일', '금요일', '토요일', '일요일'],
    'en': ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
    'fr': ['lun.', 'mar.', 'mer.', 'jeu.', 'ven.', 'sam.', 'dim.'],
    'es': ['lun', 'mar', 'mie', 'jue', 'vie', 'sab', 'dom'],
    'de': ['Mo.', 'Di.', 'Mi.', 'Do.', 'Fr.', 'Sa.', 'So.'],
  };

  static const _yesterday = {
    'zhHans': '昨天',
    'zhHant': '昨天',
    'ja': '昨日',
    'ko': '어제',
    'en': 'Yesterday',
    'fr': 'Hier',
    'es': 'Ayer',
    'de': 'Gestern',
  };

  static const _periods = {
    'zhHans': ['凌晨', '早上', '上午', '中午', '下午', '晚上'],
    'zhHant': ['凌晨', '早上', '上午', '中午', '下午', '晚上'],
    'ja': ['未明', '朝', '午前', '昼', '午後', '夜'],
    'ko': ['새벽', '아침', '오전', '정오', '오후', '밤'],
  };

  static String _two(int n) => n.toString().padLeft(2, '0');

  static String get _localeKey {
    final locale = Intl.getCurrentLocale();
    if (locale.startsWith('zh_Hant') ||
        locale.startsWith('zh-Hant') ||
        locale.contains('_TW') ||
        locale.contains('_HK') ||
        locale.contains('_MO')) {
      return 'zhHant';
    }
    if (locale.startsWith('zh')) return 'zhHans';
    final language = locale.split(RegExp('[-_]')).first;
    return _weekdays.containsKey(language) ? language : 'en';
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Chat-list timestamp.
  static String listLabel(int unix) {
    if (unix <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (_sameDay(date, now)) return _timeLabel(date);
    if (_sameDay(date, now.subtract(const Duration(days: 1)))) {
      return _yesterday[_localeKey] ?? _yesterday['en']!;
    }
    final dayStart = DateTime(date.year, date.month, date.day);
    final days = today.difference(dayStart).inDays;
    if (days < 7) {
      return (_weekdays[_localeKey] ?? _weekdays['en']!)[date.weekday - 1];
    }
    if (date.year == now.year) return '${_two(date.month)}/${_two(date.day)}';
    return '${date.year}/${_two(date.month)}/${_two(date.day)}';
  }

  /// Centered in-conversation separator: "2024/06/04 晚上7:54".
  static String separatorLabel(int unix) {
    if (unix <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    final now = DateTime.now();
    if (_sameDay(date, now)) return _timeLabel(date);
    final datePart = date.year == now.year
        ? '${_two(date.month)}/${_two(date.day)}'
        : '${date.year}/${_two(date.month)}/${_two(date.day)}';
    return '$datePart ${_timeLabel(date)}';
  }

  /// In-bubble 24-hour time, e.g. "22:47".
  static String bubbleLabel(int unix) {
    if (unix <= 0) return '';
    final date = DateTime.fromMillisecondsSinceEpoch(unix * 1000);
    return '${_two(date.hour)}:${_two(date.minute)}';
  }

  static String _timeLabel(DateTime date) {
    final key = _localeKey;
    if (_periods.containsKey(key)) return _periodTime(date, key);
    return '${_two(date.hour)}:${_two(date.minute)}';
  }

  static String _periodTime(DateTime date, String key) {
    final hour = date.hour;
    final periodSet = _periods[key] ?? _periods['zhHans']!;
    final int periodIndex;
    if (hour < 5) {
      periodIndex = 0;
    } else if (hour < 8) {
      periodIndex = 1;
    } else if (hour < 11) {
      periodIndex = 2;
    } else if (hour < 13) {
      periodIndex = 3;
    } else if (hour < 18) {
      periodIndex = 4;
    } else {
      periodIndex = 5;
    }
    final displayHour = hour <= 12 ? hour : hour - 12;
    return '${periodSet[periodIndex]}$displayHour:${_two(date.minute)}';
  }
}
