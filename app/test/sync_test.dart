import 'dart:convert';

import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/repositories/drift_ledger_repository.dart';
import 'package:beaza/data/repositories/drift_settings_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/sync_repository.dart';
import 'package:beaza/data/repositories/syncable.dart';
import 'package:beaza/data/services/account_store.dart';
import 'package:beaza/data/services/database.dart';
import 'package:beaza/data/services/database_opener.dart';
import 'package:beaza/data/services/sync_api.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/account/views/account_view.dart';
import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// Behaves like the records calls of server/src/app.ts: every stored or
/// replaced record gets the account's next change number (seq), and a pull
/// returns the latest version of each record after a number.
class FakeRecordServer {
  /// Session token -> account.
  final tokens = <String, String>{};
  final seq = <String, int>{};
  final records = <String, Map<String, Map<String, Object?>>>{};

  bool offline = false;
  final pulled = <int>[];
  final pushed = <int>[];

  http.Client get client => MockClient(_handle);

  void addAccount(String user, String token) {
    tokens[token] = user;
    seq[user] ??= 0;
    records[user] ??= {};
  }

  List<Map<String, Object?>> stored(String user) =>
      records[user]!.values.toList();

  Future<http.Response> _handle(http.Request r) async {
    if (offline) throw http.ClientException('offline');
    final token = r.headers['authorization']?.substring('Bearer '.length);
    final user = tokens[token];
    if (user == null) return _json(401, {'error': 'unauthorized'});
    final mine = records[user]!;
    switch ('${r.method} ${r.url.path}') {
      case 'POST /v1/records':
        final list = (jsonDecode(r.body) as Map)['records'] as List;
        pushed.add(list.length);
        for (final item in list.cast<Map<String, Object?>>()) {
          seq[user] = seq[user]! + 1;
          mine['${item['collection']}/${item['id']}'] = {...item, 'seq': seq[user]};
        }
        return _json(200, {'seq': seq[user]});
      case 'GET /v1/records':
        final since = int.parse(r.url.queryParameters['since']!);
        final limit = int.parse(r.url.queryParameters['limit']!);
        final after = mine.values.where((x) => (x['seq']! as int) > since).toList()
          ..sort((a, b) => (a['seq']! as int).compareTo(b['seq']! as int));
        final page = after.take(limit).toList();
        pulled.add(page.length);
        return _json(200, {
          'records': page,
          'nextSince': page.isEmpty ? since : page.last['seq'],
          'more': after.length > limit,
          'latest': seq[user],
        });
    }
    return _json(404, {'error': 'not_found'});
  }

  static http.Response _json(int status, Map<String, Object?> body) =>
      http.Response(jsonEncode(body), status,
          headers: {'content-type': 'application/json'});
}

/// An account that is already signed in; no password work.
class FixedAccount extends AccountRepository {
  FixedAccount(this._current);

  SavedAccount? _current;

  @override
  SavedAccount? get current => _current;

  set current(SavedAccount? value) {
    _current = value;
    notifyListeners();
  }

  @override
  Future<void> load() async {}
  @override
  Future<RecoveryKey> signUp({
    required String email,
    required String password,
    required Consent consent,
  }) =>
      throw UnimplementedError();
  @override
  Future<void> logIn({required String email, required String password}) =>
      throw UnimplementedError();
  @override
  Future<void> recover({
    required String email,
    required String recoveryKey,
    required String newPassword,
  }) =>
      throw UnimplementedError();
  @override
  Future<AccountInfo> info() => throw UnimplementedError();
  @override
  Future<void> deleteAccount(String password) => throw UnimplementedError();
  @override
  Future<void> logOut() async => current = null;
}

DateTime now = DateTime.utc(2026, 11, 3, 10);

final key1 = DataKey.fromBytes(List.generate(32, (i) => i));
final key2 = DataKey.fromBytes(List.generate(32, (i) => 100 + i));

SavedAccount account(String token, [DataKey? key]) =>
    SavedAccount(email: 'me@example.com', token: token, dataKey: key ?? key1);

/// One phone: its own database, the shared fake server, one account.
class Phone {
  /// [owner]: this phone's data already belongs to the account (the
  /// question about adding it was answered before).
  Phone(String deviceId, FakeRecordServer server, SavedAccount saved,
      {bool owner = true})
      : db = openMemoryDatabase() {
    if (owner) {
      prefs.values[SyncRepository.ownerPref] =
          SyncRepository.ownerMarker(saved.dataKey);
    }
    ledger = DriftLedgerRepository(db, deviceId: deviceId, clock: () => now);
    settings = DriftSettingsRepository(db, clock: () => now);
    account = FixedAccount(saved);
    sync = SyncRepository(
      api: SyncApi(client: server.client, baseUrl: 'https://sync.test'),
      account: account,
      collections: [ledger, settings],
      preferences: prefs,
      clock: () => now,
      debounce: const Duration(milliseconds: 10),
    );
  }

  final AppDatabase db;
  final prefs = MemoryPreferencesStore();
  late final DriftLedgerRepository ledger;
  late final DriftSettingsRepository settings;
  late final FixedAccount account;
  late final SyncRepository sync;

  Future<List<int>> amounts() async =>
      [for (final e in await ledger.entries()) e.result.amountFils!];

  Future<int> pending() async =>
      (await ledger.pendingChanges()).length +
      (await settings.pendingChanges()).length;

  Future<void> close() async {
    sync.dispose();
    await db.close();
  }
}

void main() {
  late FakeRecordServer server;
  late Phone a;
  late Phone b;

  setUp(() {
    now = DateTime.utc(2026, 11, 3, 10);
    server = FakeRecordServer()
      ..addAccount('user1', 'tokenA')
      ..addAccount('user1', 'tokenB');
    a = Phone('deviceA', server, account('tokenA'));
    b = Phone('deviceB', server, account('tokenB'));
  });

  tearDown(() async {
    await a.close();
    await b.close();
  });

  test('a transaction made on one phone appears on the other', () async {
    await a.ledger.addManual(amountFils: 2500, merchant: 'Bakery', at: now);
    expect(await a.sync.syncNow(), isTrue);
    expect(await a.pending(), 0);

    expect(await b.sync.syncNow(), isTrue);
    final entries = await b.ledger.entries();
    expect(entries.single.result.amountFils, 2500);
    expect(entries.single.result.merchantRaw, 'Bakery');
    expect(b.sync.lastSynced, now);
  });

  test('the server sees only a list name, a random id and an opaque blob',
      () async {
    await a.ledger.addManual(amountFils: 2500, merchant: 'Bakery', at: now);
    await a.settings.save(const GuardrailSettings(dailyLimitFils: 7000));
    await a.sync.syncNow();

    final stored = server.stored('user1');
    expect(stored.map((r) => r['collection']).toSet(), {'txn', 'settings'});
    for (final r in stored) {
      final blob = base64Url.decode(base64Url.normalize(r['blob']! as String));
      final text = latin1.decode(blob);
      expect(text, isNot(contains('Bakery')));
      expect(text, isNot(contains('2500')));
      expect(text, isNot(contains('7000')));
      expect(blob.length % 64, (1 + 24 + 16) % 64, reason: 'padded');
    }
  });

  test('the daily limit set on one phone applies on the other', () async {
    await a.settings.save(const GuardrailSettings(dailyLimitFils: 7000));
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect((await b.settings.load()).dailyLimitFils, 7000);
  });

  test('a deletion travels to the other phone', () async {
    await a.ledger.addManual(amountFils: 900, at: now);
    await a.sync.syncNow();
    await b.sync.syncNow();
    expect(await b.amounts(), [900]);

    now = now.add(const Duration(minutes: 1));
    final id = (await a.db.select(a.db.ledgerRows).getSingle()).id;
    await b.ledger.delete(id);
    await b.sync.syncNow();
    await a.sync.syncNow();
    expect(await a.amounts(), isEmpty);
    final row = await a.db.select(a.db.ledgerRows).getSingle();
    expect(row.deletedAtMs, isNotNull, reason: 'kept as a tombstone');
  });

  test('a server that lost changes gets everything again from the phone',
      () async {
    await a.ledger.addManual(amountFils: 2500, merchant: 'Bakery', at: now);
    await a.settings.save(const GuardrailSettings(dailyLimitFils: 7000));
    expect(await a.sync.syncNow(), isTrue);
    expect(server.stored('user1'), hasLength(2));

    // Restored from an empty copy: no records, change counter back to 0.
    server.records['user1']!.clear();
    server.seq['user1'] = 0;

    expect(await a.sync.syncNow(), isTrue);
    expect(server.stored('user1'), hasLength(2));
    expect(await a.pending(), 0);

    expect(await b.sync.syncNow(), isTrue);
    expect(await b.amounts(), [2500]);
    expect((await b.settings.load()).dailyLimitFils, 7000);
  });

  test('both phones end with the later change, even if the older one '
      'reached the server last', () async {
    await a.settings.save(const GuardrailSettings(dailyLimitFils: 5000));
    now = now.add(const Duration(minutes: 5));
    await b.settings.save(const GuardrailSettings(dailyLimitFils: 7000));

    await b.sync.syncNow();
    // A sends its older limit without looking (the short background run).
    await a.sync.syncNow(pushOnly: true);
    expect(server.stored('user1').single['collection'], 'settings');

    await b.sync.syncNow(); // sees the older one and sends its own again
    await a.sync.syncNow();
    expect((await a.settings.load()).dailyLimitFils, 7000);
    expect((await b.settings.load()).dailyLimitFils, 7000);
  });

  test('same change time: both phones pick the same version', () async {
    await a.ledger.addManual(amountFils: 100, at: now);
    await a.sync.syncNow();
    await b.sync.syncNow();
    final id = (await a.db.select(a.db.ledgerRows).getSingle()).id;

    // Both delete at the same millisecond; deviceB > deviceA wins.
    now = now.add(const Duration(minutes: 1));
    await a.ledger.delete(id);
    await b.ledger.delete(id);
    for (var i = 0; i < 2; i++) {
      await a.sync.syncNow();
      await b.sync.syncNow();
    }
    final rowA = await a.db.select(a.db.ledgerRows).getSingle();
    final rowB = await b.db.select(b.db.ledgerRows).getSingle();
    expect(rowA.deviceId, 'deviceB');
    expect(rowB.deviceId, 'deviceB');
  });

  test('a phone does not download its own changes back', () async {
    await a.ledger.addManual(amountFils: 100, at: now);
    await a.ledger.addManual(amountFils: 200, at: now);
    await a.sync.syncNow();
    server.pulled.clear();
    await a.sync.syncNow();
    expect(server.pulled, [0]);
  });

  test('many changes go in batches of 100', () async {
    for (var i = 1; i <= 230; i++) {
      await a.ledger.addManual(amountFils: i, at: now);
    }
    await a.sync.syncNow();
    expect(server.pushed, [100, 100, 30]);
    await b.sync.syncNow();
    expect((await b.amounts()).length, 230);
  });

  test('offline: nothing is lost, the next sync sends it', () async {
    await a.ledger.addManual(amountFils: 300, at: now);
    server.offline = true;
    expect(await a.sync.syncNow(), isFalse);
    expect(a.sync.failure!.problem, AccountProblem.network);
    expect(await a.pending(), 1);

    server.offline = false;
    expect(await a.sync.syncNow(), isTrue);
    expect(a.sync.failure, isNull);
    await b.sync.syncNow();
    expect(await b.amounts(), [300]);
  });

  test('an ended session is reported, not hidden', () async {
    server.tokens.remove('tokenA');
    expect(await a.sync.syncNow(), isFalse);
    expect(a.sync.failure!.problem, AccountProblem.sessionExpired);
  });

  group('signing in to an account this phone never synced with', () {
    test('asks first, and sends or fetches nothing until the answer',
        () async {
      await a.ledger.addManual(amountFils: 400, at: now);
      await a.sync.syncNow();

      server.addAccount('user2', 'tokenC');
      server.addAccount('user2', 'tokenD');
      final other = Phone('deviceO', server, account('tokenD', key2));
      await other.ledger.addManual(amountFils: 999, at: now);
      await other.sync.syncNow();
      server.pulled.clear();

      a.account.current = account('tokenC', key2);
      expect(await a.sync.syncNow(), isFalse);
      expect(a.sync.mergeCount, 1);
      expect(server.stored('user2'), hasLength(1), reason: 'only theirs');
      expect(server.pulled, isEmpty, reason: 'nothing fetched either');
      expect(await a.amounts(), [400]);

      // Later triggers (a local change, the background run) wait as well.
      expect(await a.sync.syncNow(pushOnly: true), isFalse);
      expect(server.stored('user2'), hasLength(1));

      expect(await a.sync.approveMerge(), isTrue);
      expect(a.sync.mergeCount, isNull);
      expect(server.stored('user2'), hasLength(2));
      expect((await a.amounts())..sort(), [400, 999]);
      await other.close();
    });

    test('logging out instead leaves the account untouched', () async {
      await a.ledger.addManual(amountFils: 400, at: now);
      server.addAccount('user2', 'tokenC');
      a.account
        ..addListener(a.sync.accountChanged)
        ..current = account('tokenC', key2);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(a.sync.mergeCount, 1);

      await a.account.logOut();
      expect(a.sync.mergeCount, isNull);
      expect(server.stored('user2'), isEmpty);
    });

    test('a phone with no data joins without a question', () async {
      final fresh =
          Phone('deviceF', server, account('tokenB'), owner: false);
      await a.ledger.addManual(amountFils: 100, at: now);
      await a.sync.syncNow();
      expect(await fresh.sync.syncNow(), isTrue);
      expect(fresh.sync.mergeCount, isNull);
      expect(await fresh.amounts(), [100]);
      await fresh.close();
    });

    test('a phone with data asks even on its first account', () async {
      final used = Phone('deviceU', server, account('tokenB'), owner: false);
      await used.ledger.addManual(amountFils: 100, at: now);
      await used.ledger.addManual(amountFils: 200, at: now);
      expect(await used.sync.syncNow(), isFalse);
      expect(used.sync.mergeCount, 2);
      await used.close();
    });

    test('a phone that already synced this session before the question '
        'existed is not asked', () async {
      final old = Phone('deviceP', server, account('tokenB'), owner: false);
      await old.ledger.addManual(amountFils: 100, at: now);
      old.prefs.values[SyncRepository.accountPref] =
          SyncRepository.sessionMarker('tokenB');
      expect(await old.sync.syncNow(), isTrue);
      expect(old.sync.mergeCount, isNull);
      await old.close();
    });

    test('the same account in a new session is not asked again', () async {
      await a.ledger.addManual(amountFils: 100, at: now);
      await a.sync.syncNow();
      server.addAccount('user1', 'tokenA2');
      a.account.current = account('tokenA2');
      expect(await a.sync.syncNow(), isTrue);
      expect(a.sync.mergeCount, isNull);
    });
  });

  test('removing transactions from other phones keeps this phone\'s own',
      () async {
    await a.ledger.addManual(amountFils: 100, at: now);
    await a.sync.syncNow();
    await b.ledger.addManual(amountFils: 200, at: now);
    await b.sync.syncNow();
    expect((await b.amounts())..sort(), [100, 200]);

    await b.account.logOut();
    expect(await b.sync.countFromOtherPhones(), 1);
    expect(await b.sync.removeFromOtherPhones(), 1);
    expect(await b.amounts(), [200]);
    expect(await b.sync.countFromOtherPhones(), 0);
  });

  test('removing is refused while signed in', () async {
    await expectLater(a.sync.removeFromOtherPhones(), throwsStateError);
  });

  test('a record locked with another key is skipped, the rest syncs',
      () async {
    final other = await RecordCipher.create(key2);
    final bad = await other.encrypt(
        collection: 'txn', id: 'x' * 32, fields: {'v': 1});
    server.records['user1']!['txn/${'x' * 32}'] = {...bad.toJson(), 'seq': 1};
    server.seq['user1'] = 1;
    await a.ledger.addManual(amountFils: 500, at: now);
    await a.sync.syncNow();

    expect(await b.sync.syncNow(), isTrue);
    expect(b.sync.unreadable, 1);
    expect(await b.amounts(), [500]);
  });

  test('a record this app version cannot use is skipped', () async {
    final changed = await a.ledger.applyRemote([
      const RemoteItem('a1', {'v': 1, 'amountFils': 0}),
      const RemoteItem('a2', {'v': 2}),
    ]);
    expect(changed, 0);
    expect(await a.amounts(), isEmpty);
  });

  test('a local change syncs by itself shortly after', () async {
    a.ledger.addListener(a.sync.localChanged);
    await a.ledger.addManual(amountFils: 600, at: now);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await b.sync.syncNow();
    expect(await b.amounts(), [600]);
  });

  test('changes that came from the sync do not start another sync',
      () async {
    await a.ledger.addManual(amountFils: 700, at: now);
    await a.sync.syncNow();
    b.ledger.addListener(b.sync.localChanged);
    await b.sync.syncNow();
    server.pulled.clear();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(server.pulled, isEmpty);
  });

  test('calls while a sync runs join it', () async {
    await a.ledger.addManual(amountFils: 800, at: now);
    final first = a.sync.syncNow();
    final second = a.sync.syncNow();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(server.pushed, [1]);
  });

  testWidgets('the account screen shows the sync state and a button',
      (tester) async {
    final phone = await tester.runAsync(
        () async => Phone('deviceW', server, account('tokenA')));
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: SyncSection(sync: phone!.sync)),
    ));
    expect(find.text('Not synced yet'), findsOneWidget);
    expect(find.byKey(const Key('syncNowButton')), findsOneWidget);

    await tester.runAsync(() => phone.sync.syncNow());
    await tester.pump();
    expect(find.textContaining('Last synced'), findsOneWidget);

    server.offline = true;
    await tester.runAsync(() => phone.sync.syncNow());
    await tester.pump();
    expect(find.textContaining('did not finish'), findsOneWidget);
    await tester.runAsync(phone.close);
  });

  testWidgets('the question about adding this phone\'s data is shown',
      (tester) async {
    final phone = (await tester.runAsync(() async {
      final p = Phone('deviceQ', server, account('tokenA'), owner: false);
      await p.ledger.addManual(amountFils: 100, at: now);
      await p.sync.syncNow();
      return p;
    }))!;
    var loggedOut = false;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SyncSection(sync: phone.sync, onLogOut: () => loggedOut = true),
      ),
    ));
    expect(find.byKey(const Key('mergeCard')), findsOneWidget);
    expect(find.textContaining('1 transaction that is not in this account'),
        findsOneWidget);
    expect(find.byKey(const Key('syncNowButton')), findsNothing);
    await tester.tap(find.byKey(const Key('mergeLogOut')));
    expect(loggedOut, isTrue);

    await tester.runAsync(() => phone.sync.approveMerge());
    await tester.pump();
    expect(find.byKey(const Key('mergeCard')), findsNothing);
    expect(find.textContaining('Last synced'), findsOneWidget);
    await tester.runAsync(phone.close);
  });
}
