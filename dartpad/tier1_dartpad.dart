// Stage 4 (Tier 1 template extractor) as a single file for dartpad.dev.
// Paste everything into DartPad and press Run.
//
// PRIVACY BY DESIGN. The extractor never outputs: personal names, phone
// numbers, full IBANs or account numbers (only the last 4 digits), balances,
// or the raw message text. Templates skip names with a non-capturing group.

// ---- SenderFamily (copied from detector.dart) ----
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
// ---- end ----

enum TxDirection { outgoing, incoming, unknown }

enum TxChannel { card, fawri, account }

/// Fields pulled out of one transaction message. Money is integer fils.
class ExtractionResult {
  const ExtractionResult({
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
      'ExtractionResult($templateId, fils: $amountFils, $direction, $channel, '
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
    this.specificity = 1.0,
  });

  final String id;
  final Set<SenderFamily> families;
  final TxChannel channel;
  final TxDirection direction;
  final RegExp pattern;
  final bool hasMerchant;

  /// 1.0 for templates verified on real messages, lower for guesses.
  final double specificity;
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
        r'Fawri\+ payment BHD\s?' + _amt +
            r' received from IBAN (?<cp>\d{4}) to IBAN (?<acct>\d{4}) ref\. (?<ref>\w+) on ' +
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
        r'thank you for using your (?:debit|credit) card (?<acct>\d{4}) for BHD\s?' +
            _amt +
            r' at (?<m>.+?) on (?<d>\d{2})/(?<mo>\d{2}) @(?<h>\d{2}):(?<mi>\d{2})',
        caseSensitive: false,
      ),
      hasMerchant: true,
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
  ExtractionResult? extract(
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

  ExtractionResult _build(
    _Template t,
    RegExpMatch m,
    double lexicon,
    DateTime? receivedAt,
  ) {
    final amount = _toFils(_g(m, 'amt'));
    final date = _parseDate(m, receivedAt);
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

    return ExtractionResult(
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

  static DateTime? _parseDate(RegExpMatch m, DateTime? receivedAt) {
    final d = int.tryParse(_g(m, 'd') ?? '');
    final mo = int.tryParse(_g(m, 'mo') ?? '');
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
    return local.subtract(_bahrain);
  }
}

int passed = 0;
int failed = 0;

void check(String name, Object? actual, Object? expected) {
  if (actual == expected) {
    passed++;
    print('PASS  $name');
  } else {
    failed++;
    print('FAIL  $name\n  expected: $expected\n  actual:   $actual');
  }
}

void main() {
  const ex = Tier1Extractor();

  String sum(ExtractionResult? r) => r == null
      ? 'null'
      : '${r.amountFils}|${r.direction.name}|${r.channel.name}|'
          '${r.accountLast4}|${r.counterpartyLast4}|${r.reference}|'
          '${r.merchant}|${r.occurredAt?.toIso8601String()}';

  int conf(ExtractionResult? r) => (r!.confidence * 1000).round();

  // Messages below follow real Bahraini formats. Names, balances and numbers
  // are invented. Text is already normalized (BD -> BHD).
  const bisbOut = 'Fawri+ payment BHD2.900, ref: BIB103KAA000AAAA was credited to IBAN ending 4411 on 2026/10/30 00:59. Balance BHD9.999. Tel: 17515151';
  const bisbIn = 'Fawri+ payment BHD8.800 received from IBAN 5522 to IBAN 6633 ref. BIB103KAB000BBBB on 2026/10/25 06:15. Balance BHD9.999. Tel 17515151';
  const bisbCard = 'Dear CLIENT, thank you for using your Debit card 7744 for BHD 0.300 at SAMPLE BAKERY - MAL BAH BH-000001 on 15/10 @16:31. Avail Bal BHD 9.999. Tel 17515151';
  const ilaCard = 'Success! Purchase at SAMPLE TRADING CO W using card ****8855 for BHD 1.500 on 29/10/2026 15:42 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456';
  const ilaIn = 'Success! Fawri+ transfer of BHD 50.000 from IBAN ****0777 credited to BHD Ac on 02/11/2026 12:11 Ref ALS103KAC000CCCC Balance BHD 9.999 Enquiry 17123456';
  const bpReceived = 'FAWRI+ Payment - BHD 0.1 received from: Test Person From IBAN: BH40ALSA**********0777 To IBAN: BH35BIBB**********6633 Reference no: 6200000001-BP1000000001TEST-R Credited on: 02/11/2026 21:02';
  const bpCredited = 'FAWRI+ Payment - BHD 0.1 was credited to:. From IBAN: BH40ALSA**********0777 To IBAN: BH35BIBB**********6633 Tel: +00000000 Reference no: 6200000002-BP1000000001TEST Credited on: 02/11/2026 21:02';

  // One check per template: amount|direction|channel|account|counterparty|ref|merchant|time(UTC)
  check('BisB Fawri+ out', sum(ex.extract(bisbOut, family: SenderFamily.bisb)),
      '2900|outgoing|fawri|null|4411|BIB103KAA000AAAA|null|2026-10-29T21:59:00.000Z');
  check('BisB Fawri+ in', sum(ex.extract(bisbIn, family: SenderFamily.bisb)),
      '8800|incoming|fawri|6633|5522|BIB103KAB000BBBB|null|2026-10-25T03:15:00.000Z');
  check('BisB card purchase',
      sum(ex.extract(bisbCard, family: SenderFamily.bisb, receivedAt: DateTime.utc(2026, 10, 15, 13, 40))),
      '300|outgoing|card|7744|null|null|SAMPLE BAKERY - MAL BAH BH-000001|2026-10-15T13:31:00.000Z');
  check('ila card purchase', sum(ex.extract(ilaCard, family: SenderFamily.ila)),
      '1500|outgoing|card|8855|null|null|SAMPLE TRADING CO W|2026-10-29T12:42:00.000Z');
  check('ila merchant with &amp;',
      sum(ex.extract('Success! Purchase at INFO &amp; SAMPLE AUTHOR using card ****8855 for BHD 5.000 on 14/10/2026 17:16 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456', family: SenderFamily.ila)),
      '5000|outgoing|card|8855|null|null|INFO & SAMPLE AUTHOR|2026-10-14T14:16:00.000Z');
  check('ila Fawri+ in', sum(ex.extract(ilaIn, family: SenderFamily.ila)),
      '50000|incoming|fawri|null|0777|ALS103KAC000CCCC|null|2026-11-02T09:11:00.000Z');
  check('ila Fawri+ out',
      sum(ex.extract('Success! Fawri+ transfer of BHD 49.000 to IBAN ****9966 is completed on 01/11/2026 20:45 Ref ABCO260000000001 Balance BHD 9.999 Enquiry 17123456', family: SenderFamily.ila)),
      '49000|outgoing|fawri|null|9966|ABCO260000000001|null|2026-11-01T17:45:00.000Z');
  check('Al Salam debit',
      sum(ex.extract('Dear Client, BHD 0.400 has been debited from your account XXXX10100777. Your balance is BHD 9.999 on 30/10/26 at 01:27. Thank you, Al Salam Bank.', family: SenderFamily.alSalam)),
      '400|outgoing|account|0777|null|null|null|2026-10-29T22:27:00.000Z');
  check('Al Salam Fawri+ in',
      sum(ex.extract('Fawri+ BHD 6.000 ref BIB103KAD000DDDD from IBAN BH35BIBBXXXXXXXXXXXX27 credited to acct XXX10100777. Bal: BHD 9.999 on 26/10/26 at 15:39. Tel 17005500', family: SenderFamily.alSalam)),
      '6000|incoming|fawri|0777|27|BIB103KAD000DDDD|null|2026-10-26T12:39:00.000Z');
  check('BenefitPay received', sum(ex.extract(bpReceived, family: SenderFamily.benefitPay)),
      '100|incoming|fawri|6633|0777|BP1000000001TEST|null|2026-11-02T18:02:00.000Z');
  check('BenefitPay credited (direction unknown)', sum(ex.extract(bpCredited, family: SenderFamily.benefitPay)),
      '100|unknown|fawri|6633|0777|BP1000000001TEST|null|2026-11-02T18:02:00.000Z');
  check('BenefitPay received without a name',
      ex.extract('FAWRI+ Payment - BHD 0.1 received from: From IBAN: BH40ALSA**********0777 To IBAN: BH35BIBB**********6633 Reference no: 6200000001-BP1000000001TEST-R Credited on: 02/11/2026 21:02', family: SenderFamily.benefitPay)?.amountFils,
      100);

  // Dedupe key
  check('Both BenefitPay notifications share one reference',
      ex.extract(bpReceived, family: SenderFamily.benefitPay)!.reference ==
          ex.extract(bpCredited, family: SenderFamily.benefitPay)!.reference,
      true);
  check('canonicalRef keeps bank references', Tier1Extractor.canonicalRef('BIB103KAE000EEEE'), 'BIB103KAE000EEEE');
  check('canonicalRef null', Tier1Extractor.canonicalRef(null), null);

  // Year handling for templates without a year
  check('No year and no receive time gives no date',
      ex.extract(bisbCard, family: SenderFamily.bisb)?.occurredAt, null);
  check('Year rolls back across New Year',
      ex.extract(bisbCard.replaceAll('15/10 @16:31', '31/12 @23:50'), family: SenderFamily.bisb, receivedAt: DateTime.utc(2026, 12, 31, 22, 0))?.occurredAt?.toIso8601String(),
      '2026-12-31T20:50:00.000Z');

  // Amounts
  check('Thousands separator', ex.extract(ilaIn.replaceAll('BHD 50.000', 'BHD 1,250.500'), family: SenderFamily.ila)?.amountFils, 1250500);
  check('Four decimals rejected', ex.extract(ilaIn.replaceAll('BHD 50.000', 'BHD 1.2345'), family: SenderFamily.ila)?.amountFils, null);

  // Confidence = 0.5*completeness + 0.3*specificity + 0.2*lexicon
  check('Full match, right sender', conf(ex.extract(bisbOut, family: SenderFamily.bisb)), 1000);
  check('Full match, wrong sender', conf(ex.extract(bisbOut, family: SenderFamily.alSalam)), 900);
  check('Full match, unknown sender', conf(ex.extract(bisbOut)), 900);
  check('Missing date lowers confidence', conf(ex.extract(bisbCard, family: SenderFamily.bisb)), 875);
  check('Unknown direction lowers confidence', conf(ex.extract(bpCredited, family: SenderFamily.benefitPay)), 833);

  // Not matched
  check('Greeting has no template', ex.extract('Hello from your bank') == null, true);
  check('ATM withdrawal has no template yet', ex.extract('ATM withdrawal of BHD 20.000 from card 7744 on 01/11/2026 10:00', family: SenderFamily.bisb) == null, true);

  // Privacy: nothing personal in the result
  final text = ex.extract(bpReceived, family: SenderFamily.benefitPay).toString();
  check('Result has no personal name', text.contains('Test Person'), false);
  check('Result has no full IBAN', text.contains('BH40') || text.contains('BH35'), false);

  print('\n$passed passed, $failed failed');
}
