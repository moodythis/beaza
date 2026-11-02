import 'dart:io';

import 'package:beaza/data/repositories/alert_log_store.dart';
import 'package:beaza/data/repositories/drift_ledger_repository.dart';
import 'package:beaza/data/repositories/drift_settings_repository.dart';
import 'package:beaza/data/repositories/seen_message_store.dart';
import 'package:beaza/data/services/database.dart';
import 'package:beaza/data/services/database_opener.dart';
import 'package:beaza/data/services/key_store.dart';
import 'package:beaza/data/services/storage.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter_test/flutter_test.dart';

DateTime bh(int day, int hour) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

final String goodKey = 'ab' * 32;

void main() {
  late AppDatabase db;
  late DriftLedgerRepository ledger;
  late DriftSettingsRepository settings;

  setUp(() {
    db = openMemoryDatabase();
    ledger = DriftLedgerRepository(db,
        deviceId: 'device1', clock: () => bh(2, 12));
    settings = DriftSettingsRepository(db, clock: () => bh(2, 12));
  });

  tearDown(() => db.close());

  group('ledger', () {
    test('a manual expense is stored and read back as spending', () async {
      await ledger.addManual(amountFils: 2500, merchant: 'Bakery', at: bh(2, 9));
      final es = await ledger.entries();
      expect(es, hasLength(1));
      expect(es.single.role, EntryRole.spending);
      expect(es.single.result.amountFils, 2500);
      expect(es.single.result.merchantRaw, 'Bakery');
      expect(es.single.result.currency, 'BHD');
      expect(es.single.result.timestamp, bh(2, 9));
      expect(es.single.result.timestamp!.isUtc, isTrue);
    });

    test('rows carry sync fields', () async {
      await ledger.addManual(amountFils: 1000, at: bh(2, 9));
      final row = await db.select(db.ledgerRows).getSingle();
      expect(row.id, hasLength(32));
      expect(row.deviceId, 'device1');
      expect(row.source, 'manual');
      expect(row.deletedAtMs, isNull);
      expect(row.updatedAtMs, bh(2, 12).millisecondsSinceEpoch);
    });

    test('ids are unique', () async {
      await ledger.addManual(amountFils: 1000, at: bh(2, 9));
      await ledger.addManual(amountFils: 1000, at: bh(2, 9));
      final ids = (await db.select(db.ledgerRows).get()).map((r) => r.id);
      expect(ids.toSet(), hasLength(2));
    });

    test('entries come back oldest first', () async {
      await ledger.addManual(amountFils: 3000, at: bh(2, 11));
      await ledger.addManual(amountFils: 1000, at: bh(2, 8));
      final es = await ledger.entries();
      expect(es.map((e) => e.result.amountFils), [1000, 3000]);
    });

    test('delete leaves a tombstone and hides the row', () async {
      await ledger.addManual(amountFils: 1000, at: bh(2, 9));
      final id = (await db.select(db.ledgerRows).getSingle()).id;
      await ledger.delete(id);
      expect(await ledger.entries(), isEmpty);
      final row = await db.select(db.ledgerRows).getSingle();
      expect(row.deletedAtMs, bh(2, 12).millisecondsSinceEpoch);
    });

    test('an extracted transaction keeps its fields but no message text',
        () async {
      await ledger.addExtracted(ExtractionResult(
        status: ExtractionStatus.transaction,
        amountFils: 4200,
        currency: 'BHD',
        type: TxnType.transferOut,
        direction: TxDirection.outgoing,
        channel: Channel.transfer,
        last4: '1234',
        counterpartyLast4: '9876',
        reference: 'BP123',
        timestamp: bh(2, 10),
        confidence: 0.9,
        templateVersion: 'x@1',
        flags: const [ExtractionFlag.timestampFromReceipt],
      ));
      final r = (await ledger.entries()).single.result;
      expect(r.type, TxnType.transferOut);
      expect(r.channel, Channel.transfer);
      expect(r.counterpartyLast4, '9876');
      expect(r.reference, 'BP123');
      expect(r.flags, [ExtractionFlag.timestampFromReceipt]);
      expect(db.ledgerRows.$columns.map((c) => c.name),
          isNot(contains('raw_text')));
    });

    test('incomplete results are refused', () {
      expect(
          () => ledger.addExtracted(
              const ExtractionResult(status: ExtractionStatus.unparsed)),
          throwsArgumentError);
    });

    test('duplicates are still resolved by the reconciler', () async {
      for (var i = 0; i < 2; i++) {
        await ledger.addExtracted(ExtractionResult(
          status: ExtractionStatus.transaction,
          amountFils: 4200,
          currency: 'BHD',
          direction: TxDirection.outgoing,
          reference: 'REF1',
          timestamp: bh(2, 10),
          templateVersion: 'x@1',
        ));
      }
      final es = await ledger.entries();
      expect(es.map((e) => e.role), [EntryRole.spending, EntryRole.duplicate]);
    });

    test('listeners hear about changes', () async {
      var calls = 0;
      ledger.addListener(() => calls++);
      await ledger.addManual(amountFils: 1000, at: bh(2, 9));
      expect(calls, 1);
    });

    test('the database refuses a non-positive amount', () async {
      expect(
        () => db.into(db.ledgerRows).insert(LedgerRowsCompanion.insert(
              id: 'x',
              amountFils: 0,
              currency: 'BHD',
              direction: 'outgoing',
              timestampMs: 1,
              templateVersion: 't',
              source: 'manual',
              updatedAtMs: 1,
              deviceId: 'd',
            )),
        throwsA(anything),
      );
    });
  });

  group('settings', () {
    test('defaults to no limit', () async {
      expect((await settings.load()).dailyLimitFils, 0);
    });

    test('round trip, and a second save replaces the first', () async {
      await settings.save(const GuardrailSettings(
          dailyLimitFils: 8000, rollover: true, alertCap: 3));
      await settings.save((await settings.load()).copyWith(dailyLimitFils: 9000));
      final s = await settings.load();
      expect(s.dailyLimitFils, 9000);
      expect(s.rollover, isTrue);
      expect(s.alertCap, 3);
      expect(await db.select(db.settingsRows).get(), hasLength(1));
    });
  });

  group('encryption', () {
    late Directory dir;

    setUp(() => dir = Directory.systemTemp.createTempSync('beaza_test_'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('the file is unreadable without the key', () async {
      final file = File('${dir.path}/enc.db');
      final enc = openEncryptedDatabase(file, goodKey, background: false);
      await DriftLedgerRepository(enc, deviceId: 'd')
          .addManual(amountFils: 1000, merchant: 'SecretCafe', at: bh(2, 9));
      await enc.close();

      final bytes = file.readAsBytesSync();
      expect(String.fromCharCodes(bytes.take(15)), isNot('SQLite format 3'));
      expect(String.fromCharCodes(bytes), isNot(contains('SecretCafe')));

      final again = openEncryptedDatabase(file, goodKey, background: false);
      final row = await again.select(again.ledgerRows).getSingle();
      expect(row.merchantRaw, 'SecretCafe');
      await again.close();
    });

    test('a wrong key throws instead of returning data', () async {
      final file = File('${dir.path}/enc.db');
      final enc = openEncryptedDatabase(file, goodKey, background: false);
      await DriftLedgerRepository(enc, deviceId: 'd')
          .addManual(amountFils: 1000, at: bh(2, 9));
      await enc.close();

      final wrong = openEncryptedDatabase(file, 'cd' * 32, background: false);
      await expectLater(wrong.select(wrong.ledgerRows).get(), throwsA(anything));
    });

    test('a key that is not 64 hex digits is refused', () {
      expect(
          () => openEncryptedDatabase(File('${dir.path}/x.db'), "x' OR '1"),
          throwsArgumentError);
    });

    test('first run creates a key, later runs reuse it', () async {
      final keys = MemoryKeyStore();
      final s1 = await openStorage(directory: dir, keys: keys, background: false);
      await s1.ledger.addManual(amountFils: 1500, at: bh(2, 9));
      await s1.database.close();

      final s2 = await openStorage(directory: dir, keys: keys, background: false);
      expect(await s2.ledger.entries(), hasLength(1));
      await s2.database.close();
    });

    test('a lost key does not create a fresh database over old data', () async {
      final s1 = await openStorage(
          directory: dir, keys: MemoryKeyStore(), background: false);
      await s1.ledger.addManual(amountFils: 1500, at: bh(2, 9)); // creates the file
      await s1.database.close();

      await expectLater(
        openStorage(directory: dir, keys: MemoryKeyStore(), background: false),
        throwsStateError,
      );
    });
  });

  group('seen messages and migration', () {
    test('seen ids are remembered and pruned', () async {
      final store = DriftSeenMessageStore(db);
      await store.add('sms:1', bh(1, 9));
      await store.add('sms:2', bh(2, 9));
      expect(await store.contains('sms:1'), isTrue);
      await store.pruneBefore(bh(2, 0));
      expect(await store.contains('sms:1'), isFalse);
      expect(await store.contains('sms:2'), isTrue);
    });

    test('a version 1 database gains the new tables and keeps its data',
        () async {
      final dir = Directory.systemTemp.createTempSync('beaza_mig_');
      addTearDown(() => dir.deleteSync(recursive: true));
      final file = File('${dir.path}/m.db');

      final v2 = openEncryptedDatabase(file, goodKey, background: false);
      await DriftLedgerRepository(v2, deviceId: 'd')
          .addManual(amountFils: 700, at: bh(2, 9));
      // Turn it back into what version 1 looked like on the phone.
      await v2.customStatement('DROP TABLE seen_messages');
      await v2.customStatement('DROP TABLE alert_days');
      await v2.customStatement('PRAGMA user_version = 1');
      await v2.close();

      final upgraded = openEncryptedDatabase(file, goodKey, background: false);
      final store = DriftSeenMessageStore(upgraded);
      await store.add('sms:9', bh(2, 9));
      expect(await store.contains('sms:9'), isTrue);
      expect(await upgraded.select(upgraded.alertDayRows).get(), isEmpty);
      expect(await upgraded.select(upgraded.ledgerRows).get(), hasLength(1));
      await upgraded.close();
    });
  });

  group('alert log', () {
    test('saved per day and read back', () async {
      final store = DriftAlertLogStore(db);
      const day = Day(2026, 11, 3);
      expect(await store.load(day), isNull);
      await store.save(const AlertLog(
          day: day, sent: 2, highestLevel: AlertLevel.level2,
          microTotalShown: true));
      final log = (await store.load(day))!;
      expect(log.sent, 2);
      expect(log.highestLevel, AlertLevel.level2);
      expect(log.microTotalShown, isTrue);
      expect(await store.load(const Day(2026, 11, 4)), isNull);
    });
  });

  group('key store helpers', () {
    test('random hex has the right length and alphabet', () {
      final k = randomHex(32);
      expect(k, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(randomHex(32), isNot(k));
      expect(newId(), hasLength(32));
    });

    test('the device id stays the same', () async {
      final keys = MemoryKeyStore();
      expect(await keys.deviceId(), await keys.deviceId());
    });
  });
}
