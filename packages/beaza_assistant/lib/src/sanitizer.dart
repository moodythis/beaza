/// What may leave the phone for a language model, and nothing else.
///
/// Never sent: message text, merchantRaw, card or account digits (last4,
/// counterpartyLast4), references, IBANs, phone numbers, e-mail addresses.
/// The assistant itself sends only numbers it already computed (metrics),
/// never single transactions; [entry] exists for a future feature and is
/// already limited to the allowed fields.
library;

import 'package:beaza_extraction/beaza_extraction.dart';

import 'response.dart';

class AiContextSanitizer {
  const AiContextSanitizer({this.merchants = const MerchantNormalizer()});

  final MerchantNormalizer merchants;

  static final RegExp _email =
      RegExp(r'[\w.+-]+@[\w-]+\.[\w.]+', unicode: true);
  static final RegExp _iban =
      RegExp(r'\b[A-Z]{2}\d{2}[A-Z0-9]{8,30}\b', caseSensitive: false);

  /// Seven or more digits, maybe split by spaces or dashes: phones,
  /// accounts, card numbers.
  static final RegExp _longNumber = RegExp(r'\d(?:[\s-]?\d){6,}');

  /// A short number right after a card or account word ("بطاقة 7744").
  static final RegExp _cardNumber = RegExp(
    r'(بطاق[هة]|حساب|رقم|card|account|ending|a/c|acc)(\s*(?:no\.?|رقم)?\s*)[\dX*]{3,}',
    caseSensitive: false,
    unicode: true,
  );

  /// The person's own words with contact and account details masked.
  /// Names cannot be found reliably, which is one reason the model is
  /// optional and asked for separately.
  String sanitizeText(String text) {
    var s = text.replaceAll(_email, '[email]');
    s = s.replaceAll(_iban, '[iban]');
    s = s.replaceAllMapped(_cardNumber, (m) => '${m[1]}${m[2]}[number]');
    s = s.replaceAll(_longNumber, '[number]');
    return s;
  }

  /// A shop name only when it is a known chain from the dictionary; any
  /// other name could be a person ("Waleed Al Kabah").
  String? safeMerchant(ExtractionResult r) {
    final info = merchants.normalize(r.merchantRaw ?? r.merchantNorm);
    return info != null && info.source == 'alias' ? info.name : null;
  }

  /// One transaction with only the allowed fields: amount, category, known
  /// chain name, type and the Bahrain date (no clock time).
  Map<String, Object?> entry(LedgerEntry e) {
    final r = e.result;
    final t = r.timestamp;
    final day = t == null ? null : Day.of(t);
    return {
      'amount_fils': r.amountFils,
      'currency': r.currency,
      'category': r.category,
      'merchant': safeMerchant(r),
      'type': r.type?.name,
      'date': day == null
          ? null
          : '${day.year.toString().padLeft(4, '0')}-'
              '${day.month.toString().padLeft(2, '0')}-'
              '${day.day.toString().padLeft(2, '0')}',
    };
  }

  /// The whole request context for the model.
  Map<String, Object?> context({
    required AssistantIntent intent,
    required String language,
    required String question,
    required List<Metric> metrics,
    required String draftReply,
  }) =>
      {
        'intent': intent.name,
        'language': language,
        'question': sanitizeText(question),
        'metrics': [for (final m in metrics) m.toJson()],
        'draft_reply': sanitizeText(draftReply),
      };
}
