// Stage 5 (Validator and public ExtractionResult) as a single file for
// dartpad.dev. Paste everything into DartPad and press Run.
//
// The first two blocks are copies of earlier stages so this file runs alone.

// ---- copied from classifier.dart ----
enum MessageKind {
  transaction,
  declined,
  otp,
  securityNotice,
  promotion,
  statement,
  balanceInquiry,
  unknown,
}

/// Result of the classifier.
///
/// [confidence] is a rule-based heuristic in 0..1, not a calibrated
/// probability. It is meant for routing (low values go to review) and will be
/// calibrated on the labelled Bahraini sample. 0.0 means no rule matched.
class ClassificationResult {
  const ClassificationResult({
    required this.kind,
    required this.confidence,
    required this.rule,
  });

  final MessageKind kind;
  final double confidence;

  /// Name of the rule that decided, useful for error analysis.
  final String rule;

  bool get isTransaction => kind == MessageKind.transaction;
}
// ---- end ----

// ---- copied from tier1.dart (class renamed Tier1Result) ----
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
// ---- end ----

/// Version of the template set. Recorded in every result so that evaluation
/// runs can be reproduced.
const String kTemplateSetVersion = '2026-11-02';

enum ExtractionStatus { transaction, nonTransaction, unparsed }

enum TxnType { purchase, transferOut, transferIn, atmWithdrawal, refund, bill }

enum Channel { card, wallet, transfer, atm }

/// Hard problems: the result cannot be used automatically (status unparsed).
enum ValidationIssue {
  unclassified,
  noTemplate,
  amountMissing,
  amountNotPositive,
  currencyMissing,
  directionUnknown,
  dateInFuture,
  dateTooOld,
}

/// Soft warnings: the result stays a transaction but the user should look.
enum ExtractionFlag { foreignCurrency, timestampFromReceipt, dateMissing }

/// Public result of the extraction pipeline (the library contract).
///
/// Extra fields compared with the minimal contract: [direction] (an account
/// debit has a direction but no known type), [kind] (why a message is not a
/// transaction), [issues] and [flags].
///
/// [amountFils] is only meaningful as BHD when [currency] is 'BHD'. Never add
/// amounts of a flagged foreign currency to a BHD limit.
class ExtractionResult {
  const ExtractionResult({
    required this.status,
    this.kind,
    this.amountFils,
    this.currency,
    this.type,
    this.direction = TxDirection.unknown,
    this.merchantRaw,
    this.merchantNorm,
    this.category,
    this.channel,
    this.last4,
    this.timestamp,
    this.confidence = 0.0,
    this.templateVersion = '',
    this.issues = const [],
    this.flags = const [],
  });

  final ExtractionStatus status;
  final MessageKind? kind;
  final int? amountFils;
  final String? currency;
  final TxnType? type;
  final TxDirection direction;
  final String? merchantRaw;

  /// Filled later by the merchant normalizer.
  final String? merchantNorm;

  /// Filled later by the categorizer.
  final String? category;
  final Channel? channel;
  final String? last4;

  /// UTC instant.
  final DateTime? timestamp;
  final double confidence;
  final String templateVersion;
  final List<ValidationIssue> issues;
  final List<ExtractionFlag> flags;

  /// True when the user should check it: unusable, or usable with a warning.
  bool get needsReview =>
      status == ExtractionStatus.unparsed || flags.isNotEmpty;

  @override
  String toString() =>
      'ExtractionResult($status, fils: $amountFils, $currency, $type, '
      '$channel, at: $timestamp, conf: $confidence, issues: $issues, '
      'flags: $flags)';
}

/// Joins the classifier and Tier 1 outputs into an [ExtractionResult] and
/// applies the safety checks (Design 3.1, step 5).
class Validator {
  const Validator({
    this.maxAge = const Duration(days: 30),
    this.maxFutureSkew = const Duration(hours: 1),
  });

  /// A transaction time older than this (before the receive time) is rejected.
  final Duration maxAge;

  /// Small clock differences between the bank and the phone are tolerated.
  final Duration maxFutureSkew;

  ExtractionResult assemble({
    required ClassificationResult classification,
    Tier1Result? tier1,
    DateTime? receivedAt,
  }) {
    if (classification.kind == MessageKind.unknown) {
      // From a bank sender but not recognised: review it, do not drop it.
      return const ExtractionResult(
        status: ExtractionStatus.unparsed,
        kind: MessageKind.unknown,
        issues: [ValidationIssue.unclassified],
      );
    }
    if (!classification.isTransaction) {
      return ExtractionResult(
        status: ExtractionStatus.nonTransaction,
        kind: classification.kind,
        confidence: classification.confidence,
      );
    }
    if (tier1 == null) {
      return const ExtractionResult(
        status: ExtractionStatus.unparsed,
        kind: MessageKind.transaction,
        issues: [ValidationIssue.noTemplate],
      );
    }

    final issues = <ValidationIssue>[];
    final flags = <ExtractionFlag>[];

    final amount = tier1.amountFils;
    if (amount == null) {
      issues.add(ValidationIssue.amountMissing);
    } else if (amount <= 0) {
      issues.add(ValidationIssue.amountNotPositive);
    }

    final currency = tier1.currency.trim().toUpperCase();
    if (currency.isEmpty) {
      issues.add(ValidationIssue.currencyMissing);
    } else if (currency != 'BHD') {
      flags.add(ExtractionFlag.foreignCurrency);
    }

    final type = _typeOf(tier1);
    if (type == null && tier1.direction == TxDirection.unknown) {
      issues.add(ValidationIssue.directionUnknown);
    }

    var timestamp = tier1.occurredAt;
    final received = receivedAt?.toUtc();
    if (timestamp != null) {
      if (received != null) {
        if (timestamp.isAfter(received.add(maxFutureSkew))) {
          issues.add(ValidationIssue.dateInFuture);
        } else if (timestamp.isBefore(received.subtract(maxAge))) {
          issues.add(ValidationIssue.dateTooOld);
        }
      }
    } else if (received != null) {
      timestamp = received;
      flags.add(ExtractionFlag.timestampFromReceipt);
    } else {
      flags.add(ExtractionFlag.dateMissing);
    }

    return ExtractionResult(
      status: issues.isEmpty
          ? ExtractionStatus.transaction
          : ExtractionStatus.unparsed,
      kind: MessageKind.transaction,
      amountFils: amount,
      currency: currency.isEmpty ? null : currency,
      type: type,
      direction: tier1.direction,
      merchantRaw: tier1.merchant,
      channel: _channelOf(tier1.channel),
      last4: tier1.accountLast4,
      timestamp: timestamp,
      confidence: tier1.confidence,
      templateVersion: '${tier1.templateId}@$kTemplateSetVersion',
      issues: issues,
      flags: flags,
    );
  }

  static TxnType? _typeOf(Tier1Result t) {
    if (t.channel == TxChannel.card && t.direction == TxDirection.outgoing) {
      return TxnType.purchase;
    }
    if (t.channel == TxChannel.fawri) {
      if (t.direction == TxDirection.outgoing) return TxnType.transferOut;
      if (t.direction == TxDirection.incoming) return TxnType.transferIn;
    }
    // Account debits and credits do not say what they were: type stays null.
    return null;
  }

  static Channel? _channelOf(TxChannel c) {
    switch (c) {
      case TxChannel.card:
        return Channel.card;
      case TxChannel.fawri:
        return Channel.transfer;
      case TxChannel.account:
        return null;
    }
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
  const v = Validator();
  final recv = DateTime.utc(2026, 11, 2, 18, 5);
  final stdAt = DateTime.utc(2026, 11, 2, 18, 2);
  const txClass = ClassificationResult(
      kind: MessageKind.transaction, confidence: 0.85, rule: 'transaction');

  String names(Iterable<Enum> xs) => xs.map((e) => e.name).join(',');

  Tier1Result t1({
    int? amount = 2900,
    String currency = 'BHD',
    TxDirection dir = TxDirection.outgoing,
    TxChannel ch = TxChannel.fawri,
    DateTime? at,
    bool noDate = false,
    String? merchant,
    String? acct,
    double conf = 1.0,
  }) =>
      Tier1Result(
        templateId: 'bisb.fawri.out',
        amountFils: amount,
        currency: currency,
        direction: dir,
        channel: ch,
        confidence: conf,
        occurredAt: noDate ? null : (at ?? stdAt),
        merchant: merchant,
        accountLast4: acct,
      );

  ExtractionResult run(Tier1Result? t,
          {bool noReceived = false, Validator val = const Validator()}) =>
      val.assemble(
          classification: txClass,
          tier1: t,
          receivedAt: noReceived ? null : recv);

  // A valid transfer
  final ok = run(t1(acct: '7744'));
  check('valid: status', ok.status, ExtractionStatus.transaction);
  check('valid: type', ok.type, TxnType.transferOut);
  check('valid: channel', ok.channel, Channel.transfer);
  check('valid: amount', ok.amountFils, 2900);
  check('valid: currency', ok.currency, 'BHD');
  check('valid: last4', ok.last4, '7744');
  check('valid: timestamp kept', ok.timestamp, stdAt);
  check('valid: no issues or flags', '${names(ok.issues)}|${names(ok.flags)}', '|');
  check('valid: needsReview is false', ok.needsReview, false);
  check('valid: template version recorded', ok.templateVersion, 'bisb.fawri.out@2026-11-02');
  check('valid: confidence passes through', (ok.confidence * 1000).round(), 1000);

  // Type and channel mapping
  final card = run(t1(ch: TxChannel.card, merchant: 'SAMPLE BAKERY'));
  check('card purchase: type', card.type, TxnType.purchase);
  check('card purchase: channel', card.channel, Channel.card);
  check('card purchase: merchantRaw', card.merchantRaw, 'SAMPLE BAKERY');
  check('card purchase: merchantNorm and category empty', '${card.merchantNorm}|${card.category}', 'null|null');
  check('incoming transfer: type', run(t1(dir: TxDirection.incoming)).type, TxnType.transferIn);
  final acct = run(t1(ch: TxChannel.account));
  check('account debit: usable without a type', acct.status, ExtractionStatus.transaction);
  check('account debit: type and channel unknown', '${acct.type}|${acct.channel}|${acct.direction.name}', 'null|null|outgoing');

  // Mandatory fields
  final noDir = run(t1(dir: TxDirection.unknown));
  check('direction unknown: unparsed', noDir.status, ExtractionStatus.unparsed);
  check('direction unknown: issue', names(noDir.issues), 'directionUnknown');
  check('direction unknown: needsReview', noDir.needsReview, true);
  check('amount missing', names(run(t1(amount: null)).issues), 'amountMissing');
  check('amount zero', names(run(t1(amount: 0)).issues), 'amountNotPositive');
  check('amount negative', names(run(t1(amount: -5)).issues), 'amountNotPositive');
  check('two problems are both reported', names(run(t1(amount: 0, dir: TxDirection.unknown)).issues), 'amountNotPositive,directionUnknown');
  final noCur = run(t1(currency: ' '));
  check('currency empty: issue', names(noCur.issues), 'currencyMissing');
  check('currency empty: result currency is null', noCur.currency, null);

  // Currency
  final usd = run(t1(currency: 'USD'));
  check('foreign currency: flagged, still a transaction', '${usd.status.name}|${names(usd.flags)}|${usd.currency}', 'transaction|foreignCurrency|USD');
  check('foreign currency: needsReview', usd.needsReview, true);
  check('lowercase bhd is accepted', '${run(t1(currency: 'bhd')).currency}|${names(run(t1(currency: 'bhd')).flags)}', 'BHD|');

  // Date plausibility
  check('30 minutes ahead is tolerated', run(t1(at: recv.add(const Duration(minutes: 30)))).status, ExtractionStatus.transaction);
  check('2 hours ahead is rejected', names(run(t1(at: recv.add(const Duration(hours: 2)))).issues), 'dateInFuture');
  check('29 days old is accepted', run(t1(at: recv.subtract(const Duration(days: 29)))).status, ExtractionStatus.transaction);
  check('exactly 30 days old is accepted', run(t1(at: recv.subtract(const Duration(days: 30)))).status, ExtractionStatus.transaction);
  check('31 days old is rejected', names(run(t1(at: recv.subtract(const Duration(days: 31)))).issues), 'dateTooOld');
  check('maxAge is configurable', names(run(t1(at: recv.subtract(const Duration(days: 2))), val: const Validator(maxAge: Duration(days: 1))).issues), 'dateTooOld');
  check('implausible date is still kept for review', run(t1(at: recv.subtract(const Duration(days: 40)))).timestamp, recv.subtract(const Duration(days: 40)));

  // Missing date
  final fromReceipt = run(t1(noDate: true));
  check('no date: receive time is used', fromReceipt.timestamp, recv);
  check('no date: flagged', '${fromReceipt.status.name}|${names(fromReceipt.flags)}', 'transaction|timestampFromReceipt');
  final none = run(t1(noDate: true), noReceived: true);
  check('no date and no receive time', '${none.timestamp}|${names(none.flags)}', 'null|dateMissing');

  // Not a transaction, or not parsed
  final otp = v.assemble(classification: const ClassificationResult(kind: MessageKind.otp, confidence: 0.95, rule: 'otp'));
  check('OTP is nonTransaction', otp.status, ExtractionStatus.nonTransaction);
  check('OTP keeps its kind', otp.kind, MessageKind.otp);
  check('OTP has no amount', otp.amountFils, null);
  check('OTP confidence', (otp.confidence * 1000).round(), 950);
  check('declined is nonTransaction', v.assemble(classification: const ClassificationResult(kind: MessageKind.declined, confidence: 0.95, rule: 'declined')).kind, MessageKind.declined);
  check('no Tier 1 template is unparsed', names(run(null).issues), 'noTemplate');
  check('no Tier 1 template: status', run(null).status, ExtractionStatus.unparsed);
  final unknown = v.assemble(classification: const ClassificationResult(kind: MessageKind.unknown, confidence: 0.0, rule: 'none'));
  check('unrecognised message goes to review', '${unknown.status.name}|${names(unknown.issues)}', 'unparsed|unclassified');

  print('\n$passed passed, $failed failed');
}
