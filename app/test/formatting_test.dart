import 'package:beaza/ui/core/formatting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('formatFils', () {
    test('three decimals and grouping', () {
      expect(formatFils(0), '0.000');
      expect(formatFils(5333), '5.333');
      expect(formatFils(100), '0.100');
      expect(formatFils(1250000), '1,250.000');
      expect(formatFils(-2500), '-2.500');
      expect(formatFils(1250000, group: false), '1250.000');
    });
  });

  group('parseBhdToFils', () {
    test('plain amounts', () {
      expect(parseBhdToFils('2.5'), 2500);
      expect(parseBhdToFils('2'), 2000);
      expect(parseBhdToFils('2.'), 2000);
      expect(parseBhdToFils('.75'), 750);
      expect(parseBhdToFils(' 1.250 '), 1250);
    });

    test('Arabic digits and decimal signs', () {
      expect(parseBhdToFils('٣٫٥'), 3500);
      expect(parseBhdToFils('١٢٣'), 123000);
      expect(parseBhdToFils('۴.۲'), 4200);
      expect(parseBhdToFils('1,25'), 1250);
    });

    test('rejects non-positive and malformed input', () {
      expect(parseBhdToFils(''), isNull);
      expect(parseBhdToFils('.'), isNull);
      expect(parseBhdToFils('0'), isNull);
      expect(parseBhdToFils('0.000'), isNull);
      expect(parseBhdToFils('1.2345'), isNull);
      expect(parseBhdToFils('-1'), isNull);
      expect(parseBhdToFils('abc'), isNull);
      expect(parseBhdToFils('1.2.3'), isNull);
    });
  });

  test('Bahrain time is UTC+3', () {
    expect(formatBahrainTime(DateTime.utc(2026, 11, 1, 21, 5)), '00:05');
    expect(formatBahrainTime(DateTime.utc(2026, 11, 2, 6)), '09:00');
  });
}
