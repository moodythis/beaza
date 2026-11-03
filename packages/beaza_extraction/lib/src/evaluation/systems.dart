/// Systems compared by the evaluation harness (SRS FR-6.4) and the data
/// splits they are compared on (NFR-10).
library;

import '../classifier.dart';
import '../detector.dart';
import '../extractor.dart';
import '../tier1.dart';
import '../validator.dart';
import 'gold.dart';

/// What a system predicted for one message, in the same shape as a label.
class Prediction {
  const Prediction({
    required this.isTransaction,
    this.accepted = false,
    this.amountFils,
    this.currency,
    this.direction,
    this.type,
    this.merchant,
    this.merchantNorm,
    this.category,
    this.last4,
    this.time,
  });

  /// The system says this is a transaction (it may still need review).
  final bool isTransaction;

  /// Usable without review: would count toward the guardrail at once.
  final bool accepted;
  final int? amountFils;
  final String? currency;
  final String? direction;
  final String? type;
  final String? merchant;
  final String? merchantNorm;
  final String? category;
  final String? last4;
  final DateTime? time;

  /// Maps a pipeline result. A time copied from the receive time is not a
  /// prediction of the message's time, so it is left out.
  factory Prediction.fromResult(ExtractionResult r) {
    final fromReceipt = r.flags.contains(ExtractionFlag.timestampFromReceipt);
    return Prediction(
      isTransaction: r.kind == MessageKind.transaction,
      accepted: r.status == ExtractionStatus.transaction,
      amountFils: r.amountFils,
      currency: r.currency,
      direction:
          r.direction == TxDirection.unknown ? null : r.direction.name,
      type: r.type?.name,
      merchant: r.merchantRaw,
      merchantNorm: r.merchantNorm,
      category: r.category,
      last4: r.last4,
      time: fromReceipt ? null : r.timestamp,
    );
  }
}

/// A system under evaluation.
abstract class EvalSystem {
  String get id;
  String get description;
  Prediction predict(GoldMessage m);
}

/// B1: rules only. The shipped pipeline (normalize, classify, Tier 1
/// templates, validate) with the sender filter off, because gold files may
/// use sender names the phone would not see.
class RulesSystem implements EvalSystem {
  RulesSystem() : _x = BeazaExtractor(requireKnownSender: false);

  final BeazaExtractor _x;

  @override
  String get id => 'B1';

  @override
  String get description =>
      'Rules only: Tier 1 templates (template set $kTemplateSetVersion)';

  @override
  Prediction predict(GoldMessage m) => Prediction.fromResult(_x.process(
      RawMessage(text: m.text, sender: m.sender, receivedAt: m.receivedAt)));
}

/// Ids of systems the SRS names but that are not built yet.
const plannedSystems = {
  'B2': 'LLM only (needs the Tier 2 model, FR-3.6)',
  'B3': 'Hybrid: Tier 1 then Tier 2 fallback (needs the Tier 2 model, FR-3.6)',
};

EvalSystem? systemById(String id) {
  switch (id.toUpperCase()) {
    case 'B1':
      return RulesSystem();
  }
  return null;
}

/// How messages are split into development and test parts.
enum SplitKind {
  /// Every message is evaluated (no split).
  all,

  /// Deterministic pseudo-random split by message id and seed.
  random,

  /// The latest messages by receive time are the test part.
  time,

  /// Messages from the held-out sender families are the test part.
  template,
}

class Split {
  const Split(this.dev, this.test, this.describe);
  final List<GoldMessage> dev;
  final List<GoldMessage> test;
  final String describe;
}

/// Splits [messages]. The same inputs always give the same split.
Split splitMessages(
  List<GoldMessage> messages, {
  SplitKind kind = SplitKind.all,
  double testFraction = 0.3,
  int seed = 42,
  Set<SenderFamily> holdout = const {},
  SenderFamilyDetector? senders,
}) {
  switch (kind) {
    case SplitKind.all:
      return Split(const [], List.of(messages), 'all messages');
    case SplitKind.random:
      final dev = <GoldMessage>[];
      final test = <GoldMessage>[];
      for (final m in messages) {
        final bucket = int.parse(fnv1a('$seed:${m.id}'), radix: 16) % 1000;
        (bucket < testFraction * 1000 ? test : dev).add(m);
      }
      return Split(dev, test,
          'random by id, seed $seed, test fraction $testFraction');
    case SplitKind.time:
      final sorted = List.of(messages)
        ..sort((a, b) {
          final c = a.receivedAt.compareTo(b.receivedAt);
          return c != 0 ? c : a.id.compareTo(b.id);
        });
      final cut = (sorted.length * (1 - testFraction)).round();
      final describe = cut < sorted.length
          ? 'by receive time, test from ${sorted[cut].receivedAt.toIso8601String()}'
          : 'by receive time (test part empty)';
      return Split(sorted.sublist(0, cut), sorted.sublist(cut), describe);
    case SplitKind.template:
      if (holdout.isEmpty) {
        throw ArgumentError('a template split needs at least one held-out sender family');
      }
      final s = senders ?? SenderFamilyDetector();
      final dev = <GoldMessage>[];
      final test = <GoldMessage>[];
      for (final m in messages) {
        (holdout.contains(s.detect(m.sender)) ? test : dev).add(m);
      }
      final names = holdout.map((f) => f.name).toList()..sort();
      return Split(dev, test, 'held-out sender families: ${names.join(', ')}');
  }
}
