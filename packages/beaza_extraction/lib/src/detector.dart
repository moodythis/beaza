/// Language and sender-family detection (SRS FR-3.2).
///
/// Expects text that already went through the Normalizer.
library;

enum MessageLanguage { arabic, english, mixed, unknown }

enum SenderFamily {
  benefitPay,
  nbb,
  bbk,
  bisb,
  ila,
  aub,
  alSalam,
  kfh,
  unknown,
}

class LanguageDetector {
  const LanguageDetector({
    this.arabicThreshold = 0.8,
    this.englishThreshold = 0.2,
    this.minMixedLetters = 0,
  });

  final double arabicThreshold;
  final double englishThreshold;
  /// Optional strict rule: at least this many Arabic AND Latin letters means
  /// mixed, whatever the ratio. 0 (default) turns it off, because most Arabic
  /// bank messages carry a Latin merchant name and would all become mixed.
  final int minMixedLetters;

  static final RegExp _currencyToken =
      RegExp(r'(?<![A-Za-z])BHD(?![A-Za-z])');

  LanguageDetectionResult detectDetailed(String text) {
    var arabicCount = 0;
    var latinCount = 0;

    // استبعاد BHD لعدم التأثير على دقة نصوص الرسائل العربية القصيرة
    for (final r in text.replaceAll(_currencyToken, ' ').runes) {
      if (_isArabicLetter(r)) {
        arabicCount++;
      } else if (_isLatinLetter(r)) {
        latinCount++;
      }
    }

    final total = arabicCount + latinCount;
    if (total == 0) {
      return const LanguageDetectionResult(
        language: MessageLanguage.unknown,
        arabicRatio: 0.0,
        englishRatio: 0.0,
      );
    }

    final arRatio = arabicCount / total;
    final enRatio = latinCount / total;

    MessageLanguage lang;
    if (minMixedLetters > 0 &&
        arabicCount >= minMixedLetters &&
        latinCount >= minMixedLetters) {
      lang = MessageLanguage.mixed;
    } else if (arRatio >= arabicThreshold) {
      lang = MessageLanguage.arabic;
    } else if (arRatio <= englishThreshold) {
      lang = MessageLanguage.english;
    } else {
      lang = MessageLanguage.mixed;
    }

    return LanguageDetectionResult(
      language: lang,
      arabicRatio: arRatio,
      englishRatio: enRatio,
    );
  }

  MessageLanguage detect(String text) => detectDetailed(text).language;

  static bool _isArabicLetter(int r) {
    return (r >= 0x0621 && r <= 0x064A) ||
        (r >= 0x066E && r <= 0x06D3) ||
        (r >= 0x06FA && r <= 0x06FF) ||
        (r >= 0xFB50 && r <= 0xFDFF) ||
        (r >= 0xFE70 && r <= 0xFEFF);
  }

  static bool _isLatinLetter(int r) {
    return (r >= 0x41 && r <= 0x5A) || (r >= 0x61 && r <= 0x7A);
  }
}

class LanguageDetectionResult {
  final MessageLanguage language;
  final double arabicRatio;
  final double englishRatio;

  const LanguageDetectionResult({
    required this.language,
    required this.arabicRatio,
    required this.englishRatio,
  });
}

class SenderFamilyDetector {
  SenderFamilyDetector({Map<SenderFamily, List<String>>? aliases})
      : _aliases = aliases ?? defaultAliases,
        _lookup = _buildLookup(aliases ?? defaultAliases);

  final Map<SenderFamily, List<String>> _aliases;
  final Map<String, SenderFamily> _lookup;

  // القائمة الكاملة والشاملة للبنوك والمحافظ البحرينية بالعربي والإنجليزي
  static const Map<SenderFamily, List<String>> defaultAliases = {
    SenderFamily.benefitPay: [
      'BenefitPay',
      'Benefit',
      'BenefitPay App',
      'بنفت',
      'بنفت بي',
    ],
    SenderFamily.nbb: [
      'NBB',
      'National Bank of Bahrain',
      'بنك البحرين الوطني',
    ],
    SenderFamily.bbk: [
      'BBK',
      'Bank of Bahrain and Kuwait',
      'بنك البحرين والكويت',
    ],
    SenderFamily.bisb: [
      'BisB',
      'BisB Bank',
      'Bahrain Islamic Bank',
      'بنك البحرين الاسلامي',
      'بنك البحرين الإسلامي',
    ],
    SenderFamily.ila: [
      'ila',
      'ila Bank',
      'بنك إلى',
      'بنك الى',
    ],
    SenderFamily.aub: [
      'AUB',
      'Ahli United Bank',
      'البنك الاهلي المتحد',
      'البنك الأهلي المتحد',
    ],
    SenderFamily.alSalam: [
      'AlSalam',
      'Al Salam',
      'Al Salam Bank',
      'Al-Salam Bank',
      'بنك السلام',
    ],
    SenderFamily.kfh: [
      'KFH',
      'KFH Bahrain',
      'بيت التمويل الكويتي',
    ],
  };

  late final List<MapEntry<String, SenderFamily>> _phrases = _buildPhrases();

  List<MapEntry<String, SenderFamily>> _buildPhrases() {
    final list = <MapEntry<String, SenderFamily>>[];
    _aliases.forEach((family, names) {
      for (final name in names) {
        final w = _words(name);
        if (w.trim().isNotEmpty) list.add(MapEntry(w, family));
      }
    });
    list.sort((a, b) => b.key.length.compareTo(a.key.length));
    return list;
  }

  static String _words(String id) {
    final w = id
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A]+'), ' ')
        .trim();
    return ' $w ';
  }

  static Map<String, SenderFamily> _buildLookup(
    Map<SenderFamily, List<String>> aliases,
  ) {
    final lookup = <String, SenderFamily>{};
    aliases.forEach((family, names) {
      for (final name in names) {
        final key = _key(name);
        if (key.isNotEmpty) {
          lookup[key] = family;
        }
      }
    });
    return lookup;
  }

  static String _key(String id) {
    return id.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\u0621-\u064A]'), '');
  }

  SenderFamily detect(String senderId) {
    final exact = _lookup[_key(senderId)];
    if (exact != null) return exact;
    final words = _words(senderId);
    for (final e in _phrases) {
      if (words.contains(e.key)) return e.value;
    }
    return SenderFamily.unknown;
  }
}

class Detection {
  const Detection(this.language, this.senderFamily, {this.details});

  final MessageLanguage language;
  final SenderFamily senderFamily;
  final LanguageDetectionResult? details;
}

class Detector {
  Detector({LanguageDetector? language, SenderFamilyDetector? senders})
      : _language = language ?? const LanguageDetector(),
        _senders = senders ?? SenderFamilyDetector();

  final LanguageDetector _language;
  final SenderFamilyDetector _senders;

  Detection detect(String normalizedText, String senderId) {
    final langDetails = _language.detectDetailed(normalizedText);
    return Detection(
      langDetails.language,
      _senders.detect(senderId),
      details: langDetails,
    );
  }
}
