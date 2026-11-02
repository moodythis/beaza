import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:test/test.dart';

// Each check becomes one test (arguments are evaluated at registration).
void check(String name, Object? actual, Object? expected) =>
    test(name, () => expect(actual, expected));

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

}
