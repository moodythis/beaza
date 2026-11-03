import 'package:beaza_assistant/beaza_assistant.dart';
import 'package:test/test.dart';

void main() {
  const p = BahrainiMoneyParser();

  group('Bahraini money words', () {
    final cases = {
      'ربية': 100,
      'ربيه': 100,
      'ربيتين': 200,
      'بربيتين': 200,
      'خمس ربيات': 500,
      'بخمس ربيات': 500,
      'نص دينار': 500,
      'دينار ونص': 1500,
      'دينار و نص': 1500,
      'دينار وربع': 1250,
      'دينارين': 2000,
      'دينارين الا ربع': 1750,
      'دينارين إلا ربع': 1750,
      'ثلاث دنانير ونص': 3500,
      'عشر دنانير': 10000,
      '3 دنانير': 3000,
      '4 دنانير و5 ربيات': 4500,
      // A dinar is ten rupees (from the user, 4 Nov 2026).
      'دينار وثمان ربيات': 1800,
      'دينار و ثمان ربيات': 1800,
      'دينار و8 ربيات': 1800,
      'عشر ربيات': 1000,
      'تسع ربيات': 900,
      'ثلاث ربيات': 300,
      // Four annas = a quarter rupee = 25 fils.
      'اربعانه': 25,
      'أربعانة': 25,
      'باربعانه': 25,
      'اربع آنة': 25,
      'ربية واربعانه': 125,
      'دينار و200 فلس': 1200,
      '800 فلس': 800,
      '800فلس': 800,
      'بـ 800 فلس': 800,
      '2.500 د.ب': 2500,
      '2.5 BD': 2500,
      'BD 2.500': 2500,
      'bhd 0.750': 750,
      '٢٫٥٠٠ د.ب': 2500,
      '٨٠٠ فلس': 800,
    };
    for (final e in cases.entries) {
      test(e.key, () => expect(p.parse(e.key), e.value));
    }
  });

  group('not money, or not one amount', () {
    test('no amount', () => expect(p.parse('مرحبا كيف الحال'), isNull));
    test('a number of days', () => expect(p.parse('آخر 7 أيام'), isNull));
    test('more than three decimals', () => expect(p.parse('2.5555 BD'), isNull));
    test('a number word alone', () => expect(p.parse('خمس'), isNull));
    test('two separate amounts', () {
      expect(p.parse('شاورما 800 فلس وكرك 200 فلس'), isNull);
      expect(p.findAll(tokenize('شاورما 800 فلس وكرك 200 فلس')).map((m) => m.fils),
          [800, 200]);
    });
  });

  group('no unit written: guessed and marked', () {
    test('100 or more is fils', () {
      final m = p.findAll(tokenize('كرك 200')).single;
      expect(m.fils, 200);
      expect(m.guessed, isTrue);
    });
    test('under 100 is dinars', () {
      expect(p.findAll(tokenize('عشا 4')).single.fils, 4000);
    });
    test('a decimal is dinars', () {
      expect(p.findAll(tokenize('غدا 1.5')).single.fils, 1500);
    });
    test('with a unit it is not guessed', () {
      expect(p.findAll(tokenize('كرك 200 فلس')).single.guessed, isFalse);
    });
  });

  test('decimal to fils', () {
    expect(decimalToFils('2.05'), 2050);
    expect(decimalToFils('0.8'), 800);
    expect(decimalToFils('3'), 3000);
    expect(decimalToFils('1.2345'), isNull);
  });

  test('tokenize keeps numbers whole and splits joined letters', () {
    expect(tokenize('بـ800فلس، و2.500 د.ب.'), ['ب', '800', 'فلس', 'و', '2.500', 'دب']);
  });
}
