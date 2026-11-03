/// Text clean-up shared by the parsers: Arabic letter forms, Arabic digits,
/// and splitting into words with numbers kept whole ("2.500").
library;

const Map<String, String> _charMap = {
  'أ': 'ا',
  'إ': 'ا',
  'آ': 'ا',
  'ٱ': 'ا',
  'ة': 'ه',
  'ى': 'ي',
  'ؤ': 'و',
  'ئ': 'ي',
  'ـ': '', // tatweel: "بـ 800"
  '٫': '.', // Arabic decimal separator
  '٬': '',
  '،': ' ',
  '؛': ' ',
  '؟': ' ',
};

/// Lower case, one form per Arabic letter, ASCII digits, no diacritics.
String normalizeText(String input) {
  final b = StringBuffer();
  for (final r in input.runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else if (r >= 0x064B && r <= 0x0652) {
      // Short vowels and shadda are dropped.
    } else {
      final c = String.fromCharCode(r);
      b.write(_charMap[c] ?? c);
    }
  }
  return b.toString().toLowerCase();
}

final RegExp _number = RegExp(r'^\d+(?:\.\d+)?$');

bool isNumberToken(String t) => _number.hasMatch(t);

/// Words and numbers. "بـ800فلس" gives ["ب", "800", "فلس"] and "د.ب" gives
/// "دب", so one word list covers both spellings.
List<String> tokenize(String input) {
  var s = normalizeText(input);
  s = s.replaceAll(RegExp(r'د\s*\.\s*ب'), ' دب ');
  s = s.replaceAll(RegExp(r'\bb\.\s?d\b\.?'), ' bd ');
  s = s.replaceAllMapped(
      RegExp(r'(\d)([^\d\s.,])'), (m) => '${m[1]} ${m[2]}');
  s = s.replaceAllMapped(
      RegExp(r'([^\d\s.,])(\d)'), (m) => '${m[1]} ${m[2]}');
  final out = <String>[];
  for (var t in s.split(RegExp(r'[\s,;:!?"()\[\]{}/\\|*+=<>«»\-]+'))) {
    t = t.replaceAll(RegExp(r'^\.+|\.+$'), '');
    if (!isNumberToken(t)) t = t.replaceAll('.', '');
    if (t.isNotEmpty) out.add(t);
  }
  return out;
}

/// True when [text] has Arabic letters.
bool isArabic(String text) => RegExp(r'[؀-ۿ]').hasMatch(text);
