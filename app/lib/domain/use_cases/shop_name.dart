/// A shop name fit to show in a tip or to send: no digits (Western, Arabic
/// or Persian, so no card, phone, CPR or branch number), one space between
/// words, at most 40 characters. Null when nothing readable is left.
String? cleanShopName(String? raw) {
  if (raw == null) return null;
  final s = raw
      .replaceAll(RegExp(r'[0-9٠-٩۰-۹]'), '')
      .replaceAll(RegExp(r'[*#@+]'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^[\s\-–.,/]+|[\s\-–.,/]+$'), '')
      .trim();
  if (s.length < 2) return null;
  return s.length <= 40 ? s : s.substring(0, 40).trim();
}
