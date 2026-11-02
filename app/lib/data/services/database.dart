import 'package:drift/drift.dart';

part 'database.g.dart';

/// One counted transaction. Built for sync from the start: a random text id
/// that is the same on every device, a last-changed time, the device that
/// changed it, and a deleted time instead of removing the row (a tombstone),
/// so a deletion can travel to the other phones.
///
/// Never holds raw message text, names, phone numbers, full IBANs or
/// balances. Only last digits of accounts and cards.
@DataClassName('LedgerRow')
class LedgerRows extends Table {
  @override
  String get tableName => 'transactions';

  TextColumn get id => text()();
  // ignore: recursive_getters
  IntColumn get amountFils => integer().check(amountFils.isBiggerThanValue(0))();
  TextColumn get currency => text()();
  TextColumn get type => text().nullable()();
  TextColumn get direction => text()();
  TextColumn get merchantRaw => text().nullable()();
  TextColumn get merchantNorm => text().nullable()();
  TextColumn get category => text().nullable()();
  TextColumn get channel => text().nullable()();
  TextColumn get last4 => text().nullable()();
  TextColumn get counterpartyLast4 => text().nullable()();
  TextColumn get reference => text().nullable()();

  /// UTC, milliseconds since epoch.
  IntColumn get timestampMs => integer()();
  RealColumn get confidence => real().withDefault(const Constant(0.0))();
  TextColumn get templateVersion => text()();

  /// ExtractionFlag names, comma separated.
  TextColumn get flags => text().withDefault(const Constant(''))();

  /// 'message' or 'manual'.
  TextColumn get source => text()();

  /// The user left it out of the totals (FR: exclude a transaction).
  BoolColumn get excluded => boolean().withDefault(const Constant(false))();

  IntColumn get updatedAtMs => integer()();
  IntColumn get deletedAtMs => integer().nullable()();
  TextColumn get deviceId => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// The single settings record (id is always 1).
@DataClassName('SettingsRow')
class SettingsRows extends Table {
  @override
  String get tableName => 'settings';

  // ignore: recursive_getters
  IntColumn get id => integer().check(id.equals(1))();
  // ignore: recursive_getters
  IntColumn get dailyLimitFils =>
      integer().check(dailyLimitFils.isBiggerOrEqualValue(0))();
  // ignore: recursive_getters
  IntColumn get microThresholdFils =>
      integer().check(microThresholdFils.isBiggerThanValue(0))();
  IntColumn get alertCap => integer()();
  IntColumn get microCountForTotal => integer()();
  BoolColumn get rollover => boolean()();
  IntColumn get rolloverCapPercent => integer()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [LedgerRows, SettingsRows])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
