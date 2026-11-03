import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

void main() {
  const n = MerchantNormalizer();

  String show(String raw) {
    final m = n.normalize(raw)!;
    return '${m.name}|${m.category}|${m.source}';
  }

  group('real NBB merchant fields (city glued on, fixed width)', () {
    test('known chains by alias', () {
      expect(show('REDTAG MANAMA'), 'Redtag|shopping|alias');
      expect(show('DAY TO DAY DISCOUNT CEMANAMA'), 'Day To Day|groceries|alias');
    });

    test('the city is cut off, also when glued to the last word', () {
      expect(show('GOLDEN COLLECTION PERFMANAMA'), 'Golden Collection Perf|shopping|keyword');
      expect(show('NOOR ALWLAYA REST MALKIYA'), 'Noor Alwlaya Rest|food|keyword');
      expect(show('SHAHAD ALZAFARAN ROASTMANAMA'), 'Shahad Alzafaran Roast|food|keyword');
    });

    test('keywords give a category, the legal suffix goes', () {
      expect(show('AL ATAA COLDSTORE WLL MALKIYA'), 'Al Ataa Coldstore|groceries|keyword');
      expect(show('ABED BAKERY MANAMA'), 'Abed Bakery|food|keyword');
    });

    test('an unknown shop is cleaned but not categorised', () {
      expect(show('Waleed Al Kabah MANAMA'), 'Waleed Al Kabah|null|none');
    });
  });

  group('other formats', () {
    test('store numbers and branch codes are dropped', () {
      expect(show('SAMPLE BAKERY - MAL BAH BH-000001'), 'Sample Bakery - Mal Bah|food|keyword');
      expect(show('GOOGLE *SAMPLE APP g #US-000001'), 'Google|entertainment|alias');
    });

    test('an alias beats the surrounding words', () {
      expect(show('COSTA COFFEE SEEF MALL'), 'Costa Coffee|food|alias');
      expect(show('TALABAT BAHRAIN'), 'Talabat|food|alias');
    });

    test('Arabic names', () {
      expect(show('طلبات'), 'Talabat|food|alias');
      expect(show('مطعم النخيل'), 'مطعم النخيل|food|keyword');
    });

    test('fuel stations are transport, even with "mart" in the name', () {
      expect(show('PETRO MART WLL'), 'Petro Mart|transport|keyword');
    });

    test('a city is not cut from a name that only ends like one', () {
      expect(show('AL MASAAR'), 'Al Masaar|null|none');
      expect(show('SAAR'), 'Saar|null|none');
    });

    test('empty or missing', () {
      expect(n.normalize(null), isNull);
      expect(n.normalize('   '), isNull);
    });

    test('every category in the dictionary is one of the allowed ten', () {
      for (final raw in [
        'TALABAT', 'LULU', 'REDTAG', 'UBER', 'BATELCO', 'NETFLIX', 'PHARMACY X',
        'SCHOOL Y', 'CINEMA Z',
      ]) {
        expect(kCategories, contains(n.normalize(raw)!.category), reason: raw);
      }
      expect(kCategories.length, lessThanOrEqualTo(10));
    });
  });

  group('inside the pipeline', () {
    final x = BeazaExtractor();

    test('a card purchase keeps the raw text and gets name and category', () {
      final r = x.process(RawMessage(
          text:
              'Thank you for using NBB Debit Card at ABED BAKERY           MANAMA for BHD3.900 on 31/10/2026 14:02, A/C ending 4810 balance BHD99.999.',
          sender: 'NBB',
          receivedAt: DateTime.utc(2026, 10, 31, 11, 3)));
      expect(r.merchantRaw, 'ABED BAKERY MANAMA');
      expect(r.merchantNorm, 'Abed Bakery');
      expect(r.category, 'food');
    });

    test('a transfer has no merchant, so nothing is added', () {
      final r = x.process(RawMessage(
          text:
              'Successful Fawri+ transfer of BHD1.600 credited to BHXALSAXX9417 on 24/10/2026 11:55, Ref.NBB241026ONH8WCQ, A/C ending 4810 balance BHD99.999.',
          sender: 'NBB',
          receivedAt: DateTime.utc(2026, 10, 24, 8, 56)));
      expect(r.merchantNorm, isNull);
      expect(r.category, isNull);
    });
  });
}
