import 'package:intl/intl.dart';

import 'i18n.dart';
import 'status.dart';

/// Date (and time) in the user's language. D365 empty dates are null and shown as a dash.
String fmtDate(DateTime? d, String lang, {bool time = true}) {
  if (d == null) return '—';
  final locale = lang == 'ar' ? 'ar' : 'en';
  return (time ? DateFormat.yMMMd(locale).add_Hm() : DateFormat.yMMMd(locale)).format(d);
}

/// Time of day only (slots, timeline).
String fmtTime(DateTime? d, String lang) => d == null ? '—' : DateFormat.Hm(lang == 'ar' ? 'ar' : 'en').format(d);

/// Short date ("12 Nov") for compact cards.
String fmtShortDate(DateTime? d, String lang) => d == null ? '—' : DateFormat.MMMd(lang == 'ar' ? 'ar' : 'en').format(d);

/// Numbers, money, odometers: always Western digits with grouping (tokens.json → font.numerals), in both languages.
String fmtNum(num value, {int decimals = 0}) =>
    NumberFormat.decimalPatternDigits(locale: 'en', decimalDigits: decimals).format(value);

String fmtMoney(num value, String currency) => '${fmtNum(value, decimals: 2)}${currency.isEmpty ? '' : ' $currency'}';

String fmtKm(num value) => '${fmtNum(value)} km';

/// "in 3 h" / "2 d late" for a promise; empty when there is no promise.
String promiseText(Strings s, DateTime? promise, {DateTime? now}) {
  if (promise == null) return '';
  final d = promiseDelta(promise, now ?? DateTime.now());
  final amount = s.t('unit_${d.unit}', [d.value]);
  return s.t(d.overdue ? 'lateBy' : 'dueIn', [amount]);
}

/// Short weekday ("Mon" / "الاثنين") for date pickers.
String fmtWeekday(DateTime d, String lang) => DateFormat.E(lang == 'ar' ? 'ar' : 'en').format(d);
