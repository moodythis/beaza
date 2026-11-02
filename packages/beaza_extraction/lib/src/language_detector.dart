/// Language label of a message (SRS FR-3.2).
enum MessageLanguage { arabic, english, mixed, unknown }

/// Detects whether a normalized message is Arabic, English or mixed.
///
/// It compares the number of Arabic and Latin letters. Digits, punctuation
/// and the currency token BHD are ignored, because every message carries
/// them whatever its language. The two thresholds are starting values and
/// must be tuned on the collected Bahraini messages (RQ2).
class LanguageDetector {
  const LanguageDetector({
    this.arabicShareHigh = 0.8,
    this.arabicShareLow = 0.2,
  });

  /// Arabic share at or above this value means the message is Arabic.
  final double arabicShareHigh;

  /// Arabic share at or below this value means the message is English.
  final double arabicShareLow;

  static final RegExp _currencyToken = RegExp(r'(?<![A-Za-z])BHD(?![A-Za-z])');

  /// Expects text already processed by `Normalizer`.
  MessageLanguage detect(String normalizedText) {
    final text = normalizedText.replaceAll(_currencyToken, ' ');
    var arabicCount = 0;
    var latinCount = 0;
    for (final r in text.runes) {
      if (_isArabicLetter(r)) {
        arabicCount++;
      } else if (_isLatinLetter(r)) {
        latinCount++;
      }
    }
    final total = arabicCount + latinCount;
    if (total == 0) {
      return MessageLanguage.unknown;
    }
    final arabicShare = arabicCount / total;
    if (arabicShare >= arabicShareHigh) {
      return MessageLanguage.arabic;
    }
    if (arabicShare <= arabicShareLow) {
      return MessageLanguage.english;
    }
    return MessageLanguage.mixed;
  }

  static bool _isLatinLetter(int r) =>
      (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A);

  static bool _isArabicLetter(int r) =>
      (r >= 0x0621 && r <= 0x064A) ||
      (r >= 0x066E && r <= 0x066F) ||
      (r >= 0x0671 && r <= 0x06D3) ||
      r == 0x06D5 ||
      (r >= 0x06FA && r <= 0x06FF) ||
      (r >= 0x0750 && r <= 0x077F) ||
      (r >= 0xFB50 && r <= 0xFDFB) ||
      (r >= 0xFE70 && r <= 0xFEFC);
}
