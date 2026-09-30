/// Locale-aware formatting of sizes and dates.
library;

import 'package:intl/intl.dart';

/// Decimal (SI) units, like Android's own storage settings: 1 MB = 10^6 B.
String formatBytes(int bytes, String locale) {
  final fr = locale.startsWith('fr');
  final units = fr
      ? const ['o', 'Ko', 'Mo', 'Go', 'To']
      : const ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1000 && unit < units.length - 1) {
    value /= 1000;
    unit++;
  }
  final digits = unit == 0 || value >= 100 ? 0 : 1;
  final number = NumberFormat.decimalPatternDigits(
    locale: locale,
    decimalDigits: digits,
  ).format(value);
  return '$number ${units[unit]}';
}

String formatDate(DateTime date, String locale) =>
    DateFormat.yMMMd(locale).format(date);
