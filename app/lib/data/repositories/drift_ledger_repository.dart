import 'dart:convert';

import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/syncable.dart';
import 'package:beaza/data/services/database.dart';
import 'package:beaza/data/services/key_store.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:crypto/crypto.dart' as hash;
import 'package:drift/drift.dart';

/// The ledger kept in the encrypted database. Deleted rows stay as
/// tombstones (deletedAtMs) so a sync can tell the other phones.
class DriftLedgerRepository extends LedgerRepository implements Syncable {
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

  Future<List<LedgerRow>> _liveRows() => (_db.select(_db.ledgerRows)
        ..where((r) => r.deletedAtMs.isNull() & r.excluded.equals(false))
        ..orderBy([
          (r) => OrderingTerm.asc(r.timestampMs),
          (r) => OrderingTerm.asc(r.id),
        ]))
      .get();

  @override
  Future<List<LedgerEntry>> entries() async {
    final rows = await _liveRows();
    return _reconciler.reconcile(rows.map(_toResult).toList(), _accounts);
  }

  @override
  Future<void> setCategory(
    LedgerEntry entry,
    String category, {
    bool sameShop = true,
  }) async {
    final rows = await _liveRows();
    final i = entry.index;
    if (i < 0 || i >= rows.length) return;
    final row = rows[i];
    // The list may have changed since the screen read it: only change the
    // row the person tapped.
    if (row.amountFils != entry.result.amountFils ||
        row.timestampMs !=
            entry.result.timestamp?.toUtc().millisecondsSinceEpoch) {
      return;
    }
    final key = shopKey(_toResult(row));
    final ids = <String>[
      for (final r in rows)
        if (r.id == row.id ||
            (sameShop && key != null && shopKey(_toResult(r)) == key))
          if (r.category != category || r.id == row.id) r.id,
    ];
    final now = _clock().toUtc().millisecondsSinceEpoch;
    await (_db.update(_db.ledgerRows)..where((r) => r.id.isIn(ids))).write(
      LedgerRowsCompanion(
        category: Value(category),
        updatedAtMs: Value(now),
        deviceId: Value(_deviceId),
        pendingSync: const Value(true),
      ),
    );
    notifyListeners();
  }

  /// The category the person already gave this shop: the newest row of the
  /// shop that has one. A shop's rows share a category unless the person
  /// changed it, so this is their last choice.
  Future<String?> _rememberedCategory(ExtractionResult r) async {
    final key = shopKey(r);
    if (key == null) return null;
    final rows = await (_db.select(_db.ledgerRows)
          ..where((x) => x.deletedAtMs.isNull() & x.category.isNotNull())
          ..orderBy([(x) => OrderingTerm.desc(x.updatedAtMs)]))
        .get();
    for (final x in rows) {
      if (shopKey(_toResult(x)) == key) return x.category;
    }
    return null;
  }

  @override
  Future<void> addManual({
    required int amountFils,
    String? merchant,
    required DateTime at,
    String? category,
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
        category: category ??
            const MerchantNormalizer().normalize(merchant)?.category,
        timestamp: at.toUtc(),
        confidence: 1.0,
        templateVersion: InMemoryLedgerRepository.manualTemplate,
      ),
      source: sourceManual,
    );
  }

  @override
  Future<void> addExtracted(ExtractionResult result,
      {String? messageKey}) async {
    checkCompleteTransaction(result);
    final remembered = await _rememberedCategory(result);
    if (remembered != null && remembered != result.category) {
      result = result.withMerchant(category: remembered);
    }
    return _insert(
      result,
      source: sourceMessage,
      id: messageKey == null ? null : messageId(messageKey, result),
    );
  }

  /// The same message always gives the same id, so reading it again (for
  /// example after the data was cleared and restored from an account) finds
  /// the row that is already there instead of adding a copy.
  static String messageId(String messageKey, ExtractionResult r) {
    final text = [
      'beaza/message/v1',
      messageKey,
      r.amountFils,
      r.timestamp!.toUtc().millisecondsSinceEpoch,
      r.direction.name,
      r.last4 ?? '',
      r.reference ?? '',
    ].join('|');
    return hash.sha256.convert(utf8.encode(text)).toString().substring(0, 32);
  }

  @override
  Future<int> countDuplicates() async => (await _duplicateIds()).length;

  @override
  Future<int> removeDuplicates() async {
    final ids = await _duplicateIds();
    if (ids.isEmpty) return 0;
    final now = _clock().toUtc().millisecondsSinceEpoch;
    await (_db.update(_db.ledgerRows)..where((r) => r.id.isIn(ids))).write(
      LedgerRowsCompanion(
        deletedAtMs: Value(now),
        updatedAtMs: Value(now),
        deviceId: Value(_deviceId),
        pendingSync: const Value(true),
      ),
    );
    notifyListeners();
    return ids.length;
  }

  /// Ids of rows from messages that repeat an earlier row with the same
  /// fields, stored at least [duplicateGap] after it. The earliest stays.
  Future<List<String>> _duplicateIds() async {
    final rows = await (_db.select(_db.ledgerRows)
          ..where((r) =>
              r.source.equals(sourceMessage) & r.deletedAtMs.isNull())
          ..orderBy([
            (r) => OrderingTerm.asc(r.updatedAtMs),
            (r) => OrderingTerm.asc(r.id),
          ]))
        .get();
    final first = <String, int>{};
    final copies = <String>[];
    for (final r in rows) {
      final key = [
        r.amountFils, r.currency, r.type, r.direction, r.merchantRaw,
        r.last4, r.counterpartyLast4, r.reference, r.timestampMs,
        r.templateVersion,
      ].join('|');
      final kept = first[key];
      if (kept == null) {
        first[key] = r.updatedAtMs;
      } else if (r.updatedAtMs - kept >= duplicateGap.inMilliseconds) {
        copies.add(r.id);
      }
    }
    return copies;
  }

  /// The live row a screen's entry stands for, or null when the list has
  /// changed since the screen read it.
  Future<LedgerRow?> _rowOf(LedgerEntry entry) async {
    final rows = await _liveRows();
    final i = entry.index;
    if (i < 0 || i >= rows.length) return null;
    final row = rows[i];
    if (row.amountFils != entry.result.amountFils ||
        row.timestampMs !=
            entry.result.timestamp?.toUtc().millisecondsSinceEpoch) {
      return null;
    }
    return row;
  }

  @override
  Future<void> remove(LedgerEntry entry) async {
    final row = await _rowOf(entry);
    if (row != null) await delete(row.id);
  }

  @override
  Future<void> edit(LedgerEntry entry,
      {required int amountFils, String? merchant}) async {
    if (amountFils <= 0) {
      throw ArgumentError.value(amountFils, 'amountFils', 'must be positive');
    }
    final row = await _rowOf(entry);
    if (row == null) return;
    final now = _clock().toUtc().millisecondsSinceEpoch;
    await (_db.update(_db.ledgerRows)..where((r) => r.id.equals(row.id))).write(
      LedgerRowsCompanion(
        amountFils: Value(amountFils),
        merchantRaw: Value(merchant),
        merchantNorm: const Value(null),
        updatedAtMs: Value(now),
        deviceId: Value(_deviceId),
        pendingSync: const Value(true),
      ),
    );
    notifyListeners();
  }

  /// Marks a transaction as deleted. The row stays as a tombstone.
  Future<void> delete(String id) async {
    final now = _clock().toUtc().millisecondsSinceEpoch;
    await (_db.update(_db.ledgerRows)..where((r) => r.id.equals(id))).write(
      LedgerRowsCompanion(
        deletedAtMs: Value(now),
        updatedAtMs: Value(now),
        deviceId: Value(_deviceId),
        pendingSync: const Value(true),
      ),
    );
    notifyListeners();
  }

  Future<void> _insert(
    ExtractionResult r, {
    required String source,
    String? id,
  }) async {
    final now = _clock().toUtc().millisecondsSinceEpoch;
    await _db.into(_db.ledgerRows).insert(
          mode: InsertMode.insertOrIgnore,
          LedgerRowsCompanion.insert(
            id: id ?? newId(),
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

  // ---- sync ----

  /// What the server sees as the list name. Short on purpose: it is the only
  /// part of a record the server can read.
  static const String syncCollection = 'txn';

  @override
  String get collection => syncCollection;

  @override
  Future<List<SyncItem>> pendingChanges({int limit = 100}) async {
    final rows = await (_db.select(_db.ledgerRows)
          ..where((r) => r.pendingSync.equals(true))
          ..orderBy([(r) => OrderingTerm.asc(r.updatedAtMs)])
          ..limit(limit))
        .get();
    return [
      for (final r in rows)
        SyncItem(id: r.id, updatedAtMs: r.updatedAtMs, fields: _fields(r)),
    ];
  }

  @override
  Future<void> markSynced(String id, int updatedAtMs) =>
      (_db.update(_db.ledgerRows)
            ..where((r) => r.id.equals(id) & r.updatedAtMs.equals(updatedAtMs)))
          .write(const LedgerRowsCompanion(pendingSync: Value(false)));

  @override
  Future<void> markAllPending() => _db
      .update(_db.ledgerRows)
      .write(const LedgerRowsCompanion(pendingSync: Value(true)));

  @override
  Future<int> localCount() async {
    final count = _db.ledgerRows.id.count();
    final query = _db.selectOnly(_db.ledgerRows)
      ..addColumns([count])
      ..where(_db.ledgerRows.deletedAtMs.isNull());
    return (await query.getSingle()).read(count) ?? 0;
  }

  @override
  Future<int> countFromOtherPhones() async {
    final count = _db.ledgerRows.id.count();
    final query = _db.selectOnly(_db.ledgerRows)
      ..addColumns([count])
      ..where(_db.ledgerRows.deviceId.equals(_deviceId).not());
    return (await query.getSingle()).read(count) ?? 0;
  }

  @override
  Future<int> removeFromOtherPhones() async {
    final n = await (_db.delete(_db.ledgerRows)
          ..where((r) => r.deviceId.equals(_deviceId).not()))
        .go();
    if (n > 0) notifyListeners();
    return n;
  }

  @override
  Future<int> applyRemote(List<RemoteItem> items) async {
    var changed = 0;
    await _db.transaction(() async {
      for (final item in items) {
        final LedgerRowsCompanion row;
        try {
          row = _fromFields(item.id, item.fields);
        } on FormatException {
          continue; // Not a version this app understands; leave it.
        }
        final local = await (_db.select(_db.ledgerRows)
              ..where((r) => r.id.equals(item.id)))
            .getSingleOrNull();
        final time = row.updatedAtMs.value;
        final device = row.deviceId.value;
        if (local == null ||
            isNewer(time, device, local.updatedAtMs, local.deviceId)) {
          await _db.into(_db.ledgerRows).insertOnConflictUpdate(row);
          changed++;
        } else if (local.updatedAtMs != time || local.deviceId != device) {
          // This phone has a later version than the server: the server got
          // an older one after ours. Send ours again so all phones agree.
          await (_db.update(_db.ledgerRows)
                ..where((r) => r.id.equals(item.id)))
              .write(const LedgerRowsCompanion(pendingSync: Value(true)));
        }
      }
    });
    if (changed > 0) notifyListeners();
    return changed;
  }

  static Map<String, Object?> _fields(LedgerRow r) => {
        'v': 1,
        'amountFils': r.amountFils,
        'currency': r.currency,
        'type': r.type,
        'direction': r.direction,
        'merchantRaw': r.merchantRaw,
        'merchantNorm': r.merchantNorm,
        'category': r.category,
        'channel': r.channel,
        'last4': r.last4,
        'counterpartyLast4': r.counterpartyLast4,
        'reference': r.reference,
        'timestampMs': r.timestampMs,
        'confidence': r.confidence,
        'templateVersion': r.templateVersion,
        'flags': r.flags,
        'source': r.source,
        'excluded': r.excluded,
        'updatedAtMs': r.updatedAtMs,
        'deletedAtMs': r.deletedAtMs,
        'deviceId': r.deviceId,
      };

  /// A remote version as a row. Throws [FormatException] for anything that
  /// would break the table's rules, so one bad record cannot stop a sync.
  static LedgerRowsCompanion _fromFields(String id, Map<String, Object?> f) {
    if (f['v'] != 1) throw const FormatException('unknown version');
    final amount = intField(f, 'amountFils');
    if (amount <= 0) throw const FormatException('bad amountFils');
    final currency = stringField(f, 'currency');
    if (currency.isEmpty) throw const FormatException('bad currency');
    return LedgerRowsCompanion.insert(
      id: id,
      amountFils: amount,
      currency: currency,
      type: Value(optionalString(f, 'type')),
      direction: stringField(f, 'direction'),
      merchantRaw: Value(optionalString(f, 'merchantRaw')),
      merchantNorm: Value(optionalString(f, 'merchantNorm')),
      category: Value(optionalString(f, 'category')),
      channel: Value(optionalString(f, 'channel')),
      last4: Value(optionalString(f, 'last4')),
      counterpartyLast4: Value(optionalString(f, 'counterpartyLast4')),
      reference: Value(optionalString(f, 'reference')),
      timestampMs: intField(f, 'timestampMs'),
      confidence: Value(doubleField(f, 'confidence')),
      templateVersion: stringField(f, 'templateVersion'),
      flags: Value(stringField(f, 'flags')),
      source: stringField(f, 'source'),
      excluded: Value(boolField(f, 'excluded')),
      updatedAtMs: intField(f, 'updatedAtMs'),
      deletedAtMs: Value(optionalInt(f, 'deletedAtMs')),
      deviceId: stringField(f, 'deviceId'),
      pendingSync: const Value(false),
    );
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
