import 'package:beaza_assistant/beaza_assistant.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

void main() {
  const parser = ExpenseParser();
  final now = DateTime.utc(2026, 11, 4, 10);

  String show(List<DraftTransaction> d) => d
      .map((x) => '${x.amountFils}|${x.merchantRaw}|${x.category}${x.amountGuessed ? '|?' : ''}')
      .join(', ');

  test('two items in one sentence', () {
    expect(show(parser.parse('شريت شاورما بـ 800 فلس وكرك بـ 200 فلس', now)),
        '800|شاورما|food, 200|كرك|food');
  });

  test('the shop after the amount', () {
    expect(show(parser.parse('دفعت دينار ونص في البرادة', now)),
        '1500|البراده|groceries');
  });

  test('dinars and rupees together', () {
    expect(show(parser.parse('عشانا طلع 4 دنانير و5 ربيات', now)),
        '4500|عشانا|food');
  });

  test('a dinar and eight rupees', () {
    expect(show(parser.parse('غدانا طلع دينار وثمان ربيات', now)),
        '1800|غدانا|food');
  });

  test('no unit: the draft is marked for checking', () {
    expect(show(parser.parse('كرك 200', now)), '200|كرك|food|?');
  });

  test('yesterday moves the time back one day', () {
    final d = parser.parse('امس شريت بنزين بدينارين', now).single;
    expect(d.amountFils, 2000);
    expect(d.merchantRaw, 'بنزين');
    expect(d.category, 'transport');
    expect(d.timestamp, now.subtract(const Duration(days: 1)));
  });

  test('English, with the shop dictionary for the category', () {
    expect(show(parser.parse('coffee 0.800 BD', now)), '800|coffee|food');
  });

  test('words from an earlier sentence do not stick to the next item', () {
    // What a phone's speech screen gave on 4 Nov 2026, plus a second try.
    final d = parser.parse(
        'is charitra beta، change language to arabic، شريت كرك بربيتين', now);
    expect(show(d), '200|كرك|food');
  });

  test('one item per line', () {
    expect(show(parser.parse('شاورما 800 فلس\nكرك 200 فلس', now)),
        '800|شاورما|food, 200|كرك|food');
  });

  test('at most three words name an item', () {
    final d = parser.parse('اليوم رحت السوق وشريت قهوة مثلجة كبيرة بدينار', now);
    expect(d.single.merchantRaw, 'قهوه مثلجه كبيره');
    expect(d.single.category, 'food');
  });

  test('nothing to add', () {
    expect(parser.parse('مرحبا', now), isEmpty);
  });

  test('a confirmed draft becomes a BHD purchase', () {
    final r = parser.parse('كرك بربيتين', now).single.toResult();
    expect(r.amountFils, 200);
    expect(r.currency, 'BHD');
    expect(r.type, TxnType.purchase);
    expect(r.direction, TxDirection.outgoing);
    expect(r.timestamp, now);
    expect(r.category, 'food');
  });
}
