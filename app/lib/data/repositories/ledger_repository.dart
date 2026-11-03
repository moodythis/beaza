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
  ///
  /// [messageKey] names the message it came from (for example `sms:123`).
  /// Adding the same message again (after the phone's data was cleared and
  /// restored from an account, say) changes nothing, and a transaction the
  /// person deleted does not come back.
  Future<void> addExtracted(ExtractionResult result, {String? messageKey});

  /// Puts a transaction in another category (one of kCategories).
  ///
  /// With [sameShop] (the default) every other transaction from the same
  /// shop changes too, and later ones from that shop start in this category:
  /// the app remembers the choice. Each changed row syncs like any edit.
  Future<void> setCategory(
    LedgerEntry entry,
    String category, {
    bool sameShop = true,
  });

  /// How many transactions read from messages are copies of an earlier one
  /// (same fields, made at least [duplicateGap] later). Copies like this
  /// came from reading the same bank message twice.
  Future<int> countDuplicates() async => 0;

  /// Removes those copies (they stay as deleted entries so other phones get
  /// the removal). Returns how many.
  Future<int> removeDuplicates() async => 0;
}

/// What identifies a shop for remembering its category: the clean name, or
/// the printed one, in capitals. Null when the transaction names no shop.
String? shopKey(ExtractionResult r) {
  final name = (r.merchantNorm ?? r.merchantRaw)?.trim();
  if (name == null || name.isEmpty) return null;
  return name.toUpperCase();
}

/// Two identical transactions made by reading messages are treated as one
/// message read twice only if they were stored this far apart. Two real
/// identical purchases in the same minute arrive seconds apart.
const Duration duplicateGap = Duration(minutes: 5);

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
  final Set<String> _messageKeys = {};

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
      category: const MerchantNormalizer().normalize(merchant)?.category,
      timestamp: at.toUtc(),
      confidence: 1.0,
      templateVersion: manualTemplate,
    ));
    notifyListeners();
  }

  @override
  Future<void> setCategory(
    LedgerEntry entry,
    String category, {
    bool sameShop = true,
  }) async {
    final i = entry.index;
    if (i < 0 || i >= _results.length) return;
    final key = shopKey(_results[i]);
    for (var j = 0; j < _results.length; j++) {
      if (j == i || (sameShop && key != null && shopKey(_results[j]) == key)) {
        _results[j] = _results[j].withMerchant(category: category);
      }
    }
    notifyListeners();
  }

  /// The category the person already gave this shop (the newest one added).
  String? _rememberedCategory(ExtractionResult r) {
    final key = shopKey(r);
    if (key == null) return null;
    for (final other in _results.reversed) {
      if (shopKey(other) == key && other.category != null) {
        return other.category;
      }
    }
    return null;
  }

  @override
  Future<void> addExtracted(ExtractionResult result,
      {String? messageKey}) async {
    checkCompleteTransaction(result);
    if (messageKey != null && !_messageKeys.add(messageKey)) return;
    final remembered = _rememberedCategory(result);
    _results.add(remembered == null || remembered == result.category
        ? result
        : result.withMerchant(category: remembered));
    notifyListeners();
  }
}
