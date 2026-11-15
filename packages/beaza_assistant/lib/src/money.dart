/// Everyday Bahraini money words to fils, with rules only (no model), so the
/// same words always give the same amount, offline.
///
/// 1 dinar = 1000 fils. "ربية" (from the old Gulf rupee, ten to the dinar)
/// is 100 fils: "ربيتين" 200, "خمس ربيات" 500. "دينار ونص" is 1500,
/// "دينار وربع" 1250, "دينارين إلا ربع" 1750, "نص دينار" 500.
library;

import 'text.dart';

/// An amount found in a token list: tokens [start, end).
class MoneyMatch {
  const MoneyMatch(this.fils, this.start, this.end,
      {this.guessed = false, this.currency, this.original});

  final int fils;
  final int start;
  final int end;

  /// True when there was no unit ("كرك 200"): the unit was guessed, so the
  /// app must show it for confirmation.
  final bool guessed;

  /// Set when the person wrote another currency and [fils] is the
  /// conversion: its code ("USD") and the number as written ("300").
  final String? currency;
  final String? original;

  @override
  String toString() => 'MoneyMatch($fils, $start-$end${guessed ? ', guessed' : ''})';
}

const Map<String, int> kNumberWords = {
  'واحد': 1,
  'وحده': 1,
  'اثنين': 2,
  'ثنين': 2,
  'اثنان': 2,
  'ثلاث': 3,
  'ثلاثه': 3,
  'اربع': 4,
  'اربعه': 4,
  'خمس': 5,
  'خمسه': 5,
  'ست': 6,
  'سته': 6,
  'سبع': 7,
  'سبعه': 7,
  'ثمان': 8,
  'ثمانيه': 8,
  'ثمنيه': 8,
  'تسع': 9,
  'تسعه': 9,
  'عشر': 10,
  'عشره': 10,
  'one': 1,
  'two': 2,
  'three': 3,
  'four': 4,
  'five': 5,
  'six': 6,
  'seven': 7,
  'eight': 8,
  'nine': 9,
  'ten': 10,
};

const Set<String> _dinarUnits = {
  'دينار', 'دنانير', 'دب', 'bd', 'bhd', 'dinar', 'dinars', //
};
const Set<String> _rupeeUnits = {'ربيه', 'ربيات', 'روبيه', 'روبيات'};
const Set<String> _filsUnits = {'فلس', 'fils', 'fls'};

/// Words that are an amount on their own.
const Map<String, int> _dinarWords = {'دينار': 1000, 'دينارين': 2000};
const Map<String, int> _plainWords = {
  'ربيه': 100,
  'ربيتين': 200,
  'روبيه': 100,
  'روبيتين': 200,
  // Four annas, a quarter rupee: 25 fils (from the user, 4 Nov 2026).
  'اربعانه': 25,
};

/// A bare number followed by one of these is not money ("آخر 7 أيام").
const Set<String> _notMoneyAfter = {
  'يوم', 'ايام', 'اسبوع', 'اسابيع', 'شهر', 'شهور', 'ساعه', 'ساعات', //
  'دقيقه', 'دقايق', 'مره', 'مرات', '%', '٪', 'بالميه', 'day', 'days', //
  'week', 'weeks', 'month', 'months', 'times', 'hours', 'percent',
};

/// Another currency: a number next to one is not dinars or fils ("300 دولار"
/// is not 300 fils).
const Set<String> _otherCurrency = {
  'دولار', 'دولارات', 'دولارين', 'ريال', 'ريالات', 'ريالين', 'درهم', 'دراهم', //
  'يورو', 'dollar', 'dollars', 'usd', 'kd', 'sar', 'aed', 'eur', 'euro', //
  'euros', 'riyal', r'us$', 'kwd', 'omr', 'qar', 'gbp', 'جنيه', 'جنيهات', //
  'ليره', 'riyals', 'dirham', 'dirhams', r'$', '€', '£', 'bucks', //
  'buck', 'دولارا', 'ريالا', 'pound', 'pounds',
};

/// [w] is another currency, with a joined "ب", "ال" or "و" ("بالدولار").
bool _isOtherCurrency(String w) {
  if (_otherCurrency.contains(w)) return true;
  for (final p in const ['وبال', 'بال', 'وال', 'ال', 'وب', 'ب', 'و', 'ل']) {
    if (w.length > p.length + 1 &&
        w.startsWith(p) &&
        _otherCurrency.contains(w.substring(p.length))) {
      return true;
    }
  }
  return false;
}

/// Milli-fils (thousandths of a fil) for one unit of a neighbouring currency.
///
/// The dollar, riyal, dirham and Qatari riyal are pegged to the US dollar,
/// and the dinar is pegged at 1 USD = 0.376 BHD, so these four are fixed:
/// 1 USD = 376 fils, 1 SAR = 376 / 3.75, 1 AED = 376 / 3.6725, 1 QAR =
/// 376 / 3.64. The Kuwaiti dinar is not pegged to one currency: 1 KWD =
/// 1.2073 BHD on 15 Nov 2026 (moneyconvert.net, mid-market). It moves a
/// little, so a reply that uses it says "about".
const Map<String, int> kForeignMilliFils = {
  'USD': 376000,
  'SAR': 100267,
  'AED': 102383,
  'QAR': 103297,
  'KWD': 1207300,
};

/// The currencies whose rate is not fixed: the reply says "about".
const Set<String> kApproximateCurrencies = {'KWD'};

const Map<String, String> _currencyCodes = {
  'دولار': 'USD', 'دولارات': 'USD', 'دولارين': 'USD', 'دولارا': 'USD', //
  'dollar': 'USD', 'dollars': 'USD', 'usd': 'USD', r'us$': 'USD', r'$': 'USD',
  'bucks': 'USD', 'buck': 'USD',
  'ريال': 'SAR', 'ريالات': 'SAR', 'ريالين': 'SAR', 'ريالا': 'SAR',
  'riyal': 'SAR', 'riyals': 'SAR', 'sar': 'SAR',
  'qar': 'QAR',
  'درهم': 'AED', 'دراهم': 'AED', 'dirham': 'AED', 'dirhams': 'AED', 'aed': 'AED',
  'kd': 'KWD', 'kwd': 'KWD',
};

/// Names that follow a riyal and make it another riyal.
const Set<String> _qatari = {'قطري', 'قطر', 'qatari'};
const Set<String> _otherRiyal = {'عماني', 'عمان', 'omani', 'يمني', 'ايراني'};

class _Foreign {
  const _Foreign(this.code, this.end);
  final String code;
  final int end;
}

/// A supported currency word at token [j] (with a joined "ب", "ال", "و"), and
/// where it ends. "ريال" alone is the Saudi riyal.
_Foreign? _foreignAt(List<String> t, int j) {
  if (j >= t.length) return null;
  String? code = _currencyCodes[t[j]];
  if (code == null) {
    for (final p in const ['وبال', 'بال', 'وال', 'ال', 'وب', 'ب', 'و', 'ل']) {
      if (t[j].length > p.length + 1 && t[j].startsWith(p)) {
        code = _currencyCodes[t[j].substring(p.length)];
        if (code != null) break;
      }
    }
  }
  if (code == null) return null;
  final next = j + 1 < t.length ? t[j + 1] : '';
  if (code == 'SAR') {
    if (_qatari.contains(next)) return _Foreign('QAR', j + 2);
    if (_otherRiyal.contains(next)) return null;
    if (next == 'سعودي' || next == 'saudi') return _Foreign('SAR', j + 2);
  }
  if (code == 'AED' && (next == 'اماراتي' || next == 'emirati')) {
    return _Foreign('AED', j + 2);
  }
  return _Foreign(code, j + 1);
}

enum _Unit { dinar, rupee, fils }

/// The word without a joined "ب", "و", "وب" or "ل" when that makes it pass
/// [ok] ("بربيتين" is "ربيتين").
String? stripJoined(String w, bool Function(String) ok) {
  if (ok(w)) return w;
  for (final p in const ['وب', 'ب', 'و', 'ل']) {
    if (w.length > p.length + 1 && w.startsWith(p)) {
      final rest = w.substring(p.length);
      if (ok(rest)) return rest;
    }
  }
  return null;
}

class _Part {
  const _Part(this.fils, this.end,
      {this.guessed = false, this.currency, this.original});
  final int fils;
  final int end;
  final bool guessed;
  final String? currency;
  final String? original;
}

/// [number] units of [code] in fils, rounded to the nearest fil. Null for
/// zero, a text that is not a plain number, or an amount over a million.
_Part? _converted(String number, String code, int end) {
  final milli = decimalToFils(number);
  final rate = kForeignMilliFils[code];
  if (milli == null || rate == null || milli > 1000000000) return null;
  final fils = (milli * rate + 500000) ~/ 1000000;
  if (fils <= 0) return null;
  return _Part(fils, end, currency: code, original: number);
}

class BahrainiMoneyParser {
  const BahrainiMoneyParser();

  /// The single amount in [text], or null when there is none or more than one.
  int? parse(String text) {
    final all = findAll(tokenize(text));
    return all.length == 1 ? all.single.fils : null;
  }

  /// A number written next to another currency ("300 دولار") and no
  /// amount in dinars or fils: the question is about money in a currency the
  /// app does not count.
  bool onlyOtherCurrency(List<String> tokens) {
    // A bare number with no unit ("على 2 تذاكر") is only a guess, so it does
    // not count as an amount in dinars.
    if (findAll(tokens).any((m) => !m.guessed)) return false;
    for (var i = 0; i < tokens.length; i++) {
      if (!isNumberToken(tokens[i])) continue;
      if ((i + 1 < tokens.length && _isOtherCurrency(tokens[i + 1])) ||
          (i > 0 && _isOtherCurrency(tokens[i - 1])) ||
          // "20 دينار كويتي"
          (i + 2 < tokens.length &&
              _dinarUnits.contains(tokens[i + 1]) &&
              const {'كويتي', 'kuwaiti'}.contains(tokens[i + 2]))) {
        return true;
      }
    }
    return false;
  }

  /// Every amount in [tokens] (from [tokenize]), left to right.
  List<MoneyMatch> findAll(List<String> tokens) {
    final out = <MoneyMatch>[];
    var i = 0;
    while (i < tokens.length) {
      final m = _amountAt(tokens, i);
      if (m == null) {
        i++;
        continue;
      }
      out.add(m);
      i = m.end;
    }
    return out;
  }

  MoneyMatch? _amountAt(List<String> t, int i) {
    final first = _part(t, i, allowBare: true);
    if (first == null) return null;
    var fils = first.fils;
    var end = first.end;
    // "4 دنانير و5 ربيات", "دينار و200 فلس": parts joined by "و".
    while (first.currency == null) {
      final next = _joined(t, end);
      if (next == null) break;
      fils += next.fils;
      end = next.end;
    }
    if (fils <= 0) return null;
    return MoneyMatch(fils, i, end,
        guessed: first.guessed,
        currency: first.currency,
        original: first.original);
  }

  _Part? _joined(List<String> t, int j) {
    if (j >= t.length) return null;
    if (t[j] == 'و') return _part(t, j + 1, allowBare: false);
    if (t[j].length > 1 && t[j].startsWith('و')) {
      final copy = [...t];
      copy[j] = t[j].substring(1);
      return _part(copy, j, allowBare: false);
    }
    return null;
  }

  _Unit? _unitAt(List<String> t, int j) {
    if (j >= t.length) return null;
    final w = t[j];
    if (_dinarUnits.contains(w)) return _Unit.dinar;
    if (_rupeeUnits.contains(w)) return _Unit.rupee;
    if (_filsUnits.contains(w)) return _Unit.fils;
    return null;
  }

  _Part? _part(List<String> t, int i, {required bool allowBare}) {
    if (i >= t.length) return null;
    final w = t[i];

    // Another currency first: "USD 300", "$300", "KD 20".
    final lead = _foreignAt(t, i);
    if (lead != null &&
        lead.end < t.length &&
        isNumberToken(t[lead.end]) &&
        _unitAt(t, lead.end + 1) == null) {
      return _converted(t[lead.end], lead.code, lead.end + 1);
    }

    // Currency first: "BD 2.500", "د.ب 2.5".
    if (_dinarUnits.contains(w) &&
        i + 1 < t.length &&
        isNumberToken(t[i + 1])) {
      final f = decimalToFils(t[i + 1]);
      return f == null ? null : _fraction(t, i + 2, f);
    }

    final number = isNumberToken(w) ? w : null;
    final word = number == null
        ? stripJoined(w, kNumberWords.containsKey)
        : null;
    if (number != null || word != null) {
      // "اربع آنة" written apart is the same 25 fils.
      if ((word != null ? kNumberWords[word] : int.tryParse(number!)) == 4 &&
          i + 1 < t.length &&
          (t[i + 1] == 'انه' || t[i + 1] == 'انات')) {
        return _Part(25, i + 2);
      }
      final unit = _unitAt(t, i + 1);
      final whole = number != null ? int.tryParse(number) : kNumberWords[word];
      // "ثلاث ارباع (دينار)" is three quarters of a dinar.
      if (whole == 3 && i + 1 < t.length && t[i + 1] == 'ارباع') {
        return _Part(750, _unitAt(t, i + 2) == _Unit.dinar ? i + 3 : i + 2);
      }
      switch (unit) {
        case _Unit.dinar:
          // "20 دينار كويتي" is Kuwaiti dinars, not Bahraini.
          if (i + 2 < t.length && const {'كويتي', 'kuwaiti'}.contains(t[i + 2])) {
            return number == null ? null : _converted(number, 'KWD', i + 3);
          }
          final f = number != null ? decimalToFils(number) : whole! * 1000;
          return f == null ? null : _fraction(t, i + 2, f);
        case _Unit.rupee:
          return whole == null ? null : _Part(whole * 100, i + 2);
        case _Unit.fils:
          return whole == null ? null : _Part(whole, i + 2);
        case null:
          if (number == null || !allowBare) return null;
          final after = _foreignAt(t, i + 1);
          if (after != null) return _converted(number, after.code, after.end);
          if ((i + 1 < t.length && _isOtherCurrency(t[i + 1])) ||
              (i > 0 && _isOtherCurrency(t[i - 1]))) {
            return null;
          }
          return _bare(t, i, number);
      }
    }

    final dinarWord = stripJoined(w, _dinarWords.containsKey);
    // The "دينار" left behind after "20 دينار كويتي" was turned down is not
    // a dinar of its own.
    if (dinarWord != null &&
        ((i > 0 && isNumberToken(t[i - 1])) ||
            (i + 1 < t.length && const {'كويتي', 'kuwaiti'}.contains(t[i + 1])))) {
      return null;
    }
    if (dinarWord != null) return _fraction(t, i + 1, _dinarWords[dinarWord]!);
    final plain = stripJoined(w, _plainWords.containsKey);
    if (plain != null) return _Part(_plainWords[plain]!, i + 1);

    // "نص دينار", "ربع دينار".
    final half = stripJoined(w, const {'نص', 'نصف', 'ربع'}.contains);
    if (half != null && _unitAt(t, i + 1) == _Unit.dinar) {
      return _Part(half == 'ربع' ? 250 : 500, i + 2);
    }
    // "نص ربية" is 50 fils (from the user, 4 Nov 2026).
    if (half != null && half != 'ربع' && _unitAt(t, i + 1) == _Unit.rupee) {
      return _Part(50, i + 2);
    }
    return null;
  }

  /// A number with no unit: under 100 is dinars ("عشا 4"), 100 or more is
  /// fils ("كرك 200"), a decimal is dinars ("2.5"). Always marked guessed.
  _Part? _bare(List<String> t, int i, String number) {
    if (i + 1 < t.length && _notMoneyAfter.contains(t[i + 1])) return null;
    if (number.contains('.')) {
      final f = decimalToFils(number);
      return f == null ? null : _Part(f, i + 1, guessed: true);
    }
    final n = int.parse(number);
    if (n <= 0 || n > 9999) return null;
    return _Part(n < 100 ? n * 1000 : n, i + 1, guessed: true);
  }

  /// "ونص" +500, "وربع" +250, "إلا ربع" -250 after a dinar amount.
  _Part _fraction(List<String> t, int j, int base) {
    String at(int k) => k < t.length ? t[k] : '';
    // "دينار ونص ربية" is a dinar and half a rupee, not a dinar and a half.
    if (_rupeeUnits.contains(at(j + 1)) || _rupeeUnits.contains(at(j + 2))) {
      return _Part(base, j);
    }
    if (at(j) == 'ونص' || at(j) == 'ونصف') return _Part(base + 500, j + 1);
    if (at(j) == 'وربع') return _Part(base + 250, j + 1);
    if (at(j) == 'و' && (at(j + 1) == 'نص' || at(j + 1) == 'نصف')) {
      return _Part(base + 500, j + 2);
    }
    if (at(j) == 'و' && at(j + 1) == 'ربع') return _Part(base + 250, j + 2);
    if ((at(j) == 'الا' || at(j) == 'غير') && at(j + 1) == 'ربع') {
      return _Part(base - 250, j + 2);
    }
    return _Part(base, j);
  }
}

/// "2.5" is 2500 fils, "2.050" is 2050, "3" is 3000. More than three decimal
/// places is not a Bahraini amount: null.
int? decimalToFils(String s) {
  final p = s.split('.');
  final whole = int.tryParse(p[0]);
  if (whole == null) return null;
  if (p.length == 1) return whole * 1000;
  if (p.length != 2 || p[1].isEmpty || p[1].length > 3) return null;
  return whole * 1000 + int.parse(p[1].padRight(3, '0'));
}
