import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/foundation.dart';

/// Single source of truth for the user's transactions.
///
/// Stores extraction results (never raw message text) and returns the
/// reconciled ledger, so duplicates and transfers between the user's own
/// accounts are resolved the same way everywhere. Notifies listeners when
/// anything changes, so screens recompute the guardrail.
abstract class LedgerRepository extends ChangeNotifier {
  Future<List<LedgerEntry>> entries();

  /// An expense the user typed in (cash or a missed message).
  Future<void> addManual({
    required int amountFils,
    String? merchant,
    required DateTime at,
  });

  /// A transaction found in a bank message. Only extracted fields are kept,
  /// never the message text. Throws for anything not a complete transaction.
  Future<void> addExtracted(ExtractionResult result);
}

/// Shared check for [LedgerRepository.addExtracted].
void checkCompleteTransaction(ExtractionResult r) {
  if (r.status != ExtractionStatus.transaction ||
      (r.amountFils ?? 0) <= 0 ||
      r.currency == null ||
      r.timestamp == null) {
    throw ArgumentError('not a complete transaction');
  }
}

/// Keeps everything in memory, for tests. The app uses the encrypted
/// database (DriftLedgerRepository).
class InMemoryLedgerRepository extends LedgerRepository {
  InMemoryLedgerRepository({
    List<ExtractionResult> initial = const [],
    OwnAccounts? accounts,
    Reconciler reconciler = const Reconciler(),
  })  : _results = [...initial],
        _accounts = accounts ?? OwnAccounts(),
        _reconciler = reconciler;

  final List<ExtractionResult> _results;
  final OwnAccounts _accounts;
  final Reconciler _reconciler;

  /// Marks results the user typed in, instead of a message template.
  static const String manualTemplate = 'manual';

  @override
  Future<List<LedgerEntry>> entries() async =>
      _reconciler.reconcile(List.unmodifiable(_results), _accounts);

  @override
  Future<void> addManual({
    required int amountFils,
    String? merchant,
    required DateTime at,
  }) async {
    if (amountFils <= 0) {
      throw ArgumentError.value(amountFils, 'amountFils', 'must be positive');
    }
    _results.add(ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: amountFils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantRaw: merchant,
      timestamp: at.toUtc(),
      confidence: 1.0,
      templateVersion: manualTemplate,
    ));
    notifyListeners();
  }

  @override
  Future<void> addExtracted(ExtractionResult result) async {
    checkCompleteTransaction(result);
    _results.add(result);
    notifyListeners();
  }
}
