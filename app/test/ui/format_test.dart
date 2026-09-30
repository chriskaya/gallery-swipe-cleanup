import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:tamis/src/ui/format.dart';

void main() {
  test('bytes use decimal units and the locale', () {
    expect(formatBytes(0, 'en'), '0 B');
    expect(formatBytes(999, 'en'), '999 B');
    expect(formatBytes(1500, 'en'), '1.5 KB');
    expect(formatBytes(3000000, 'en'), '3.0 MB');
    expect(formatBytes(123456789, 'en'), '123 MB');
    expect(formatBytes(2500000000, 'en'), '2.5 GB');
    expect(formatBytes(3000000, 'fr'), '3,0 Mo');
  });

  test('dates follow the locale', () async {
    await initializeDateFormatting('fr');
    await initializeDateFormatting('en');
    final d = DateTime(2024, 3, 12);
    expect(formatDate(d, 'en'), 'Mar 12, 2024');
    expect(formatDate(d, 'fr'), '12 mars 2024');
  });
}
