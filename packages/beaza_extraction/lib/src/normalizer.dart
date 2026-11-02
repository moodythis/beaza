/// Text normalization for bank and wallet messages (SRS FR-3.1).
///
/// Stage 2 of the extraction pipeline (Design, Section 3.1). It turns
/// Arabic, English and mixed messages into one predictable form so that
/// rules and models see the same digits, punctuation and currency tokens.
///
/// Pure Dart: no Flutter imports, so it also runs in the evaluation tool.
class Normalizer {
  const Normalizer();

  /// Canonical token used for the Bahraini dinar.
  static const String bhd = 'BHD';

  // Bidi marks and embeddings that mixed Arabic/English messages carry,
  // including the Arabic Letter Mark (U+061C) that Android adds.
  static final RegExp _bidiMarks =
      RegExp('[‎‏‪-‮⁦-⁩؜]');

  // Arabic diacritics (tashkeel), dagger alef and tatweel.
  static final RegExp _diacriticsAndTatweel =
      RegExp('[ً-ٰٟـ]');

  // BD or BHD as a standalone Latin word.
  static final RegExp _bhdLatin = RegExp(
    r'(?<![A-Za-z])(?:BHD|BD)(?![A-Za-z])',
    caseSensitive: false,
  );

  // Dotted abbreviation with at least one dot: د.ب  د. ب  د .ب  د.ب.
  static final RegExp _bhdArabicDotted = RegExp(
    r'(?<!\p{L})د(?:\.\s?|\s\.)ب\.?(?!\p{L})',
    unicode: true,
  );

  // Undotted forms (دب, د ب) are also the Arabic word for "bear" and part
  // of words like دبي, so they are replaced only when a digit is adjacent.
  static final RegExp _bhdArabicAfterNumber = RegExp(
    r'(\d)(\s?)د\s?ب(?!\p{L})',
    unicode: true,
  );
  static final RegExp _bhdArabicBeforeNumber = RegExp(
    r'(?<!\p{L})د\s?ب(\s?\d)',
    unicode: true,
  );

  // دينار or دينار بحريني (also typed with alef maqsura or Persian yeh).
  static final RegExp _bhdArabicWord = RegExp(
    r'(?<!\p{L})دينار(?:\s+بحر[يىی]ن[يىی])?(?!\p{L})',
    unicode: true,
  );

  static final RegExp _whitespace = RegExp(r'\s+');

  /// Returns the normalized form of [input].
  ///
  /// Idempotent: normalizing an already normalized string changes nothing.
  String normalize(String input) {
    var text = input;
    text = text.replaceAll(_bidiMarks, '');
    text = _normalizeDigits(text);
    text = _normalizePunctuation(text);
    text = text.replaceAll(_diacriticsAndTatweel, '');
    text = _normalizeCurrency(text);
    return text.replaceAll(_whitespace, ' ').trim();
  }

  /// Arabic-Indic (U+0660..0669) and Eastern Arabic-Indic (U+06F0..06F9)
  /// digits to Western digits.
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

  /// Arabic decimal and thousands separators and punctuation to ASCII.
  String _normalizePunctuation(String s) {
    return s
        .replaceAll('٫', '.') // Arabic decimal separator
        .replaceAll('٬', ',') // Arabic thousands separator
        .replaceAll('،', ',') // Arabic comma
        .replaceAll('؛', ';') // Arabic semicolon
        .replaceAll('؟', '?'); // Arabic question mark
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
