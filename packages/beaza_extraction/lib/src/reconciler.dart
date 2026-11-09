/// Stage 6: duplicates, the user's own accounts, and what counts as spending.
library;

import 'tier1.dart' show TxDirection;
import 'validator.dart';

/// Last digits of accounts and cards that belong to the user.
///
/// Nothing is trusted until the user confirms it: [suggestions] lists the
/// account digits seen on the user's side of messages so the app can ask
/// "Is this your account?". Only confirmed accounts make a transfer internal.
class OwnAccounts {
  OwnAccounts({
    Iterable<String> confirmed = const [],
    Iterable<String> rejected = const [],
  })  : _confirmed = {...confirmed},
        _rejected = {...rejected};

  final Set<String> _confirmed;
  final Set<String> _rejected;

  Set<String> get confirmed => Set.unmodifiable(_confirmed);

  void confirm(String last4) {
    _rejected.remove(last4);
    _confirmed.add(last4);
  }

  void reject(String last4) {
    _confirmed.remove(last4);
    _rejected.add(last4);
  }

  bool isOwn(String? last4) => last4 != null && _confirmed.contains(last4);

  /// Account digits from the user's side of valid transactions that the user
  /// has not answered yet, in the order first seen.
  List<String> suggestions(Iterable<ExtractionResult> results) {
    final out = <String>[];
    for (final r in results) {
      final d = r.last4;
      if (r.status != ExtractionStatus.transaction || d == null) continue;
      if (_confirmed.contains(d) || _rejected.contains(d) || out.contains(d)) {
        continue;
      }
      out.add(d);
    }
    return out;
  }
}

/// Money received that pays back something the person paid for (a friend's
/// share of a meal they covered, a shop's refund). Taken off spending on the
/// day it arrives. Set by the person, or found by [Reconciler] (see there).
const String kRepaymentCategory = 'repayment';

/// The person said money received is not a repayment: plain income.
const String kReceivedCategory = 'received';

/// How far back spending can be paid back by a transfer found on its own.
/// Friends often pay back after more than a week.
const Duration kRepaymentWindow = Duration(days: 30);

enum EntryRole {
  /// Money the user spent: counts toward the daily limit (if in BHD).
  spending,

  /// Money received.
  income,

  /// Between two of the user's own accounts: neither spending nor income.
  internalTransfer,

  /// Another copy of an earlier entry (same reference): ignored.
  duplicate,

  /// Not a usable transaction (non-transaction or unparsed).
  notCounted,

  /// Money received that the person marked as paid back to them
  /// ([kRepaymentCategory]): taken off spending.
  repayment,
}

class LedgerEntry {
  const LedgerEntry({
    required this.index,
    required this.result,
    required this.role,
    this.duplicateOf,
    this.possibleDuplicateOf,
  });

  /// Position in the input list.
  final int index;
  final ExtractionResult result;
  final EntryRole role;

  /// Set when [role] is [EntryRole.duplicate].
  final int? duplicateOf;

  /// Same amount, direction and time window as an earlier entry but no shared
  /// reference. Still counted; the app asks the user whether it is a copy.
  final int? possibleDuplicateOf;

  bool get countsTowardSpending =>
      role == EntryRole.spending && result.currency == 'BHD';

  /// Money paid back to the person, in BHD.
  bool get isRepayment =>
      role == EntryRole.repayment && result.currency == 'BHD';

  /// What this entry adds to spending: the amount for spending, minus the
  /// amount for money paid back, 0 for anything else.
  int get countedFils {
    final a = result.amountFils ?? 0;
    if (countsTowardSpending) return a;
    if (isRepayment) return -a;
    return 0;
  }
}

/// Decides the role of every extracted result. Pure: the same input gives the
/// same output, so roles are simply recomputed after the user answers a
/// question (for example confirms an account).
class Reconciler {
  const Reconciler({this.window = const Duration(minutes: 10)});

  /// How close in time two copies without a reference must be.
  final Duration window;

  List<LedgerEntry> reconcile(
    List<ExtractionResult> results,
    OwnAccounts accounts,
  ) {
    final n = results.length;
    final roles = List<EntryRole>.filled(n, EntryRole.notCounted);
    final dupOf = List<int?>.filled(n, null);
    final maybeDupOf = List<int?>.filled(n, null);

    for (var i = 0; i < n; i++) {
      final r = results[i];
      if (r.status != ExtractionStatus.transaction) continue;

      final ref = r.reference;
      if (ref != null) {
        final same = _earlier(results, i, (o) =>
            o.reference == ref && o.direction == r.direction);
        if (same != null) {
          roles[i] = EntryRole.duplicate;
          dupOf[i] = same;
          continue;
        }
        final other = _earlier(results, i, (o) =>
            o.reference == ref && _opposite(o.direction, r.direction));
        if (other != null) {
          // Both legs of one transfer reached the phone: own accounts.
          roles[i] = EntryRole.internalTransfer;
          roles[other] = EntryRole.internalTransfer;
          continue;
        }
      }

      if (_isTransfer(r) && accounts.isOwn(r.counterpartyLast4)) {
        roles[i] = EntryRole.internalTransfer;
        continue;
      }

      if (r.direction == TxDirection.outgoing) {
        roles[i] = EntryRole.spending;
      } else if (r.direction == TxDirection.incoming) {
        roles[i] = r.category == kRepaymentCategory
            ? EntryRole.repayment
            : EntryRole.income;
      } else {
        continue;
      }
      maybeDupOf[i] = _possibleDuplicate(results, roles, i);
    }

    _findRepayments(results, roles);

    return [
      for (var i = 0; i < n; i++)
        LedgerEntry(
          index: i,
          result: results[i],
          role: roles[i],
          duplicateOf: dupOf[i],
          possibleDuplicateOf: maybeDupOf[i],
        ),
    ];
  }

  /// Money received that the person did not label is a repayment when the
  /// bank message shows it can only be one of two things and the amount fits:
  /// a shop's refund always; a transfer from someone when it is no more than
  /// what the person spent in the 30 days before it, less what was already
  /// paid back in that time. A salary is usually more than that, so it stays
  /// income and is not counted twice with a budget worked out from income. The person can undo either way
  /// ([kReceivedCategory], [kRepaymentCategory]).
  static void _findRepayments(
      List<ExtractionResult> results, List<EntryRole> roles) {
    final candidates = <int>[
      for (var i = 0; i < results.length; i++)
        if (roles[i] == EntryRole.income &&
            results[i].category == null &&
            results[i].currency == 'BHD' &&
            results[i].timestamp != null &&
            (results[i].amountFils ?? 0) > 0 &&
            (results[i].type == TxnType.refund || _isTransfer(results[i])))
          i,
    ]..sort((a, b) => results[a].timestamp!.compareTo(results[b].timestamp!));
    for (final i in candidates) {
      final r = results[i];
      if (r.type == TxnType.refund) {
        roles[i] = EntryRole.repayment;
        continue;
      }
      final t = r.timestamp!;
      final from = t.subtract(kRepaymentWindow);
      var room = 0;
      for (var j = 0; j < results.length; j++) {
        final o = results[j];
        final ot = o.timestamp;
        if (ot == null || ot.isBefore(from) || ot.isAfter(t)) continue;
        if (o.currency != 'BHD' || j == i) continue;
        final a = o.amountFils ?? 0;
        if (roles[j] == EntryRole.spending) room += a;
        if (roles[j] == EntryRole.repayment) room -= a;
      }
      if (r.amountFils! <= room) roles[i] = EntryRole.repayment;
    }
  }

  /// Sum of spending in BHD fils. Foreign-currency entries are left out.
  static int spentFils(Iterable<LedgerEntry> entries) => entries
      .where((e) => e.countsTowardSpending)
      .fold(0, (sum, e) => sum + (e.result.amountFils ?? 0));

  /// Spending minus money paid back (can be below 0 when more came back).
  static int netFils(Iterable<LedgerEntry> entries) =>
      entries.fold(0, (sum, e) => sum + e.countedFils);

  static int? _earlier(
    List<ExtractionResult> results,
    int i,
    bool Function(ExtractionResult) test,
  ) {
    for (var j = 0; j < i; j++) {
      final o = results[j];
      if (o.status == ExtractionStatus.transaction && test(o)) return j;
    }
    return null;
  }

  static bool _opposite(TxDirection a, TxDirection b) =>
      (a == TxDirection.outgoing && b == TxDirection.incoming) ||
      (a == TxDirection.incoming && b == TxDirection.outgoing);

  static bool _isTransfer(ExtractionResult r) =>
      r.type == TxnType.transferIn ||
      r.type == TxnType.transferOut ||
      r.channel == Channel.transfer;

  int? _possibleDuplicate(
    List<ExtractionResult> results,
    List<EntryRole> roles,
    int i,
  ) {
    final r = results[i];
    for (var j = i - 1; j >= 0; j--) {
      if (roles[j] != EntryRole.spending &&
          roles[j] != EntryRole.income &&
          roles[j] != EntryRole.repayment) {
        continue;
      }
      final o = results[j];
      if (o.amountFils == null || o.amountFils != r.amountFils) continue;
      if (o.direction != r.direction) continue;
      if (o.reference != null &&
          r.reference != null &&
          o.reference != r.reference) {
        continue;
      }
      if (!_compatible(o.merchantRaw, r.merchantRaw)) continue;
      if (!_compatible(o.last4, r.last4)) continue;
      final a = o.timestamp;
      final b = r.timestamp;
      if (a == null || b == null) continue;
      if (a.difference(b).abs() > window) continue;
      return j;
    }
    return null;
  }

  static bool _compatible(String? a, String? b) =>
      a == null || b == null || a == b;
}
