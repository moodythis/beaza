import 'dart:async';
import 'dart:convert';

import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/syncable.dart';
import 'package:beaza/data/services/account_store.dart';
import 'package:beaza/data/services/sync_api.dart';
import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:crypto/crypto.dart' as hash;
import 'package:flutter/foundation.dart';

/// Keeps the phones of one account in step through the sync server.
///
/// A sync first pulls what other phones changed (and applies it, last
/// writer wins), then pushes this phone's pending changes. Every record is
/// encrypted on the phone with the account's data key before it is sent;
/// the server only ever sees a list name, a random id and an opaque blob.
class SyncRepository extends ChangeNotifier {
  SyncRepository({
    required SyncApi api,
    required AccountRepository account,
    required List<Syncable> collections,
    required PreferencesStore preferences,
    DateTime Function()? clock,
    this.debounce = const Duration(seconds: 2),
  })  : _api = api,
        _account = account,
        _collections = collections,
        _prefs = preferences,
        _clock = clock ?? DateTime.now;

  final SyncApi _api;
  final AccountRepository _account;
  final List<Syncable> _collections;
  final PreferencesStore _prefs;
  final DateTime Function() _clock;

  /// Wait after a local change before syncing, so a burst of changes goes
  /// in one request.
  final Duration debounce;

  // Kept in the (encrypted) app database.
  static const String accountPref = 'sync.account';
  static const String sincePref = 'sync.since';
  static const String lastPref = 'sync.last';

  static const int pushBatch = 100;

  /// Upper bound of push rounds per list in one sync; the rest goes next time.
  static const int maxRounds = 50;

  bool _syncing = false;
  bool get syncing => _syncing;

  DateTime? _lastSynced;

  /// When the last sync finished without a problem.
  DateTime? get lastSynced => _lastSynced;

  AccountFailure? _failure;

  /// Why the last sync failed, or null.
  AccountFailure? get failure => _failure;

  int _unreadable = 0;

  /// Records skipped because they could not be opened with this account's
  /// key (for example damaged on the way). Shown nowhere yet; for tests.
  int get unreadable => _unreadable;

  Future<bool>? _running;
  bool _again = false;
  bool _applying = false;
  Timer? _timer;
  String? _lastToken;
  bool _disposed = false;

  RecordCipher? _cipher;
  DataKey? _cipherKey;

  Future<void> load() async {
    final ms = int.tryParse(await _prefs.read(lastPref) ?? '');
    _lastSynced =
        ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    _lastToken = _account.current?.token;
    _notify();
  }

  /// Call when the account changes. Syncs right after a log-in or sign-up.
  void accountChanged() {
    final token = _account.current?.token;
    if (token == _lastToken) return;
    _lastToken = token;
    _failure = null;
    if (token != null) unawaited(syncNow());
    _notify();
  }

  /// Call when something changed on this phone. Syncs a moment later.
  /// Changes made by the sync itself are ignored.
  void localChanged() {
    if (_applying || !_account.signedIn || _disposed) return;
    _timer?.cancel();
    _timer = Timer(debounce, () => unawaited(syncNow()));
  }

  /// Syncs now. If a sync is already running, one more runs after it (so
  /// nothing changed meanwhile is left behind). Returns true on success.
  ///
  /// [pushOnly] sends this phone's changes without fetching others', for
  /// the short background run after a bank message.
  Future<bool> syncNow({bool pushOnly = false}) {
    final running = _running;
    if (running != null) {
      _again = true;
      return running;
    }
    // Set before the sync starts, so a call made while it starts joins it.
    final done = Completer<bool>();
    _running = done.future;
    _loop(pushOnly).then(done.complete, onError: done.completeError);
    return done.future;
  }

  Future<bool> _loop(bool pushOnly) async {
    try {
      var ok = await _syncOnce(pushOnly);
      while (_again && !_disposed) {
        _again = false;
        ok = await _syncOnce(false);
      }
      return ok;
    } finally {
      _running = null;
    }
  }

  Future<bool> _syncOnce(bool pushOnly) async {
    final account = _account.current;
    if (account == null) return false;
    _syncing = true;
    _failure = null;
    _notify();
    try {
      final cipher = await _cipherFor(account.dataKey);
      var since = await _startingPoint(account);
      if (!pushOnly) since = await _pull(account.token, cipher, since);
      await _push(account.token, cipher, since);
      if (_account.current?.token != account.token) return false;
      _lastSynced = _clock().toUtc();
      await _prefs.write(
          lastPref, _lastSynced!.millisecondsSinceEpoch.toString());
      return true;
    } on AccountFailure catch (e) {
      _failure = e;
      return false;
    } finally {
      _syncing = false;
      _notify();
    }
  }

  /// The change number to pull after. After logging in to an account (or a
  /// different one), starts from zero and marks everything to be sent, so
  /// both sides end up with all rows.
  Future<int> _startingPoint(SavedAccount account) async {
    final marker = sessionMarker(account.token);
    if (await _prefs.read(accountPref) != marker) {
      for (final c in _collections) {
        await c.markAllPending();
      }
      await _prefs.write(sincePref, '0');
      await _prefs.write(accountPref, marker);
      return 0;
    }
    return int.tryParse(await _prefs.read(sincePref) ?? '') ?? 0;
  }

  Future<int> _pull(String token, RecordCipher cipher, int since) async {
    while (true) {
      final page = await guardApi(() => _api.pullRecords(token, since));
      final byList = <String, List<RemoteItem>>{};
      for (final record in page.records) {
        final Map<String, Object?> fields;
        try {
          fields = await cipher.decrypt(record);
        } on Object {
          _unreadable++;
          continue;
        }
        (byList[record.collection] ??= []).add(RemoteItem(record.id, fields));
      }
      _applying = true;
      try {
        for (final c in _collections) {
          final items = byList[c.collection];
          if (items != null) await c.applyRemote(items);
        }
      } finally {
        _applying = false;
      }
      since = page.nextSince;
      await _prefs.write(sincePref, '$since');
      if (!page.more || page.records.isEmpty) return since;
    }
  }

  Future<void> _push(String token, RecordCipher cipher, int since) async {
    for (final c in _collections) {
      for (var round = 0; round < maxRounds; round++) {
        final items = await c.pendingChanges(limit: pushBatch);
        if (items.isEmpty) break;
        final records = [
          for (final item in items)
            await cipher.encrypt(
                collection: c.collection, id: item.id, fields: item.fields),
        ];
        final seq = await guardApi(() => _api.pushRecords(token, records));
        for (final item in items) {
          await c.markSynced(item.id, item.updatedAtMs);
        }
        // Nobody else wrote in between: the records after `since` are the
        // ones just sent, so there is no need to download them back.
        if (seq == since + records.length) {
          since = seq;
          await _prefs.write(sincePref, '$since');
        }
      }
    }
  }

  Future<RecordCipher> _cipherFor(DataKey key) async {
    if (_cipher == null || _cipherKey != key) {
      _cipher = await RecordCipher.create(key);
      _cipherKey = key;
    }
    return _cipher!;
  }

  /// Tells sessions apart without keeping the token itself in the database.
  static String sessionMarker(String token) =>
      hash.sha256.convert(utf8.encode('beaza/sync/$token')).toString();

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
