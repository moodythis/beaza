// Stage 3 (Message classifier) as a single file for dartpad.dev.
// Paste everything into DartPad and press Run.

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

/// Separates real money movements from other bank messages.
/// Input is normalized text (digits Western, currency token BHD).
/// Check order: declined, OTP, statement, strong security, weak security
/// (only when the message is not a transaction), promotion, transaction,
/// balance, unknown.
class MessageClassifier {
  const MessageClassifier();

  static final RegExp _declined = RegExp(
    r'\bdeclined\b|insufficient\s+funds|not\s+approved|رفض|مرفوض|غير\s+مقبول|عدم\s+كفاية|غير\s+كاف',
    caseSensitive: false,
  );

  static final RegExp _otpKeyword = RegExp(
    r'\botp\b|one[\s-]?time\s+(?:password|pin|code)|verification\s+code|security\s+code|رمز\s+(?:التحقق|التفعيل|الأمان|الامان)|لمرة\s+واحدة',
    caseSensitive: false,
  );

  // A real OTP message carries a 4-8 digit code (not part of an amount).
  static final RegExp _otpCode = RegExp(r'(?<![\d.])\d{4,8}(?!\d|\.\d)');

  static final RegExp _statement = RegExp(
    r'e-?statement|account\s+statement|statement\s+(?:is|has\s+been)\s+(?:ready|available)|كشف\s+(?:الحساب|حسابك)',
    caseSensitive: false,
  );

  // Specific phrases: these win even over a transaction-looking message.
  static final RegExp _securityStrong = RegExp(
    r'phishing|scam|suspicious|suspected\s+fraud|fraud\s+alert|security\s+(?:alert|notice|warning)|new\s+device|unauthori[sz]ed|تنبيه\s+(?:أمني|امني)|تصيد|مشبوه|جهاز\s+جديد|غير\s+مصرح',
    caseSensitive: false,
  );

  // Footer-style warnings. Real transaction messages often end with them, so
  // they count only when the message is not a transaction.
  static final RegExp _securityWeak = RegExp(
    r'never\s+share|do\s+not\s+share|don.?t\s+share|will\s+never\s+ask|\bfraud\b|\bbeware\b|لا\s+تشارك|لن\s+نطلب|احتيال|احذر|كن\s+حذر',
    caseSensitive: false,
  );

  // Plain "خصم" is NOT here: in bank messages it means "debited".
  static final RegExp _promotion = RegExp(
    r'\boffers?\b|\bpromo(?:tion)?s?\b|cash\s?back|\bdiscounts?\b|\bwin\b|\bprizes?\b|\d+\s?%\s?off|عرض|عروض|اربح|جوائز|تخفيض|خصومات',
    caseSensitive: false,
  );

  // Includes common BenefitPay wording (عملية مقبولة, نجحت العملية,
  // تم استلام). These phrases still need confirmation on real notifications.
  static final RegExp _transactionCue = RegExp(
    r'\bpurchase\b|\bdebited\b|\bcredited\b|\btransfer\b|\bpayment\b|\bwithdraw(?:al|n)?\b|\brefund(?:ed)?\b|\breversal\b|\bdeposit(?:ed)?\b|\bpaid\b|\breceived\b|using\s+your\s+(?:debit|credit)\s+card|transaction\s+approved|payment\s+successful|عملية\s+مقبولة|نجحت\s+العملية|تم\s+استلام|خصم|إيداع|ايداع|شراء|تحويل|حوالة|سحب|دفع|استرداد|استرجاع',
    caseSensitive: false,
  );

  static final RegExp _amount = RegExp(r'BHD\s?\d|\d\s?BHD');

  static final RegExp _balance = RegExp(
    r'\bbalance\b|\bbal\b|رصيد',
    caseSensitive: false,
  );

  ClassificationResult classify(String normalizedText) {
    final t = normalizedText;

    if (_declined.hasMatch(t)) {
      return _r(MessageKind.declined, 0.95, 'declined');
    }
    if (_otpKeyword.hasMatch(t) && _otpCode.hasMatch(t)) {
      return _r(MessageKind.otp, 0.95, 'otp');
    }
    if (_statement.hasMatch(t)) {
      return _r(MessageKind.statement, 0.90, 'statement');
    }
    if (_securityStrong.hasMatch(t)) {
      return _r(MessageKind.securityNotice, 0.90, 'security.strong');
    }

    final cues = _transactionCue
        .allMatches(t)
        .map((m) => m.group(0)!.toLowerCase())
        .toSet()
        .length;
    final isTx = cues > 0 && _amount.hasMatch(t);

    if (!isTx && _securityWeak.hasMatch(t)) {
      return _r(MessageKind.securityNotice, 0.75, 'security.weak');
    }
    if (_promotion.hasMatch(t)) {
      return _r(MessageKind.promotion, 0.80, 'promotion');
    }
    if (isTx) {
      final conf = cues >= 3 ? 0.95 : (cues == 2 ? 0.85 : 0.70);
      return _r(MessageKind.transaction, conf, 'transaction');
    }
    if (_balance.hasMatch(t)) {
      return _r(MessageKind.balanceInquiry, 0.70, 'balance');
    }
    return _r(MessageKind.unknown, 0.0, 'none');
  }

  static ClassificationResult _r(MessageKind k, double c, String rule) =>
      ClassificationResult(kind: k, confidence: c, rule: rule);
}

int passed = 0;
int failed = 0;

void check(String name, Object actual, Object expected) {
  if (actual == expected) {
    passed++;
    print('PASS  $name');
  } else {
    failed++;
    print('FAIL  $name\n  expected: $expected\n  actual:   $actual');
  }
}

void main() {
  const c = MessageClassifier();
  const tx = MessageKind.transaction;
  MessageKind kindOf(String s) => c.classify(s).kind;

  // Formats modelled on real Bahraini messages (names and numbers changed).
  // BisB style
  check('BisB Fawri+ out', kindOf('Fawri+ payment BHD2.900, ref: BIB103KAA000AAAA was credited to IBAN ending 4411 on 2026/10/30 00:59. Balance BHD9.999. Tel: 17515151'), tx);
  check('BisB Fawri+ in', kindOf('Fawri+ payment BHD8.800 received from IBAN 5522 to IBAN 6633 ref. BIB103KAB000BBBB on 2026/10/25 06:15. Balance BHD9.999. Tel 17515151'), tx);
  check('BisB debit card', kindOf('Dear CLIENT, thank you for using your Debit card 7744 for BHD 0.300 at SAMPLE BAKERY - MAL BAH BH-000001 on 15/10 @16:31. Avail Bal BHD 9.999. Tel 17515151'), tx);

  // ila style
  check('ila Fawri+ in', kindOf('Success! Fawri+ transfer of BHD 50.000 from IBAN ****0777 credited to BHD Ac on 02/11/2026 12:11 Ref ALS103KAC000CCCC Balance BHD 9.999 Enquiry 17123456'), tx);
  check('ila Fawri+ out', kindOf('Success! Fawri+ transfer of BHD 49.000 to IBAN ****9966 is completed on 01/11/2026 20:45 Ref ABCO260000000001 Balance BHD 9.999 Enquiry 17123456'), tx);
  check('ila purchase', kindOf('Success! Purchase at SAMPLE TRADING CO W using card ****8855 for BHD 1.500 on 29/10/2026 15:42 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456'), tx);
  check('ila purchase without Success', kindOf('Purchase at SAMPLE MARKET ISA TOWN BH using card ****8855 for BHD 14.900 on 14/10/2026 17:37 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456'), tx);
  check('ila purchase with &amp;', kindOf('Success! Purchase at INFO &amp; SAMPLE AUTHOR using card ****8855 for BHD 5.000 on 14/10/2026 17:16 debited from BHD Ac Balance BHD 9.999 Enquiry 17123456'), tx);
  check('ila DECLINED', kindOf('DECLINED. Your BHD account has insufficient funds. Please fund it and try again. Card ****8855 for BHD 1.500 on 29/10/2026 15:41 Enquiry 17123456'), MessageKind.declined);

  // Al Salam style
  check('Al Salam debit', kindOf('Dear Client, BHD 0.400 has been debited from your account XXXX10100777. Your balance is BHD 9.999 on 30/10/26 at 01:27. Thank you, Al Salam Bank.'), tx);
  check('Al Salam Fawri+ in', kindOf('Fawri+ BHD 6.000 ref BIB103KAD000DDDD from IBAN BH35BIBBXXXXXXXXXXXX27 credited to acct XXX10100777. Bal: BHD 9.999 on 26/10/26 at 15:39. Tel 17005500'), tx);

  // Arabic transactions
  check('Arabic debit', kindOf('تم خصم 12.500 BHD من بطاقتك لدى CAFE ROMA'), tx);
  check('Arabic deposit', kindOf('تم إيداع 50.000 BHD في حسابك'), tx);
  check('Arabic purchase', kindOf('تمت عملية شراء بقيمة 4.250 BHD لدى TALABAT'), tx);

  // BenefitPay-style notifications (wording to be confirmed on real ones)
  check('BenefitPay approved', kindOf('عملية مقبولة بمبلغ 2.500 BHD لدى COSTA COFFEE'), tx);
  check('BenefitPay succeeded', kindOf('نجحت العملية: 5.000 BHD'), tx);
  check('BenefitPay received', kindOf('تم استلام 10.000 BHD من أحمد'), tx);
  check('BenefitPay not accepted is declined', kindOf('عملية غير مقبولة بمبلغ 2.500 BHD'), MessageKind.declined);
  check('Request received without amount', kindOf('تم استلام طلبك وسيتم التواصل معك'), MessageKind.unknown);
  check('English approved', kindOf('Transaction approved for BHD 3.000 at SHOP'), tx);

  // OTP and security notices
  check('OTP wins over payment words', kindOf('Your OTP for card payment BHD 5.000 at SHOP is 123456. Do not share it.'), MessageKind.otp);
  check('Arabic OTP', kindOf('رمز التحقق 123456 لا تشاركه مع أحد'), MessageKind.otp);
  check('Awareness message is not OTP', kindOf('Beware of phishing. Never share your PIN or OTP with anyone.'), MessageKind.securityNotice);
  check('Never share only', kindOf('Never share your OTP with anyone'), MessageKind.securityNotice);
  check('New device login', kindOf('Security alert: new device login to your account'), MessageKind.securityNotice);
  check('Arabic security alert', kindOf('تنبيه أمني: لا تشارك رمز التحقق مع أحد'), MessageKind.securityNotice);
  check('Fraud alert beats transaction', kindOf('Fraud alert: unauthorized purchase of BHD 50.000 at SHOP'), MessageKind.securityNotice);
  check('Footer warning keeps transaction', kindOf('Purchase at SHOP using card ****8855 for BHD 3.000 debited from BHD Ac. Never share your PIN. Enquiry 17123456'), tx);

  // Other non-transactions
  check('Promotion', kindOf('Get 20% cashback offer at Costa Coffee until 30/11. Terms apply'), MessageKind.promotion);
  check('Promotion wins over purchase', kindOf('Make a purchase of BHD 10 and get 10% cashback offer'), MessageKind.promotion);
  check('Arabic promotion', kindOf('عرض خاص: اربح قسيمة شراء بقيمة 10 BHD'), MessageKind.promotion);
  check('Statement', kindOf('Your e-statement for October is ready'), MessageKind.statement);
  check('Arabic statement', kindOf('كشف حسابك لشهر أكتوبر جاهز'), MessageKind.statement);
  check('Balance inquiry', kindOf('Your available balance is BHD 5.000 as of 02/11/2026'), MessageKind.balanceInquiry);
  check('Arabic balance', kindOf('رصيدك المتاح هو 5.000 BHD'), MessageKind.balanceInquiry);
  check('Arabic declined', kindOf('تم رفض العملية بسبب عدم كفاية الرصيد'), MessageKind.declined);
  check('Cue without amount is unknown', kindOf('Your card purchase was successful'), MessageKind.unknown);
  check('Greeting is unknown', kindOf('Hello from your bank'), MessageKind.unknown);
  check('Empty is unknown', kindOf(''), MessageKind.unknown);

  // ClassificationResult
  final fawri = c.classify('Fawri+ payment BHD2.900, ref: BIB103KAA000AAAA was credited to IBAN ending 4411 on 2026/10/30 00:59. Balance BHD9.999. Tel: 17515151');
  check('isTransaction true', fawri.isTransaction, true);
  check('Two cues give 0.85', fawri.confidence, 0.85);
  check('Rule name', fawri.rule, 'transaction');
  final single = c.classify('Dear Client, BHD 0.400 has been debited from your account XXXX10100777. Your balance is BHD 9.999 on 30/10/26 at 01:27. Thank you, Al Salam Bank.');
  check('One cue gives 0.70', single.confidence, 0.70);
  final otp = c.classify('Your OTP is 123456');
  check('isTransaction false for OTP', otp.isTransaction, false);
  check('OTP confidence', otp.confidence, 0.95);
  final none = c.classify('Hello from your bank');
  check('Unknown confidence is 0', none.confidence, 0.0);
  check('Unknown isTransaction false', none.isTransaction, false);

  print('\n$passed passed, $failed failed');
}
