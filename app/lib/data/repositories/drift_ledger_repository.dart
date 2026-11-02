import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/services/database.dart';
import 'package:beaza/data/services/key_store.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:drift/drift.dart';

/// The ledger kept in the encrypted database. Deleted rows stay as
/// tombstones (deletedAtMs) so a later sync can tell the other phones.
class DriftLedgerRepository extends LedgerRepository {
  DriftLedgerRepository(
    this._db, {
    required String deviceId,
    DateTime Function()? clock,
    OwnAccounts? accounts,
    Reconciler reconciler = const Reconciler(),
  })  : _deviceId = deviceId,
        _clock = clock ?? DateTime.now,
        _accounts = accounts ?? OwnAccounts(),
        _reconciler = reconciler;

  final AppDatabase _db;
  final String _deviceId;
  final DateTime Function() _clock;
  final OwnAccounts _accounts;
  final Reconciler _reconciler;

  static const String sourceManual = 'manual';
  static const String sourceMessage = 'message';

  @override
  Future<List<LedgerEntry>> entries() async {
    final rows = await (_db.select(_db.ledgerRows)
          ..where((r) => r.deletedAtMs.isNull() & r.excluded.equals(false))
          ..orderBy([
            (r) => OrderingTerm.asc(r.timestampMs),
            (r) => OrderingTerm.asc(r.id),
          ]))
        .get();
    return _reconciler.reconcile(rows.map(_toResult).toList(), _accounts);
  }

  @override
  Future<void> addManual({
    required int amountFils,
    String? merchant,
    required DateTime at,
  }) {
    if (amountFils <= 0) {
      throw ArgumentError.value(amountFils, 'amountFils', 'must be positive');
    }
    return _insert(
      ExtractionResult(
        status: ExtractionStatus.transaction,
        amountFils: amountFils,
        currency: 'BHD',
        type: TxnType.purchase,
        direction: TxDirection.outgoing,
        merchantRaw: merchant,
        timestamp: at.toUtc(),
        confidence: 1.0,
        templateVersion: InMemoryLedgerRepository.manualTemplate,
      ),
      source: sourceManual,
    );
  }

  /// Stores a transaction found in a bank message. Only the extracted
  /// fields are kept, never the message text.
  Future<void> addExtracted(ExtractionResult result) {
    if (result.status != ExtractionStatus.transaction ||
        (result.amountFils ?? 0) <= 0 ||
        result.currency == null ||
        result.timestamp == null) {
      throw ArgumentError('not a complete transaction');
    }
    return _insert(result, source: sourceMessage);
  }

  /// Marks a transaction as deleted. The row stays as a tombstone.
  Future<void> delete(String id) async {
    final now = _clock().toUtc().millisecondsSinceEpoch;
    await (_db.update(_db.ledgerRows)..where((r) => r.id.equals(id))).write(
      LedgerRowsCompanion(
        deletedAtMs: Value(now),
        updatedAtMs: Value(now),
        deviceId: Value(_deviceId),
      ),
    );
    notifyListeners();
  }

  Future<void> _insert(ExtractionResult r, {required String source}) async {
    final now = _clock().toUtc().millisecondsSinceEpoch;
    await _db.into(_db.ledgerRows).insert(
          LedgerRowsCompanion.insert(
            id: newId(),
            amountFils: r.amountFils!,
            currency: r.currency!,
            type: Value(r.type?.name),
            direction: r.direction.name,
            merchantRaw: Value(r.merchantRaw),
            merchantNorm: Value(r.merchantNorm),
            category: Value(r.category),
            channel: Value(r.channel?.name),
            last4: Value(r.last4),
            counterpartyLast4: Value(r.counterpartyLast4),
            reference: Value(r.reference),
            timestampMs: r.timestamp!.toUtc().millisecondsSinceEpoch,
            confidence: Value(r.confidence),
            templateVersion: r.templateVersion,
            flags: Value(r.flags.map((f) => f.name).join(',')),
            source: source,
            updatedAtMs: now,
            deviceId: _deviceId,
          ),
        );
    notifyListeners();
  }

  static ExtractionResult _toResult(LedgerRow r) => ExtractionResult(
        status: ExtractionStatus.transaction,
        amountFils: r.amountFils,
        currency: r.currency,
        type: _byName(TxnType.values, r.type),
        direction: _byName(TxDirection.values, r.direction) ??
            TxDirection.unknown,
        merchantRaw: r.merchantRaw,
        merchantNorm: r.merchantNorm,
        category: r.category,
        channel: _byName(Channel.values, r.channel),
        last4: r.last4,
        counterpartyLast4: r.counterpartyLast4,
        reference: r.reference,
        timestamp:
            DateTime.fromMillisecondsSinceEpoch(r.timestampMs, isUtc: true),
        confidence: r.confidence,
        templateVersion: r.templateVersion,
        flags: [
          for (final name in r.flags.split(','))
            if (_byName(ExtractionFlag.values, name) case final f?) f,
        ],
      );

  /// Unknown names (for example from a newer app version) become null
  /// instead of crashing the screen.
  static T? _byName<T extends Enum>(List<T> values, String? name) {
    if (name == null) return null;
    for (final v in values) {
      if (v.name == name) return v;
    }
    return null;
  }
}
