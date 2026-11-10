/// Stage 4: Tier 1 template extractor for known Bahraini senders.
///
/// PRIVACY BY DESIGN. The extractor never outputs: personal names, phone
/// numbers, full IBANs or account numbers (only the last 4 digits), balances,
/// or the raw message text. Templates skip names with a non-capturing group.
library;

import 'detector.dart' show SenderFamily;

enum TxDirection { outgoing, incoming, unknown }

enum TxChannel { card, fawri, account }

/// Fields pulled out of one transaction message. Money is integer fils.
class Tier1Result {
  const Tier1Result({
    required this.templateId,
    required this.amountFils,
    required this.direction,
    required this.channel,
    required this.confidence,
    this.currency = 'BHD',
    this.occurredAt,
    this.merchant,
    this.accountLast4,
    this.counterpartyLast4,
    this.reference,
  });

  final String templateId;
  final int? amountFils;
  final String currency;
  final TxDirection direction;
  final TxChannel channel;

  /// UTC instant (Bahrain time is UTC+3). Null when the date is unknown.
  final DateTime? occurredAt;
  final String? merchant;

  /// Last 4 digits of the user's card or account.
  final String? accountLast4;

  /// Last 4 digits (or fewer) of the other party's IBAN. Never a name.
  final String? counterpartyLast4;

  /// Canonical reference, the same across banks and duplicate notifications.
  final String? reference;

  /// Tier 1 confidence: 0.5*completeness + 0.3*specificity + 0.2*lexicon.
  final double confidence;

  @override
  String toString() =>
      'Tier1Result($templateId, fils: $amountFils, $direction, $channel, '
      'at: $occurredAt, merchant: $merchant, acct: $accountLast4, '
      'cp: $counterpartyLast4, ref: $reference, conf: $confidence)';
}

class _Template {
  _Template(
    this.id,
    this.families,
    this.channel,
    this.direction,
    this.pattern, {
    this.hasMerchant = false,
    this.dateLagsAfterMidnight = false,
  });

  final String id;
  final Set<SenderFamily> families;
  final TxChannel channel;
  final TxDirection direction;
  final RegExp pattern;
  final bool hasMerchant;

  /// The bank prints the previous day's date between 00:00 and 00:59
  /// (seen on NBB: the balances show the order). With a receive time the
  /// date is moved forward one day.
  final bool dateLagsAfterMidnight;

  /// 1.0 for templates verified on real messages. Give unverified templates
  /// a lower value (and a constructor parameter) when they are added.
  final double specificity = 1.0;
}

String? _g(RegExpMatch m, String name) =>
    m.groupNames.contains(name) ? m.namedGroup(name) : null;

class Tier1Extractor {
  const Tier1Extractor();

  static const Duration _bahrain = Duration(hours: 3);

  // Amount: 2.900 | 0.1 | 1,250.500
  static const String _amt = r'(?<amt>\d+(?:,\d{3})*(?:\.\d+)?)';
  static const String _ymd =
      r'(?<y>\d{4})/(?<mo>\d{2})/(?<d>\d{2}) (?<h>\d{2}):(?<mi>\d{2})';
  static const String _dmy4 =
      r'(?<d>\d{2})/(?<mo>\d{2})/(?<y>\d{4}) (?<h>\d{2}):(?<mi>\d{2})';

  static final List<_Template> _templates = [
    // ---- BisB ----
    _Template(
      'bisb.fawri.out',
      {SenderFamily.bisb},
      TxChannel.fawri,
      TxDirection.outgoing,
      RegExp(
        r'Fawri\+ payment BHD\s?' + _amt +
            r',? ref: (?<ref>\w+) was credited to IBAN ending (?<cp>\d{4}) on ' +
            _ymd,
        caseSensitive: false,
      ),
    ),
    _Template(
      'bisb.fawri.in',
      {SenderFamily.bisb},
      TxChannel.fawri,
      TxDirection.incoming,
      RegExp(
        // Two wordings seen: "Fawri+ ... from IBAN 5522 to IBAN 6633" and
        // "Fawri ... from IBAN ending 5522 credited to IBAN ending 6633".
        r'Fawri\+? payment BHD\s?' + _amt +
            r' received from IBAN (?:ending )?(?<cp>\d{4}) (?:credited )?to IBAN (?:ending )?(?<acct>\d{4}) ref\. (?<ref>\w+) on ' +
            _ymd,
        caseSensitive: false,
      ),
    ),
    _Template(
      'bisb.card',
      {SenderFamily.bisb},
      TxChannel.card,
      TxDirection.outgoing,
      RegExp(
        r'thank you for using your (?:debit|credit) card (?<acct>\d{4}) for (?<cur>[A-Z]{3})\s?' +
            _amt +
            r' at (?<m>.+?) on (?<d>\d{2})/(?<mo>\d{2}) @(?<h>\d{2}):(?<mi>\d{2})',
        caseSensitive: false,
      ),
      hasMerchant: true,
    ),
    // No date in the message: the receive time is used and flagged.
    _Template(
      'bisb.account.credit',
      {SenderFamily.bisb},
      TxChannel.account,
      TxDirection.incoming,
      RegExp(
        r'Your account (?<acct>\S+) has been credited with BHD\s?' + _amt,
        caseSensitive: false,
      ),
    ),
    // ---- ila ----
    _Template(
      'ila.card',
      {SenderFamily.ila},
      TxChannel.card,
      TxDirection.outgoing,
      RegExp(
        r'Purchase at (?<m>.+?) using card \*+(?<acct>\d{4}) for BHD\s?' +
            _amt + r' on ' + _dmy4 + r' debited',
        caseSensitive: false,
      ),
      hasMerchant: true,
    ),
    _Template(
      'ila.fawri.in',
      {SenderFamily.ila},
      TxChannel.fawri,
      TxDirection.incoming,
      RegExp(
        r'Fawri\+ transfer of BHD\s?' + _amt +
            r' from IBAN \*+(?<cp>\d{4}) credited to BHD Ac on ' + _dmy4 +
            r' Ref (?<ref>\w+)',
        caseSensitive: false,
      ),
    ),
    _Template(
      'ila.fawri.out',
      {SenderFamily.ila},
      TxChannel.fawri,
      TxDirection.outgoing,
      RegExp(
        r'Fawri\+ transfer of BHD\s?' + _amt +
            r' to IBAN \*+(?<cp>\d{4}) is completed on ' + _dmy4 +
            r' Ref (?<ref>\w+)',
        caseSensitive: false,
      ),
    ),
    // ---- Al Salam ----
    _Template(
      'alsalam.debit',
      {SenderFamily.alSalam},
      TxChannel.account,
      TxDirection.outgoing,
      RegExp(
        r'BHD\s?' + _amt +
            r' has been debited from your account X+(?<acct>\d+)\. .*? on (?<d>\d{2})/(?<mo>\d{2})/(?<y>\d{2}) at (?<h>\d{2}):(?<mi>\d{2})',
        caseSensitive: false,
      ),
    ),
    _Template(
      'alsalam.fawri.in',
      {SenderFamily.alSalam},
      TxChannel.fawri,
      TxDirection.incoming,
      RegExp(
        r'Fawri\+ BHD\s?' + _amt +
            r' ref (?<ref>\w+) from IBAN (?<cp>[A-Z0-9]+) credited to acct X+(?<acct>\d+)\. Bal: BHD [\d,.]+ on (?<d>\d{2})/(?<mo>\d{2})/(?<y>\d{2}) at (?<h>\d{2}):(?<mi>\d{2})',
        caseSensitive: false,
      ),
    ),
    // Fawri credit as Al Salam also prints it: no "+", "Ref." with a dot,
    // the sender's name (skipped, never kept) instead of an IBAN, and "Acc.".
    _Template(
      'alsalam.fawri.in.named',
      {SenderFamily.alSalam},
      TxChannel.fawri,
      TxDirection.incoming,
      RegExp(
        r'Fawri\+? BHD\s?' + _amt +
            r' Ref\.? (?<ref>\w+) from .+? credited to Acc\.? X+(?<acct>\d+)\. Bal: BHD [\d,.]+ on (?<d>\d{2})/(?<mo>\d{2})/(?<y>\d{2}) at (?<h>\d{2}):(?<mi>\d{2})',
        caseSensitive: false,
      ),
    ),
    // Card purchase as Al Salam prints it for its VISA prepaid card: the
    // date has a month name and no year ("29-Apr"), and the text between the
    // date and the time is a stray symbol. The balance (it may be in another
    // currency) is not read.
    _Template(
      'alsalam.card',
      {SenderFamily.alSalam},
      TxChannel.card,
      TxDirection.outgoing,
      RegExp(
        r'thank you for using your (?:[a-z]+ ){0,3}card (?<acct>\S+) for (?<cur>[A-Z]{3})\s?' +
            _amt +
            r' at (?<m>.+?) on (?<d>\d{1,2})-(?<mon>[A-Za-z]{3})\s+\S{0,3}\s*(?<h>\d{1,2}):(?<mi>\d{2})',
        caseSensitive: false,
      ),
      hasMerchant: true,
    ),
    // ---- NBB ----
    // The card's own digits are not printed; "A/C ending" is the user's
    // account. The merchant field is fixed width: name and city run together
    // ("DAY TO DAY DISCOUNT CEMANAMA") and are kept as printed.
    _Template(
      'nbb.card',
      {SenderFamily.nbb},
      TxChannel.card,
      TxDirection.outgoing,
      RegExp(
        r'Thank you for using NBB (?:Debit|Credit|Prepaid) Card at (?<m>.+?) for (?<cur>[A-Z]{3})\s?' +
            _amt + r' on ' + _dmy4 + r', A/C ending (?<acct>\d{4})',
        caseSensitive: false,
      ),
      hasMerchant: true,
      dateLagsAfterMidnight: true,
    ),
    _Template(
      'nbb.fawri.out',
      {SenderFamily.nbb},
      TxChannel.fawri,
      TxDirection.outgoing,
      RegExp(
        r'Successful Fawri\+ transfer of BHD\s?' + _amt +
            r' credited to (?<cp>\S+) on ' + _dmy4 +
            r', Ref\.?\s?(?<ref>\w+), A/C ending (?<acct>\d{4})',
        caseSensitive: false,
      ),
      dateLagsAfterMidnight: true,
    ),
    _Template(
      'nbb.fawri.in',
      {SenderFamily.nbb},
      TxChannel.fawri,
      TxDirection.incoming,
      RegExp(
        r'Fawri\+ transfer of BHD\s?' + _amt +
            r' from (?<cp>\S+) credited to your account on ' + _dmy4 +
            r', Ref\.?\s?(?<ref>\w+), A/C ending (?<acct>\d{4})',
        caseSensitive: false,
      ),
      dateLagsAfterMidnight: true,
    ),
    // ---- KFH ----
    // Only the recipient's IBAN is printed (full, so only its last 4 digits
    // are kept); the sender's account is not named. "credited to IBAN" is
    // read as money leaving, like the other banks' outgoing Fawri+ messages.
    _Template(
      'kfh.fawri.out',
      {SenderFamily.kfh},
      TxChannel.fawri,
      TxDirection.outgoing,
      RegExp(
        r'Fawri\+? payment BHD\s?' + _amt +
            r',? Ref\.?\s?(?<ref>\w+) credited to IBAN (?<cp>\S+) on (?<d>\d{2})/(?<mo>\d{2})/(?<y>\d{4}) at (?<h>\d{2}):(?<mi>\d{2})',
        caseSensitive: false,
      ),
    ),
    // ---- BenefitPay notifications ----
    _Template(
      'benefitpay.fawri.received',
      {SenderFamily.benefitPay},
      TxChannel.fawri,
      TxDirection.incoming,
      RegExp(
        r'FAWRI\+ Payment - BHD\s?' + _amt +
            r' received from:(?: .*?)? From IBAN: \S*?(?<cp>\d{4}) To IBAN: \S*?(?<acct>\d{4}) Reference no: (?<ref>\S+) Credited on: ' +
            _dmy4,
        caseSensitive: false,
      ),
    ),
    // "was credited to" does not say which side the user is on, so the
    // direction stays unknown (confidence drops, the app asks the user).
    _Template(
      'benefitpay.fawri.credited',
      {SenderFamily.benefitPay},
      TxChannel.fawri,
      TxDirection.unknown,
      RegExp(
        r'FAWRI\+ Payment - BHD\s?' + _amt +
            r' was credited to:\.? From IBAN: \S*?(?<cp>\d{4}) To IBAN: \S*?(?<acct>\d{4}) (?:Tel: \S+ )?Reference no: (?<ref>\S+) Credited on: ' +
            _dmy4,
        caseSensitive: false,
      ),
    ),
  ];

  /// Extracts fields from normalized text of a message already classified as
  /// a transaction. Returns null when no template matches (Tier 2 or review).
  ///
  /// [receivedAt] (UTC) is only needed for templates that print no year.
  Tier1Result? extract(
    String normalizedText, {
    SenderFamily family = SenderFamily.unknown,
    DateTime? receivedAt,
  }) {
    for (final t in _templates.where((t) => t.families.contains(family))) {
      final m = t.pattern.firstMatch(normalizedText);
      if (m != null) return _build(t, m, 1.0, receivedAt);
    }
    // Unknown or wrong sender: try the other templates, lower lexicon score.
    for (final t in _templates.where((t) => !t.families.contains(family))) {
      final m = t.pattern.firstMatch(normalizedText);
      if (m != null) return _build(t, m, 0.5, receivedAt);
    }
    return null;
  }

  Tier1Result _build(
    _Template t,
    RegExpMatch m,
    double lexicon,
    DateTime? receivedAt,
  ) {
    final amount = _toFils(_g(m, 'amt'));
    final date = _parseDate(m, receivedAt,
        lagsAfterMidnight: t.dateLagsAfterMidnight);
    final merchant = t.hasMerchant ? _cleanMerchant(_g(m, 'm')) : null;

    var needed = 3;
    var found = 0;
    if (amount != null) found++;
    if (t.direction != TxDirection.unknown) found++;
    if (date != null) found++;
    if (t.hasMerchant) {
      needed++;
      if (merchant != null) found++;
    }
    final completeness = found / needed;
    final confidence =
        0.5 * completeness + 0.3 * t.specificity + 0.2 * lexicon;

    return Tier1Result(
      templateId: t.id,
      amountFils: amount,
      direction: t.direction,
      channel: t.channel,
      confidence: confidence,
      occurredAt: date,
      merchant: merchant,
      accountLast4: _last4(_g(m, 'acct')),
      counterpartyLast4: _last4(_g(m, 'cp')),
      reference: canonicalRef(_g(m, 'ref')),
      currency: (_g(m, 'cur') ?? 'BHD').toUpperCase(),
    );
  }

  /// "6200000001-BP1000000001TEST-R" and "6200000002-BP1000000001TEST" both
  /// become "BP1000000001TEST"; bank references are returned unchanged.
  static String? canonicalRef(String? ref) {
    if (ref == null || ref.isEmpty) return null;
    final m = RegExp(r'^\d+-(.+?)(?:-R)?$').firstMatch(ref);
    return m == null ? ref : m.group(1);
  }

  /// "2.900" -> 2900, "0.1" -> 100, "1,250.500" -> 1250500. BHD has at most
  /// 3 decimals, so anything longer is rejected (null).
  static int? _toFils(String? s) {
    if (s == null) return null;
    final parts = s.replaceAll(',', '').split('.');
    final whole = int.tryParse(parts[0]);
    if (whole == null) return null;
    final frac = parts.length > 1 ? parts[1] : '';
    if (frac.length > 3) return null;
    final fils = int.tryParse(frac.padRight(3, '0'));
    return fils == null ? null : whole * 1000 + fils;
  }

  static String? _last4(String? s) {
    if (s == null) return null;
    return RegExp(r'(\d{1,4})$').firstMatch(s)?.group(1);
  }

  static String? _cleanMerchant(String? s) {
    if (s == null) return null;
    final c = s.replaceAll('&amp;', '&').replaceAll(RegExp(r'\s+'), ' ').trim();
    return c.isEmpty ? null : c;
  }

  static const List<String> _months = [
    'jan', 'feb', 'mar', 'apr', 'may', 'jun',
    'jul', 'aug', 'sep', 'oct', 'nov', 'dec',
  ];

  /// "Apr" -> 4, null for anything that is not an English month.
  static int? _monthNumber(String? name) {
    if (name == null) return null;
    final i = _months.indexOf(name.toLowerCase());
    return i < 0 ? null : i + 1;
  }

  static DateTime? _parseDate(
    RegExpMatch m,
    DateTime? receivedAt, {
    bool lagsAfterMidnight = false,
  }) {
    final d = int.tryParse(_g(m, 'd') ?? '');
    final mo = int.tryParse(_g(m, 'mo') ?? '') ?? _monthNumber(_g(m, 'mon'));
    final h = int.tryParse(_g(m, 'h') ?? '');
    final mi = int.tryParse(_g(m, 'mi') ?? '');
    if (d == null || mo == null || h == null || mi == null) return null;
    if (mo < 1 || mo > 12 || d < 1 || d > 31 || h > 23 || mi > 59) return null;

    var year = 0;
    final yRaw = _g(m, 'y');
    if (yRaw != null) {
      final v = int.parse(yRaw);
      year = yRaw.length == 2 ? 2000 + v : v;
    } else {
      // No year printed: take it from the receive time (Bahrain wall clock),
      // and step back a year if the date would land in the future.
      if (receivedAt == null) return null;
      final refLocal = receivedAt.toUtc().add(_bahrain);
      year = refLocal.year;
      final cand = DateTime.utc(year, mo, d, h, mi);
      if (cand.isAfter(refLocal.add(const Duration(days: 1)))) year -= 1;
    }
    final local = DateTime.utc(year, mo, d, h, mi);
    if (local.month != mo || local.day != d) return null; // e.g. 31 Feb
    var utc = local.subtract(_bahrain);
    if (lagsAfterMidnight && h == 0 && receivedAt != null) {
      // Received about a day after the printed time: the date lagged.
      final gap = receivedAt.toUtc().difference(utc);
      if (gap > const Duration(hours: 12) && gap < const Duration(hours: 36)) {
        utc = utc.add(const Duration(days: 1));
      }
    }
    return utc;
  }
}
