/// Metrics for the evaluation harness (SRS FR-6.3, NFR-5).
library;

import '../detector.dart';
import '../normalizer.dart';
import 'gold.dart';
import 'systems.dart';

/// Fields compared one by one.
const evalFields = [
  'amount',
  'currency',
  'direction',
  'type',
  'merchant',
  'merchant_norm',
  'category',
  'last4',
  'time',
];

/// True positives, false positives and false negatives.
///
/// A wrong value counts as both a false positive (it was predicted) and a
/// false negative (the right value was missed), the usual rule for slot
/// filling.
class Counts {
  int tp = 0;
  int fp = 0;
  int fn = 0;

  double get precision => tp + fp == 0 ? double.nan : tp / (tp + fp);
  double get recall => tp + fn == 0 ? double.nan : tp / (tp + fn);
  double get f1 {
    // Nothing right but something expected or predicted: F1 is 0, even when
    // precision is undefined because nothing was predicted.
    if (tp == 0) return fp + fn == 0 ? double.nan : 0.0;
    final p = precision;
    final r = recall;
    return 2 * p * r / (p + r);
  }

  int get support => tp + fn;

  void add(Counts o) {
    tp += o.tp;
    fp += o.fp;
    fn += o.fn;
  }

  Map<String, dynamic> toJson() => {
        'tp': tp,
        'fp': fp,
        'fn': fn,
        'precision': _num(precision),
        'recall': _num(recall),
        'f1': _num(f1),
      };
}

Object? _num(double v) => v.isNaN ? null : double.parse(v.toStringAsFixed(4));

/// One field that a system got wrong on one message.
class FieldError {
  const FieldError(this.id, this.field, this.gold, this.predicted);
  final String id;
  final String field;
  final String? gold;
  final String? predicted;

  Map<String, dynamic> toJson() =>
      {'id': id, 'field': field, 'gold': gold, 'predicted': predicted};
}

/// Scores for one group of messages (all, one sender, one language...).
class Scores {
  int messages = 0;
  int goldTransactions = 0;

  /// Transaction or not.
  final Counts detection = Counts();
  final Map<String, Counts> fields = {for (final f in evalFields) f: Counts()};

  /// Gold transactions whose amount and currency are both exactly right.
  int amountExact = 0;

  /// Gold transactions the system accepted without review.
  int accepted = 0;

  /// Messages where detection and every field are right.
  int exactMatch = 0;

  double get amountExactRate =>
      goldTransactions == 0 ? double.nan : amountExact / goldTransactions;
  double get acceptedRate =>
      goldTransactions == 0 ? double.nan : accepted / goldTransactions;
  double get exactMatchRate =>
      messages == 0 ? double.nan : exactMatch / messages;

  Counts get micro {
    final c = Counts();
    for (final f in fields.values) {
      c.add(f);
    }
    return c;
  }

  Map<String, dynamic> toJson() => {
        'messages': messages,
        'gold_transactions': goldTransactions,
        'detection': detection.toJson(),
        'fields': {for (final e in fields.entries) e.key: e.value.toJson()},
        'fields_micro': micro.toJson(),
        'amount_exact_match': _num(amountExactRate),
        'accepted_without_review': _num(acceptedRate),
        'message_exact_match': _num(exactMatchRate),
      };
}

/// Result of scoring one system on one set of messages.
class Evaluation {
  Evaluation(this.systemId);

  final String systemId;
  final Scores overall = Scores();
  final Map<String, Scores> bySender = {};
  final Map<String, Scores> byLanguage = {};
  final List<FieldError> errors = [];

  Map<String, dynamic> toJson() => {
        'system': systemId,
        'overall': overall.toJson(),
        'by_sender': {for (final e in bySender.entries) e.key: e.value.toJson()},
        'by_language': {
          for (final e in byLanguage.entries) e.key: e.value.toJson()
        },
        'errors': [for (final e in errors) e.toJson()],
      };
}

/// Values are compared after this, so spacing and letter case do not count
/// as errors. Merchant normalization proper is measured separately (NFR-5).
String? canonical(String field, Object? v) {
  if (v == null) return null;
  if (v is DateTime) {
    // Minute precision: bank messages carry no seconds.
    final u = v.toUtc();
    return DateTime.utc(u.year, u.month, u.day, u.hour, u.minute)
        .toIso8601String();
  }
  final s = v.toString().trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return null;
  return field == 'merchant' || field == 'merchant_norm' || field == 'currency'
      ? s.toUpperCase()
      : s;
}

Map<String, String?> _goldValues(GoldLabel g) => {
      'amount': canonical('amount', g.amountFils),
      'currency': canonical('currency', g.currency),
      'direction': canonical('direction', g.direction),
      'type': canonical('type', g.type),
      'merchant': canonical('merchant', g.merchant),
      'merchant_norm': canonical('merchant_norm', g.merchantNorm),
      'category': canonical('category', g.category),
      'last4': canonical('last4', g.last4),
      'time': canonical('time', g.time),
    };

Map<String, String?> _predValues(Prediction p) => {
      'amount': canonical('amount', p.amountFils),
      'currency': canonical('currency', p.currency),
      'direction': canonical('direction', p.direction),
      'type': canonical('type', p.type),
      'merchant': canonical('merchant', p.merchant),
      'merchant_norm': canonical('merchant_norm', p.merchantNorm),
      'category': canonical('category', p.category),
      'last4': canonical('last4', p.last4),
      'time': canonical('time', p.time),
    };

/// Scores [system] on [messages].
Evaluation evaluate(EvalSystem system, List<GoldMessage> messages) {
  final ev = Evaluation(system.id);
  final senders = SenderFamilyDetector();
  const language = LanguageDetector();
  const normalizer = Normalizer();

  for (final m in messages) {
    final p = system.predict(m);
    final sender = senders.detect(m.sender).name;
    final lang = language.detect(normalizer.normalize(m.text)).name;
    final groups = [
      ev.overall,
      ev.bySender.putIfAbsent(sender, Scores.new),
      ev.byLanguage.putIfAbsent(lang, Scores.new),
    ];

    final g = m.label;
    final gold = _goldValues(g);
    final pred = _predValues(p);

    final det = Counts();
    if (g.isTransaction && p.isTransaction) det.tp++;
    if (!g.isTransaction && p.isTransaction) det.fp++;
    if (g.isTransaction && !p.isTransaction) det.fn++;

    final perField = <String, Counts>{};
    var allRight = g.isTransaction == p.isTransaction;
    for (final f in evalFields) {
      final c = Counts();
      final gv = gold[f];
      final pv = pred[f];
      if (gv != null && pv == gv) {
        c.tp++;
      } else {
        if (pv != null) c.fp++;
        if (gv != null) c.fn++;
      }
      if (gv != pv) {
        allRight = false;
        ev.errors.add(FieldError(m.id, f, gv, pv));
      }
      perField[f] = c;
    }

    final amountExact = g.isTransaction &&
        gold['amount'] != null &&
        gold['amount'] == pred['amount'] &&
        gold['currency'] == pred['currency'];

    for (final s in groups) {
      s.messages++;
      s.detection.add(det);
      for (final f in evalFields) {
        s.fields[f]!.add(perField[f]!);
      }
      if (g.isTransaction) {
        s.goldTransactions++;
        if (amountExact) s.amountExact++;
        if (p.accepted) s.accepted++;
      }
      if (allRight) s.exactMatch++;
    }
  }
  return ev;
}

/// Agreement between two annotators on the same messages (FR-6.2).
class Agreement {
  Agreement({
    required this.shared,
    required this.onlyA,
    required this.onlyB,
    required this.kappa,
    required this.observed,
    required this.fieldAgreement,
    required this.disagreements,
  });

  /// Ids labelled by both.
  final int shared;
  final int onlyA;
  final int onlyB;

  /// Cohen's kappa on transaction or not.
  final double kappa;

  /// Share of shared messages with the same transaction decision.
  final double observed;

  /// For each field, the share of messages both call a transaction where the
  /// two values match.
  final Map<String, double> fieldAgreement;
  final List<FieldError> disagreements;

  Map<String, dynamic> toJson() => {
        'shared': shared,
        'only_a': onlyA,
        'only_b': onlyB,
        'is_transaction_observed': _num(observed),
        'is_transaction_kappa': _num(kappa),
        'fields': {
          for (final e in fieldAgreement.entries) e.key: _num(e.value)
        },
        'disagreements': [for (final d in disagreements) d.toJson()],
      };
}

Agreement agreement(List<GoldMessage> a, List<GoldMessage> b) {
  final byId = {for (final m in b) m.id: m};
  final aIds = a.map((m) => m.id).toSet();
  var n = 0, both = 0, neither = 0, aYes = 0, bYes = 0;
  final same = {for (final f in evalFields) f: 0};
  var bothTx = 0;
  final dis = <FieldError>[];

  for (final ma in a) {
    final mb = byId[ma.id];
    if (mb == null) continue;
    n++;
    final la = ma.label, lb = mb.label;
    if (la.isTransaction) aYes++;
    if (lb.isTransaction) bYes++;
    if (la.isTransaction && lb.isTransaction) both++;
    if (!la.isTransaction && !lb.isTransaction) neither++;
    if (la.isTransaction != lb.isTransaction) {
      dis.add(FieldError(ma.id, 'is_transaction', '${la.isTransaction}',
          '${lb.isTransaction}'));
    }
    if (la.isTransaction && lb.isTransaction) {
      bothTx++;
      final ga = _goldValues(la), gb = _goldValues(lb);
      for (final f in evalFields) {
        if (ga[f] == gb[f]) {
          same[f] = same[f]! + 1;
        } else {
          dis.add(FieldError(ma.id, f, ga[f], gb[f]));
        }
      }
    }
  }

  final observed = n == 0 ? double.nan : (both + neither) / n;
  final pe = n == 0
      ? double.nan
      : (aYes / n) * (bYes / n) + ((n - aYes) / n) * ((n - bYes) / n);
  final kappa = n == 0
      ? double.nan
      : (pe == 1 ? (observed == 1 ? 1.0 : 0.0) : (observed - pe) / (1 - pe));

  return Agreement(
    shared: n,
    onlyA: a.length - n,
    onlyB: b.where((m) => !aIds.contains(m.id)).length,
    kappa: kappa,
    observed: observed,
    fieldAgreement: {
      for (final f in evalFields)
        f: bothTx == 0 ? double.nan : same[f]! / bothTx
    },
    disagreements: dis,
  );
}
