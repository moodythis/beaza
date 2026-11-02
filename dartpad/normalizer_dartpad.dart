// Single-file version for dartpad.dev (no packages needed).
// Paste everything into DartPad and press Run. Each line prints PASS or FAIL.

class Normalizer {
  const Normalizer();
  static const String bhd = 'BHD';

  static final RegExp _bidiMarks =
      RegExp('[‎‏‪-‮⁦-⁩؜]');
  static final RegExp _diacriticsAndTatweel =
      RegExp('[ً-ٰٟـ]');
  static final RegExp _bhdLatin = RegExp(
    r'(?<![A-Za-z])(?:BHD|BD)(?![A-Za-z])',
    caseSensitive: false,
  );
  static final RegExp _bhdArabicDotted = RegExp(
    r'(?<!\p{L})د(?:\.\s?|\s\.)ب\.?(?!\p{L})',
    unicode: true,
  );
  static final RegExp _bhdArabicAfterNumber = RegExp(
    r'(\d)(\s?)د\s?ب(?!\p{L})',
    unicode: true,
  );
  static final RegExp _bhdArabicBeforeNumber = RegExp(
    r'(?<!\p{L})د\s?ب(\s?\d)',
    unicode: true,
  );
  static final RegExp _bhdArabicWord = RegExp(
    r'(?<!\p{L})دينار(?:\s+بحر[يىی]ن[يىی])?(?!\p{L})',
    unicode: true,
  );
  static final RegExp _whitespace = RegExp(r'\s+');

  String normalize(String input) {
    var text = input;
    text = text.replaceAll(_bidiMarks, '');
    text = _normalizeDigits(text);
    text = _normalizePunctuation(text);
    text = text.replaceAll(_diacriticsAndTatweel, '');
    text = _normalizeCurrency(text);
    return text.replaceAll(_whitespace, ' ').trim();
  }

  String _normalizeDigits(String s) {
    final out = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        out.writeCharCode(r - 0x0660 + 0x30);
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        out.writeCharCode(r - 0x06F0 + 0x30);
      } else {
        out.writeCharCode(r);
      }
    }
    return out.toString();
  }

  String _normalizePunctuation(String s) {
    return s
        .replaceAll('٫', '.')
        .replaceAll('٬', ',')
        .replaceAll('،', ',')
        .replaceAll('؛', ';')
        .replaceAll('؟', '?');
  }

  String _normalizeCurrency(String s) {
    return s
        .replaceAll(_bhdLatin, bhd)
        .replaceAll(_bhdArabicDotted, bhd)
        .replaceAllMapped(
          _bhdArabicAfterNumber,
          (m) => '${m[1]}${m[2]}$bhd',
        )
        .replaceAllMapped(
          _bhdArabicBeforeNumber,
          (m) => '$bhd${m[1]}',
        )
        .replaceAll(_bhdArabicWord, bhd);
  }
}

int passed = 0;
int failed = 0;

void check(String name, String actual, String expected) {
  if (actual == expected) {
    passed++;
    print('PASS  $name');
  } else {
    failed++;
    print('FAIL  $name\n  expected: $expected\n  actual:   $actual');
  }
}

void main() {
  const n = Normalizer();

  check('Arabic-Indic digits', n.normalize('تم خصم ١٢٫٥٠٠ د.ب'), 'تم خصم 12.500 BHD');
  check('Persian digits', n.normalize('۱۲٫۵'), '12.5');
  check('Thousands separator', n.normalize('١٬٢٣٤٫٥٠٠'), '1,234.500');
  check('Arabic comma', n.normalize('أ،ب'), 'أ,ب');
  check('Diacritics', n.normalize('كَتَب'), 'كتب');
  check('Tatweel', n.normalize('مــتـجر'), 'متجر');
  check('BD', n.normalize('Paid 5.000 BD at Cafe'), 'Paid 5.000 BHD at Cafe');
  check('bhd lowercase', n.normalize('Paid 5.000 bhd'), 'Paid 5.000 BHD');
  check('Longer Latin words untouched', n.normalize('ABD BDX'), 'ABD BDX');
  check('Dinar bahraini', n.normalize('مبلغ 3 دينار بحريني'), 'مبلغ 3 BHD');
  check('Dinar', n.normalize('مبلغ 3 دينار'), 'مبلغ 3 BHD');
  check('Dinar alef maqsura', n.normalize('مبلغ 4 دينار بحرينى'), 'مبلغ 4 BHD');
  check('Dinar Persian yeh', n.normalize('مبلغ 4 دينار بحرینی'), 'مبلغ 4 BHD');
  check('Dotted 1', n.normalize('1.500 د.ب.'), '1.500 BHD');
  check('Dotted 2', n.normalize('1.500 د. ب'), '1.500 BHD');
  check('Dotted 3', n.normalize('1.500 د .ب'), '1.500 BHD');
  check('Undotted next to number', n.normalize('1.500 د ب و 2.000 دب'), '1.500 BHD و 2.000 BHD');
  check('Undotted before number', n.normalize('دب 3.000'), 'BHD 3.000');
  check('Word bear untouched', n.normalize('دب كبير'), 'دب كبير');
  check('Word al-dub untouched', n.normalize('الدب الأبيض'), 'الدب الأبيض');
  check('Dubai untouched', n.normalize('5 دبي'), '5 دبي');
  check('Bidi marks', n.normalize('Cafe ‏مقهى‎ 1.500 BD'), 'Cafe مقهى 1.500 BHD');
  check('Arabic Letter Mark', n.normalize('Cafe ؜مقهى 1.500 BD'), 'Cafe مقهى 1.500 BHD');
  check('Whitespace', n.normalize('  Paid \n\t 5.000   BHD '), 'Paid 5.000 BHD');
  check('Empty', n.normalize(''), '');

  for (final s in [
    'تم خصم ١٢٫٥٠٠ د.ب من بطاقتك',
    'Purchase BD 2.300 at CAFE ROMA',
    'Cafe ‏مقهى‎ ١٫٥ دينار',
    '1.500 د.ب. و 2.000 د ب',
  ]) {
    final once = n.normalize(s);
    check('Idempotent: $s', n.normalize(once), once);
  }

  print('\n$passed passed, $failed failed');
}
