/// Message classifier: separates transactions from other bank messages.
library;

enum MessageKind {
  transaction,
  declined,
  otp,
  securityNotice,
  promotion,
  statement,
  balanceInquiry,

  /// Service news with no amount at all (maintenance, new rates...).
  information,
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
/// balance, information (no amount at all), unknown.
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
    r'\boffers?\b|\bpromo(?:tion)?s?\b|cash\s?back|\bdiscounts?\b|\bwin\b|\bprizes?\b|\d+\s?%\s?off|apply\s+(?:for|now)|\bcampaign\b|chance\s+to|earn\s+more|high\s+yield|\bp\.a\.|rates?\s+(?:have\s+|has\s+)?increased|عرض|عروض|اربح|جوائز|تخفيض|خصومات|قدّم\s+الآن|حملة',
    caseSensitive: false,
  );

  // Includes common BenefitPay wording (عملية مقبولة, نجحت العملية,
  // تم استلام). These phrases still need confirmation on real notifications.
  static final RegExp _transactionCue = RegExp(
    r'\bpurchase\b|\bdebited\b|\bcredited\b|\btransfer\b|\bpayment\b|\bwithdraw(?:al|n)?\b|\brefund(?:ed)?\b|\breversal\b|\bdeposit(?:ed)?\b|\bpaid\b|\breceived\b|using\s+your\s+(?:debit|credit)\s+card|transaction\s+approved|payment\s+successful|عملية\s+مقبولة|نجحت\s+العملية|تم\s+استلام|خصم|إيداع|ايداع|شراء|تحويل|حوالة|سحب|دفع|استرداد|استرجاع',
    caseSensitive: false,
  );

  static final RegExp _amount = RegExp(r'BHD\s?\d|\d\s?BHD');

  // Any amount in any currency code, for the "no amount at all" rule.
  static final RegExp _anyAmount =
      RegExp(r'\b[A-Z]{3}\s?\d|\d\s?[A-Z]{3}\b');

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
    // A money movement always states an amount; with no amount and no
    // transaction word it is news. (A transaction word without an amount
    // stays unknown and goes to review.)
    if (cues == 0 && !_anyAmount.hasMatch(t)) {
      return _r(MessageKind.information, 0.60, 'information.noAmount');
    }
    return _r(MessageKind.unknown, 0.0, 'none');
  }

  static ClassificationResult _r(MessageKind k, double c, String rule) =>
      ClassificationResult(kind: k, confidence: c, rule: rule);
}
