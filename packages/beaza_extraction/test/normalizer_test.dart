import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

void main() {
  const n = Normalizer();

  group('digits and separators', () {
    test('Arabic-Indic digits and decimal separator', () {
      expect(n.normalize('تم خصم ١٢٫٥٠٠ د.ب'), 'تم خصم 12.500 BHD');
    });

    test('Eastern Arabic-Indic (Persian) digits', () {
      expect(n.normalize('۱۲٫۵'), '12.5');
    });

    test('Arabic thousands separator and comma', () {
      expect(n.normalize('١٬٢٣٤٫٥٠٠'), '1,234.500');
      expect(n.normalize('أ،ب'), 'أ,ب');
    });
  });

  group('diacritics and tatweel', () {
    test('removes diacritics', () {
      expect(n.normalize('كَتَب'), 'كتب');
    });

    test('removes tatweel', () {
      expect(n.normalize('مــتـجر'), 'متجر');
    });
  });

  group('currency forms', () {
    test('BD and BHD become BHD', () {
      expect(n.normalize('Paid 5.000 BD at Cafe'), 'Paid 5.000 BHD at Cafe');
      expect(n.normalize('Paid 5.000 bhd'), 'Paid 5.000 BHD');
    });

    test('does not touch longer Latin words', () {
      expect(n.normalize('ABD BDX'), 'ABD BDX');
    });

    test('Arabic dinar words', () {
      expect(n.normalize('مبلغ 3 دينار بحريني'), 'مبلغ 3 BHD');
      expect(n.normalize('مبلغ 3 دينار'), 'مبلغ 3 BHD');
    });

    test('dinar with alef maqsura or Persian yeh', () {
      expect(n.normalize('مبلغ 4 دينار بحرينى'), 'مبلغ 4 BHD');
      expect(n.normalize('مبلغ 4 دينار بحرینی'), 'مبلغ 4 BHD');
    });

    test('dotted abbreviation variants', () {
      expect(n.normalize('1.500 د.ب.'), '1.500 BHD');
      expect(n.normalize('1.500 د. ب'), '1.500 BHD');
      expect(n.normalize('1.500 د .ب'), '1.500 BHD');
    });

    test('undotted abbreviation only next to a number', () {
      expect(n.normalize('1.500 د ب و 2.000 دب'), '1.500 BHD و 2.000 BHD');
      expect(n.normalize('دب 3.000'), 'BHD 3.000');
    });

    test('undotted letters elsewhere are not currency', () {
      expect(n.normalize('دب كبير'), 'دب كبير');
      expect(n.normalize('الدب الأبيض'), 'الدب الأبيض');
      expect(n.normalize('5 دبي'), '5 دبي');
    });
  });

  group('mixed text and whitespace', () {
    test('removes bidi marks', () {
      expect(n.normalize('Cafe ‏مقهى‎ 1.500 BD'), 'Cafe مقهى 1.500 BHD');
    });

    test('removes Arabic Letter Mark', () {
      expect(n.normalize('Cafe ؜مقهى 1.500 BD'), 'Cafe مقهى 1.500 BHD');
    });

    test('collapses whitespace', () {
      expect(n.normalize('  Paid \n\t 5.000   BHD '), 'Paid 5.000 BHD');
    });

    test('empty string', () {
      expect(n.normalize(''), '');
    });

    test('is idempotent', () {
      const samples = [
        'تم خصم ١٢٫٥٠٠ د.ب من بطاقتك',
        'Purchase BD 2.300 at CAFE ROMA',
        'Cafe ‏مقهى‎ ١٫٥ دينار',
        '1.500 د.ب. و 2.000 د ب',
      ];
      for (final s in samples) {
        final once = n.normalize(s);
        expect(n.normalize(once), once);
      }
    });
  });
}
