/// Merchant names and categories (SRS FR-3.9).
///
/// Bank messages print the shop as a fixed-width field with the city glued
/// on ("REDTAG                MANAMA", "GOLDEN COLLECTION PERFMANAMA"), store
/// numbers and legal suffixes. This turns that into a short display name and
/// puts it in one of nine categories, using an alias dictionary first and
/// keywords second. Nothing is learned and nothing leaves the phone.
library;

/// The categories (at most ten, FR-3.9).
const List<String> kCategories = [
  'food',
  'groceries',
  'shopping',
  'transport',
  'bills',
  'health',
  'entertainment',
  'education',
  'other',
];

class MerchantInfo {
  const MerchantInfo({required this.name, this.category, this.source = 'none'});

  /// Display name.
  final String name;

  /// One of [kCategories], or null when nothing matched.
  final String? category;

  /// 'alias', 'keyword' or 'none'.
  final String source;
}

class _Alias {
  _Alias(String pattern, this.name, this.category)
      : regex = RegExp(pattern, caseSensitive: false, unicode: true);

  final RegExp regex;
  final String name;
  final String category;
}

class MerchantNormalizer {
  const MerchantNormalizer();

  // Cities and areas that banks append to the merchant name. Long ones are
  // also removed when glued to the last word (PERFMANAMA).
  static const List<String> _cities = [
    'MANAMA', 'MALKIYA', 'MUHARRAQ', 'RIFFA', 'JUFFAIR', 'ADLIYA', 'SANABIS',
    'GUDAIBIYA', 'ISA TOWN', 'HAMAD TOWN', 'SITRA', 'SAAR', 'BUDAIYA', 'SEEF',
    'HIDD', 'JASRA', 'ZALLAQ', 'AALI', 'TUBLI', 'BAHRAIN', 'BH',
  ];

  static final RegExp _storeCode = RegExp(
    r'\s+(?:[A-Z]{1,2}\s+)?#\S+|\s+[A-Z]{2}-\d{3,}\b|\s+#?\d{4,}\b',
  );
  static final RegExp _legal = RegExp(
    r'\s+(?:W\.?\s?L\.?\s?L\.?|L\.?L\.?C\.?|B\.?S\.?C\.?|S\.?P\.?C\.?|CO\.?(?:\s+W)?|COMPANY|EST\.?)$',
    caseSensitive: false,
  );

  static final List<_Alias> _aliases = [
    // Food
    _Alias(r'\btalabat\b|طلبات', 'Talabat', 'food'),
    _Alias(r'\bjahez\b', 'Jahez', 'food'),
    _Alias(r'\bcareem\s*food\b', 'Careem Food', 'food'),
    _Alias(r'\bcosta\b|كوستا', 'Costa Coffee', 'food'),
    _Alias(r'\bstarbucks\b|ستاربكس', 'Starbucks', 'food'),
    _Alias(r'\btim\s*hortons?\b', 'Tim Hortons', 'food'),
    _Alias(r'\bdunkin\b', "Dunkin'", 'food'),
    _Alias(r'\bkfc\b', 'KFC', 'food'),
    _Alias(r"\bmcdonald'?s?\b|\bmc\s?donalds?\b", "McDonald's", 'food'),
    _Alias(r'\bburger\s*king\b', 'Burger King', 'food'),
    _Alias(r'\bhardee', "Hardee's", 'food'),
    _Alias(r'\bpizza\s*hut\b', 'Pizza Hut', 'food'),
    _Alias(r"\bdomino'?s?\b", "Domino's", 'food'),
    _Alias(r'\bsubway\b', 'Subway', 'food'),
    _Alias(r'\bshawarma\b|شاورما', 'Shawarma', 'food'),
    // Groceries
    _Alias(r'\bday\s*to\s*day\b', 'Day To Day', 'groceries'),
    _Alias(r'\blulu\b', 'Lulu', 'groceries'),
    _Alias(r'\bnesto\b', 'Nesto', 'groceries'),
    _Alias(r'\bcarrefour\b|كارفور', 'Carrefour', 'groceries'),
    _Alias(r'\bal\s*jazira\b|\baljazira\b', 'Al Jazira', 'groceries'),
    _Alias(r'\bmegamart\b|\bmega\s*mart\b', 'Megamart', 'groceries'),
    _Alias(r'\bsaveco\b', 'Saveco', 'groceries'),
    // Shopping
    _Alias(r'\bred\s*tag\b|\bredtag\b', 'Redtag', 'shopping'),
    _Alias(r'\bamazon\b', 'Amazon', 'shopping'),
    _Alias(r'\bnoon\b', 'Noon', 'shopping'),
    _Alias(r'\bshein\b', 'Shein', 'shopping'),
    _Alias(r'\bikea\b', 'IKEA', 'shopping'),
    _Alias(r'\bh\s?&\s?m\b', 'H&M', 'shopping'),
    _Alias(r'\bzara\b', 'Zara', 'shopping'),
    _Alias(r'\bsharaf\s*dg\b', 'Sharaf DG', 'shopping'),
    _Alias(r'\bjarir\b', 'Jarir', 'shopping'),
    // Transport
    _Alias(r'\buber\b', 'Uber', 'transport'),
    _Alias(r'\bcareem\b', 'Careem', 'transport'),
    _Alias(r'\bbapco\b', 'BAPCO', 'transport'),
    _Alias(r'\bnational\s*oil\b', 'National Oil', 'transport'),
    // Bills
    _Alias(r'\bbatelco\b|بتلكو', 'Batelco', 'bills'),
    _Alias(r'\bzain\b', 'Zain', 'bills'),
    _Alias(r'\bstc\b', 'stc', 'bills'),
    _Alias(r'\bewa\b|هيئة\s+الكهرباء', 'EWA', 'bills'),
    // Entertainment and subscriptions
    _Alias(r'\bnetflix\b', 'Netflix', 'entertainment'),
    _Alias(r'\bspotify\b', 'Spotify', 'entertainment'),
    _Alias(r'\bapple\.?com\b|\bitunes\b|\bapple\s*(?:services|music|tv)\b', 'Apple', 'entertainment'),
    _Alias(r'\bgoogle\s*\*?\s*(?:play|youtube)|\bgoogle\b', 'Google', 'entertainment'),
    _Alias(r'\bplaystation\b|\bsteam\b', 'Games', 'entertainment'),
    _Alias(r'\bvox\b|\bcinema\b|\bcineco\b', 'Cinema', 'entertainment'),
  ];

  static final List<(RegExp, String)> _keywords = [
    (
      RegExp(
          r'\b(?:rest(?:aurant)?|cafe|caf[eé]|coffee|roast(?:ery)?|bakery|bakeries|kitchen|grill|pizza|burger|shawarma|juice|sweets?|bistro|diner|tea|food|catering|cake|patisserie)\b|مطعم|مقهى|كافيه|مخبز|حلويات',
          caseSensitive: false,
          unicode: true),
      'food'
    ),
    (
      RegExp(
          r'\b(?:fuel|petrol|petro|gas\s?station|taxi|parking|car\s?wash|garage|auto|motors?|airways?|airlines?|metro|bus)\b|وقود|بنزين|تاكسي',
          caseSensitive: false,
          unicode: true),
      'transport'
    ),
    (
      RegExp(
          r'\b(?:cold\s?store|supermarket|super\s?market|hypermarket|grocer(?:y|ies)|mini\s?mart|mart|market|vegetables?|fruits?|butchery|fish)\b|بقالة|سوبرماركت|هايبر',
          caseSensitive: false,
          unicode: true),
      'groceries'
    ),
    (
      RegExp(
          r'\b(?:pharmacy|pharma|clinic|hospital|medical|dental|health|optic(?:al|s)?|lab(?:oratory)?)\b|صيدلية|عيادة|مستشفى',
          caseSensitive: false,
          unicode: true),
      'health'
    ),
    (
      RegExp(
          r'\b(?:school|university|college|academy|institute|books?|library|stationery|training)\b|مدرسة|جامعة|مكتبة',
          caseSensitive: false,
          unicode: true),
      'education'
    ),
    (
      RegExp(
          r'\b(?:cinema|games?|gaming|park|resort|spa|salon|gym|fitness|club|bowling|arcade)\b',
          caseSensitive: false),
      'entertainment'
    ),
    (
      RegExp(
          r'\b(?:perf(?:umes?)?|gold|jewel(?:ler|lery|s)?|fashion|mall|store|stores|shop|boutique|collection|trading|electronics|textiles?|garments?|gifts?|toys?|furniture|optics)\b|عطور|مجوهرات|ذهب',
          caseSensitive: false,
          unicode: true),
      'shopping'
    ),
  ];

  /// Cleans [raw]. Returns null for a missing or empty name.
  MerchantInfo? normalize(String? raw) {
    if (raw == null) return null;
    var s = raw.replaceAll('&amp;', '&').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (s.isEmpty) return null;

    // Alias first, on the text as printed: "COSTA COFFEE SEEF MALL" is Costa.
    for (final a in _aliases) {
      if (a.regex.hasMatch(s)) {
        return MerchantInfo(name: a.name, category: a.category, source: 'alias');
      }
    }

    s = s.replaceAll(_storeCode, '');
    s = _stripCity(s);
    // A fixed-width field can cut the next word down to one letter
    // ("ABUTAKI OFFERS COMPANY Y" + "MANAMA" on BBK): drop it.
    s = s.replaceFirst(RegExp(r'\s+[A-Za-z]$'), '');
    s = s.replaceFirst(_legal, '').trim();
    s = s.replaceAll(RegExp(r'^[\s*#-]+|[\s*#-]+$'), '');
    if (s.isEmpty) return null;

    for (final (re, category) in _keywords) {
      if (re.hasMatch(s)) {
        return MerchantInfo(
            name: _titleCase(s), category: category, source: 'keyword');
      }
    }
    return MerchantInfo(name: _titleCase(s));
  }

  static String _stripCity(String s) {
    final upper = s.toUpperCase();
    for (final city in _cities) {
      if (!upper.endsWith(city)) continue;
      final head = s.substring(0, s.length - city.length);
      if (head.isEmpty) continue;
      final spaced = head.endsWith(' ');
      // Glued to the last word only for long city names, so a name that
      // simply ends in "...SAAR" or "...BH" is left alone.
      if (!spaced && city.length < 6) continue;
      final cleaned = head.trimRight();
      if (cleaned.length >= 3) return cleaned;
    }
    return s;
  }

  static String _titleCase(String s) {
    return s.split(' ').map((w) {
      if (w.isEmpty) return w;
      // Keep tokens with digits or symbols as printed (e.g. "7-ELEVEN").
      if (RegExp(r'[\d&*#@]').hasMatch(w)) return w;
      final lower = w.toLowerCase();
      return lower[0].toUpperCase() + lower.substring(1);
    }).join(' ');
  }
}
