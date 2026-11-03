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

  /// Changed here and not yet on the sync server. New rows start pending, so
  /// everything made before an account existed is sent once one does.
  /// Added in version 6.
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();

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
  IntColumn get dailyLimitFils => integer().check(dailyLimitFils.isBiggerOrEqualValue(0))(); // ignore: recursive_getters
  IntColumn get microThresholdFils => integer().check(microThresholdFils.isBiggerThanValue(0))(); // ignore: recursive_getters
  IntColumn get alertCap => integer()();
  IntColumn get microCountForTotal => integer()();
  BoolColumn get rollover => boolean()();
  IntColumn get rolloverCapPercent => integer()();
  IntColumn get updatedAtMs => integer()();

  /// See LedgerRows.pendingSync. Added in version 6.
  BoolColumn get pendingSync => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Messages already handled (ids only, never text). Added in version 2.
@DataClassName('SeenMessageRow')
class SeenMessageRows extends Table {
  @override
  String get tableName => 'seen_messages';

  /// For example "sms:123" (the inbox id).
  TextColumn get messageKey => text()();
  IntColumn get seenAtMs => integer()();

  @override
  Set<Column> get primaryKey => {messageKey};
}

/// Alerts already sent on a Bahrain day (FR-5.6 cap). Added in version 3.
@DataClassName('AlertDayRow')
class AlertDayRows extends Table {
  @override
  String get tableName => 'alert_days';

  /// "2026-11-03" in Bahrain time.
  TextColumn get dayKey => text()();
  IntColumn get sent => integer()();

  /// AlertLevel index: 0 normal ... 3 limit reached.
  IntColumn get highestLevel => integer()();
  BoolColumn get microTotalShown => boolean()();
  BoolColumn get limitExceededLogged => boolean()();

  /// The limit the levels were measured against. Added in version 4.
  IntColumn get limitFils => integer().nullable()();
  IntColumn get updatedAtMs => integer()();

  @override
  Set<Column> get primaryKey => {dayKey};
}

/// Small app preferences such as the chosen language. Added in version 5.
@DataClassName('PreferenceRow')
class PreferenceRows extends Table {
  @override
  String get tableName => 'preferences';

  TextColumn get name => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {name};
}

@DriftDatabase(tables: [
  LedgerRows,
  SettingsRows,
  SeenMessageRows,
  AlertDayRows,
  PreferenceRows,
])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.createTable(seenMessageRows);
          if (from < 3) await m.createTable(alertDayRows);
          if (from == 3) {
            await m.addColumn(alertDayRows, alertDayRows.limitFils);
          }
          if (from < 5) await m.createTable(preferenceRows);
          if (from < 6) {
            await m.addColumn(ledgerRows, ledgerRows.pendingSync);
            await m.addColumn(settingsRows, settingsRows.pendingSync);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
