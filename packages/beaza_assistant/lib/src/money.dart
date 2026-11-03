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
  const MoneyMatch(this.fils, this.start, this.end, {this.guessed = false});

  final int fils;
  final int start;
  final int end;

  /// True when there was no unit ("كرك 200"): the unit was guessed, so the
  /// app must show it for confirmation.
  final bool guessed;

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
};

/// A bare number followed by one of these is not money ("آخر 7 أيام").
const Set<String> _notMoneyAfter = {
  'يوم', 'ايام', 'اسبوع', 'اسابيع', 'شهر', 'شهور', 'ساعه', 'ساعات', //
  'دقيقه', 'دقايق', 'مره', 'مرات', '%', '٪', 'بالميه', 'day', 'days', //
  'week', 'weeks', 'month', 'months', 'times', 'hours', 'percent',
};

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
  const _Part(this.fils, this.end, {this.guessed = false});
  final int fils;
  final int end;
  final bool guessed;
}

class BahrainiMoneyParser {
  const BahrainiMoneyParser();

  /// The single amount in [text], or null when there is none or more than one.
  int? parse(String text) {
    final all = findAll(tokenize(text));
    return all.length == 1 ? all.single.fils : null;
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
    while (true) {
      final next = _joined(t, end);
      if (next == null) break;
      fils += next.fils;
      end = next.end;
    }
    if (fils <= 0) return null;
    return MoneyMatch(fils, i, end, guessed: first.guessed);
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
      final unit = _unitAt(t, i + 1);
      final whole = number != null ? int.tryParse(number) : kNumberWords[word];
      switch (unit) {
        case _Unit.dinar:
          final f = number != null ? decimalToFils(number) : whole! * 1000;
          return f == null ? null : _fraction(t, i + 2, f);
        case _Unit.rupee:
          return whole == null ? null : _Part(whole * 100, i + 2);
        case _Unit.fils:
          return whole == null ? null : _Part(whole, i + 2);
        case null:
          if (number == null || !allowBare) return null;
          return _bare(t, i, number);
      }
    }

    final dinarWord = stripJoined(w, _dinarWords.containsKey);
    if (dinarWord != null) return _fraction(t, i + 1, _dinarWords[dinarWord]!);
    final plain = stripJoined(w, _plainWords.containsKey);
    if (plain != null) return _Part(_plainWords[plain]!, i + 1);

    // "نص دينار", "ربع دينار".
    final half = stripJoined(w, const {'نص', 'نصف', 'ربع'}.contains);
    if (half != null && _unitAt(t, i + 1) == _Unit.dinar) {
      return _Part(half == 'ربع' ? 250 : 500, i + 2);
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
