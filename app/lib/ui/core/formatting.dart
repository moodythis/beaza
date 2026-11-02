/// Display and input helpers. Money is always integer fils (1 BHD = 1000).
library;

import 'package:beaza_extraction/beaza_extraction.dart' show kBahrainOffset;

final RegExp _thousands = RegExp(r'\B(?=(\d{3})+(?!\d))');

/// 3500 -> "3.500", 1250000 -> "1,250.000". Western digits in both
/// languages, as in Bahraini bank messages.
String formatFils(int fils, {bool group = true}) {
  final abs = fils.abs();
  var whole = (abs ~/ 1000).toString();
  if (group) whole = whole.replaceAll(_thousands, ',');
  final frac = (abs % 1000).toString().padLeft(3, '0');
  return '${fils < 0 ? '-' : ''}$whole.$frac';
}

final RegExp _amount = RegExp(r'^(\d{0,6})(?:\.(\d{0,3}))?$');

/// Parses what the user typed into fils. Accepts Arabic-Indic digits and
/// "," or the Arabic decimal sign as the decimal point (some keyboards show
/// them instead of "."). Returns null for anything that is not a positive
/// amount with at most three decimals.
int? parseBhdToFils(String input) {
  final b = StringBuffer();
  for (final r in input.trim().runes) {
    if (r >= 0x0660 && r <= 0x0669) {
      b.writeCharCode(0x30 + r - 0x0660);
    } else if (r >= 0x06F0 && r <= 0x06F9) {
      b.writeCharCode(0x30 + r - 0x06F0);
    } else if (r == 0x066B || r == 0x2C) {
      b.write('.');
    } else {
      b.writeCharCode(r);
    }
  }
  final m = _amount.firstMatch(b.toString());
  if (m == null) return null;
  final wholeText = m.group(1)!;
  final fracText = m.group(2) ?? '';
  if (wholeText.isEmpty && fracText.isEmpty) return null;
  final whole = wholeText.isEmpty ? 0 : int.parse(wholeText);
  final fils = whole * 1000 + int.parse(fracText.padRight(3, '0'));
  return fils > 0 ? fils : null;
}

/// "HH:mm" in Bahrain time for a stored UTC instant.
String formatBahrainTime(DateTime instant) {
  final t = instant.toUtc().add(kBahrainOffset);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(t.hour)}:${two(t.minute)}';
}
