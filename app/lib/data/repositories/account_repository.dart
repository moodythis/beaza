import 'package:beaza/data/services/account_store.dart';
import 'package:beaza/data/services/key_work.dart';
import 'package:beaza/data/services/sync_api.dart';
import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:flutter/foundation.dart';

/// Why an account action did not work. Each has its own message on screen.
enum AccountProblem {
  wrongCredentials,
  emailTaken,
  rateLimited,
  network,

  /// The server asked for a cheap Argon2id setting; the phone refused and
  /// sent nothing derived from the password.
  weakServerSettings,
  recoveryKeyTypo,
  recoveryKeyFormat,
  wrongRecoveryKey,

  /// The privacy notice or terms changed; this app is out of date.
  documentsOutdated,
  sessionExpired,
  server,
}

class AccountFailure implements Exception {
  const AccountFailure(this.problem, {this.retryAfterSeconds});

  final AccountProblem problem;
  final int? retryAfterSeconds;

  @override
  String toString() => 'AccountFailure(${problem.name})';
}

/// The sync account on this phone. Without an account nothing leaves the
/// phone; with one, only encrypted data and key proofs are sent.
abstract class AccountRepository extends ChangeNotifier {
  SavedAccount? get current;
  bool get signedIn => current != null;

  Future<void> load();

  /// Creates the account and returns the recovery key, to be shown once.
  Future<RecoveryKey> signUp({
    required String email,
    required String password,
    required Consent consent,
  });

  Future<void> logIn({required String email, required String password});

  /// Forgot the password: proves the recovery key, opens the data key with
  /// it, and sets [newPassword].
  Future<void> recover({
    required String email,
    required String recoveryKey,
    required String newPassword,
  });

  /// What the server holds about this account (right of access).
  Future<AccountInfo> info();

  /// Deletes the account and all synced data on the server (right to
  /// erasure; also withdraws consent). Data on this phone stays.
  Future<void> deleteAccount(String password);

  /// Ends the session. Works offline: the phone forgets the account even if
  /// the server cannot be told.
  Future<void> logOut();
}

String normalizeEmail(String email) => email.trim().toLowerCase();

class RemoteAccountRepository extends AccountRepository {
  RemoteAccountRepository({
    required SyncApi api,
    required AccountStore store,
    KeyWork work = const KeyWork(),
  })  : _api = api,
        _store = store,
        _work = work;

  final SyncApi _api;
  final AccountStore _store;
  final KeyWork _work;

  SavedAccount? _current;

  @override
  SavedAccount? get current => _current;

  @override
  Future<void> load() async {
    _current = await _store.read();
    notifyListeners();
  }

  @override
  Future<RecoveryKey> signUp({
    required String email,
    required String password,
    required Consent consent,
  }) async {
    if (!consent.adult) throw ArgumentError('consent must include age');
    email = normalizeEmail(email);
    final created = await _work.createAccount(password);
    final token = await _guard(() => _api.register(
          email: email,
          authKey: created.authKey!,
          recoveryAuthKey: created.recoveryAuthKey,
          bundle: created.bundle,
          consent: consent,
        ));
    await _save(SavedAccount(
        email: email, token: token, dataKey: created.dataKey));
    return created.recoveryKey;
  }

  @override
  Future<void> logIn({required String email, required String password}) async {
    email = normalizeEmail(email);
    final keys = await _passwordKeys(email, password);
    final session = await _guard(() => _api.login(email, keys.authKey));
    final DataKey dataKey;
    try {
      dataKey = await session.bundle.openWithPassword(keys);
    } on DecryptionFailed {
      // The server accepted the password but sent a bundle it does not open:
      // it was changed. Do not trust it.
      throw const AccountFailure(AccountProblem.server);
    }
    await _save(
        SavedAccount(email: email, token: session.token, dataKey: dataKey));
  }

  @override
  Future<void> recover({
    required String email,
    required String recoveryKey,
    required String newPassword,
  }) async {
    email = normalizeEmail(email);
    final RecoveryKey key;
    try {
      key = RecoveryKey.parse(recoveryKey);
    } on RecoveryKeyException catch (e) {
      throw AccountFailure(e.problem == RecoveryKeyProblem.typo
          ? AccountProblem.recoveryKeyTypo
          : AccountProblem.recoveryKeyFormat);
    }

    final ({String token, KeyBundle bundle}) session;
    try {
      session = await _guard(() async => _api.recover(email, await key.authKey()));
    } on AccountFailure catch (e) {
      if (e.problem == AccountProblem.wrongCredentials) {
        throw const AccountFailure(AccountProblem.wrongRecoveryKey);
      }
      rethrow;
    }

    final DataKey dataKey;
    try {
      dataKey = await session.bundle.openWithRecoveryKey(key);
    } on DecryptionFailed {
      throw const AccountFailure(AccountProblem.wrongRecoveryKey);
    }
    final change = await _work.setPassword(session.bundle, dataKey, newPassword);
    await _guard(
        () => _api.setPassword(session.token, change.authKey, change.bundle));
    await _save(
        SavedAccount(email: email, token: session.token, dataKey: dataKey));
  }

  @override
  Future<AccountInfo> info() {
    final account = _requireAccount();
    return _guard(() => _api.accountInfo(account.token));
  }

  @override
  Future<void> deleteAccount(String password) async {
    final account = _requireAccount();
    final keys = await _passwordKeys(account.email, password);
    await _guard(() => _api.deleteAccount(account.token, keys.authKey));
    await _forget();
  }

  @override
  Future<void> logOut() async {
    final account = _current;
    if (account == null) return;
    try {
      await _api.logout(account.token);
    } on Exception {
      // Offline or already expired: the phone forgets the session anyway.
    }
    await _forget();
  }

  // ---- helpers ----

  SavedAccount _requireAccount() {
    final account = _current;
    if (account == null) throw StateError('not signed in');
    return account;
  }

  Future<PasswordKeys> _passwordKeys(String email, String password) async {
    final kdf = await _guard(() => _api.kdf(email));
    try {
      return await _work.derive(password, kdf.salt, kdf.params);
    } on WeakKdfParams {
      throw const AccountFailure(AccountProblem.weakServerSettings);
    }
  }

  Future<void> _save(SavedAccount account) async {
    await _store.write(account);
    _current = account;
    notifyListeners();
  }

  Future<void> _forget() async {
    await _store.clear();
    _current = null;
    notifyListeners();
  }

  static Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on ApiException catch (e) {
      throw AccountFailure(_problemFor(e.code),
          retryAfterSeconds: e.retryAfterSeconds);
    } on NetworkException {
      throw const AccountFailure(AccountProblem.network);
    }
  }

  static AccountProblem _problemFor(String code) => switch (code) {
        'invalid_credentials' => AccountProblem.wrongCredentials,
        'email_taken' => AccountProblem.emailTaken,
        'rate_limited' => AccountProblem.rateLimited,
        'documents_outdated' => AccountProblem.documentsOutdated,
        'unauthorized' => AccountProblem.sessionExpired,
        _ => AccountProblem.server,
      };
}
