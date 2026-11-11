import 'package:beaza_extraction/beaza_extraction.dart';

enum AssistantIntent {
  spendingQuery,
  logExpense,
  guardrailAdvice,
  unknown,

  /// Not about the person's spending or budget (kAssistantScopeJson): turned
  /// away on the phone, never sent to a model.
  outOfScope,

  /// "Can I afford a laptop for 300 BD?": what the price does to the limit.
  canIBuy,
}

/// What the app knows about a price from its budget plan ("Can I buy it?",
/// FR-5.10). All null without a plan.
class AffordFacts {
  const AffordFacts({
    this.monthLeftFils,
    this.limitFromTomorrowFils,
    this.limitIfBoughtFils,
  });

  /// Free money left this month after today's spending.
  final int? monthLeftFils;

  /// The limit from tomorrow without and with the purchase; null on the
  /// last day of the month.
  final int? limitFromTomorrowFils;
  final int? limitIfBoughtFils;
}

/// Who wrote the reply text. The numbers are always computed on the phone.
enum ResponseSource { local, llm }

enum MetricUnit { fils, percent, count, days }

/// A number the reply is based on, computed on the phone.
class Metric {
  const Metric(this.key, this.value, this.unit, {this.display});

  final String key;
  final int value;
  final MetricUnit unit;

  /// How the number is written in the reply ("1.500 د.ب").
  final String? display;

  Map<String, Object?> toJson() => {
        'key': key,
        'value': value,
        'unit': unit.name,
        if (display != null) 'display': display,
      };

  @override
  String toString() => '$key=$value';
}

/// A cash expense read from the person's words. Never saved by itself: the
/// app shows it and the person confirms.
class DraftTransaction {
  const DraftTransaction({
    required this.amountFils,
    required this.timestamp,
    this.merchantRaw,
    this.category,
    this.type = TxnType.purchase,
    this.amountGuessed = false,
  });

  final int amountFils;
  final DateTime timestamp;

  /// What was bought or where, in the person's words ("شاورما").
  final String? merchantRaw;
  final String? category;
  final TxnType type;

  /// True when no unit was written ("كرك 200").
  final bool amountGuessed;

  /// As a ledger result once confirmed.
  ExtractionResult toResult() => ExtractionResult(
        status: ExtractionStatus.transaction,
        kind: MessageKind.transaction,
        amountFils: amountFils,
        currency: 'BHD',
        type: type,
        direction: TxDirection.outgoing,
        merchantRaw: merchantRaw,
        category: category,
        timestamp: timestamp.toUtc(),
      );

  @override
  String toString() =>
      'Draft($amountFils, $merchantRaw, $category${amountGuessed ? ', guessed' : ''})';
}

class AssistantResponse {
  const AssistantResponse({
    required this.intent,
    required this.replyText,
    this.draftTransactions = const [],
    this.referencedMetrics = const [],
    this.source = ResponseSource.local,
  });

  final AssistantIntent intent;
  final String replyText;
  final List<DraftTransaction> draftTransactions;
  final List<Metric> referencedMetrics;
  final ResponseSource source;

  AssistantResponse withText(String text, ResponseSource source) =>
      AssistantResponse(
        intent: intent,
        replyText: text,
        draftTransactions: draftTransactions,
        referencedMetrics: referencedMetrics,
        source: source,
      );
}
