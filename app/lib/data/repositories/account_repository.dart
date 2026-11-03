import 'package:beaza/data/services/account_store.dart';
import 'package:beaza/data/services/google_auth.dart';
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

  /// Google's sign-in did not work (not set up for this app, or no Google
  /// account on the phone).
  google,
  server,
}

class AccountFailure implements Exception {
  const AccountFailure(this.problem, {this.retryAfterSeconds, this.code});

  final AccountProblem problem;
  final int? retryAfterSeconds;

  /// The server's error code, shown with unexpected errors so they can be
  /// reported from a screenshot (for example `bad_bundle`).
  final String? code;

  @override
  String toString() => 'AccountFailure(${problem.name})';
}

/// A Google account picked on this phone, and whether it already has a
/// Beaza account (then log in with the recovery key; otherwise sign up).
class GoogleStart {
  const GoogleStart({
    required this.idToken,
    required this.email,
    required this.exists,
    this.hasPassword = false,
  });

  final String idToken;
  final String email;
  final bool exists;

  /// The account has a password (made with email and password, or linked):
  /// log in with it instead of the recovery key.
  final bool hasPassword;
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

  // ---- Sign in with Google ----
  // Google proves who the person is; the recovery key is the only lock on
  // the data, so logging in on a phone needs it too.

  /// True when this phone can show Google's account picker.
  bool get googleAvailable => false;

  /// Shows Google's account picker and asks the server whether that Google
  /// account has a Beaza account. Null when the person closed the picker.
  Future<GoogleStart?> startGoogle() =>
      throw UnsupportedError('Google sign-in');

  /// Creates a Google account and returns the recovery key, to be shown once.
  Future<RecoveryKey> signUpWithGoogle(GoogleStart start, Consent consent) =>
      throw UnsupportedError('Google sign-in');

  /// Logs in with Google plus the password or the recovery key, whichever
  /// is given. An email account with the same Gmail is linked to Google.
  Future<void> logInWithGoogle(GoogleStart start,
          {String? password, String? recoveryKey}) =>
      throw UnsupportedError('Google sign-in');

  /// Deletes a Google account after Google confirms it is the same
  /// account. False when the person closed Google's picker.
  Future<bool> deleteGoogleAccount() =>
      throw UnsupportedError('Google sign-in');
}

String normalizeEmail(String email) => email.trim().toLowerCase();

/// Runs a server call and turns its errors into [AccountFailure]s.
Future<T> guardApi<T>(Future<T> Function() call) async {
  try {
    return await call();
  } on ApiException catch (e) {
    throw AccountFailure(problemForCode(e.code),
        retryAfterSeconds: e.retryAfterSeconds, code: e.code);
  } on NetworkException {
    throw const AccountFailure(AccountProblem.network);
  }
}

AccountProblem problemForCode(String code) => switch (code) {
      'invalid_credentials' => AccountProblem.wrongCredentials,
      'email_taken' => AccountProblem.emailTaken,
      'rate_limited' => AccountProblem.rateLimited,
      'documents_outdated' => AccountProblem.documentsOutdated,
      'unauthorized' => AccountProblem.sessionExpired,
      'google_disabled' ||
      'invalid_id_token' ||
      'google_unavailable' =>
        AccountProblem.google,
      _ => AccountProblem.server,
    };

class RemoteAccountRepository extends AccountRepository {
  RemoteAccountRepository({
    required SyncApi api,
    required AccountStore store,
    KeyWork work = const KeyWork(),
    GoogleAuth? google,
  })  : _api = api,
        _store = store,
        _work = work,
        _google = google;

  final SyncApi _api;
  final AccountStore _store;
  final KeyWork _work;
  final GoogleAuth? _google;

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
  bool get googleAvailable => _google?.available ?? false;

  @override
  Future<GoogleStart?> startGoogle() async {
    final idToken = await _googleToken();
    if (idToken == null) return null;
    final found = await _guard(() => _api.googleCheck(idToken));
    return GoogleStart(
      idToken: idToken,
      email: found.email,
      exists: found.exists,
      hasPassword: found.password,
    );
  }

  @override
  Future<RecoveryKey> signUpWithGoogle(
      GoogleStart start, Consent consent) async {
    if (!consent.adult) throw ArgumentError('consent must include age');
    final created = await _work.createGoogleAccount();
    final token = await _guard(() => _api.googleRegister(
          idToken: start.idToken,
          recoveryAuthKey: created.recoveryAuthKey,
          bundle: created.bundle,
          consent: consent,
        ));
    await _save(SavedAccount(
        email: start.email,
        token: token,
        dataKey: created.dataKey,
        google: true));
    return created.recoveryKey;
  }

  @override
  Future<void> logInWithGoogle(GoogleStart start,
      {String? password, String? recoveryKey}) async {
    final DataKey dataKey;
    final String token;
    if (password != null) {
      final keys = await _passwordKeys(start.email, password);
      final session = await _guard(
          () => _api.googleLogin(start.idToken, authKey: keys.authKey));
      try {
        dataKey = await session.bundle.openWithPassword(keys);
      } on DecryptionFailed {
        throw const AccountFailure(AccountProblem.server);
      }
      token = session.token;
    } else {
      final key = _parseRecoveryKey(recoveryKey ?? '');
      final ({String token, KeyBundle bundle}) session;
      try {
        session = await _guard(() async => _api.googleLogin(start.idToken,
            recoveryAuthKey: await key.authKey()));
      } on AccountFailure catch (e) {
        if (e.problem == AccountProblem.wrongCredentials) {
          throw const AccountFailure(AccountProblem.wrongRecoveryKey);
        }
        rethrow;
      }
      try {
        dataKey = await session.bundle.openWithRecoveryKey(key);
      } on DecryptionFailed {
        throw const AccountFailure(AccountProblem.wrongRecoveryKey);
      }
      token = session.token;
    }
    await _save(SavedAccount(
        email: start.email, token: token, dataKey: dataKey, google: true));
  }

  @override
  Future<bool> deleteGoogleAccount() async {
    final account = _requireAccount();
    final idToken = await _googleToken();
    if (idToken == null) return false;
    await _guard(() => _api.deleteGoogleAccount(account.token, idToken));
    await _forget();
    return true;
  }

  Future<String?> _googleToken() async {
    final google = _google;
    if (google == null || !google.available) {
      throw const AccountFailure(AccountProblem.google);
    }
    try {
      return await google.idToken();
    } on Exception catch (e) {
      throw AccountFailure(AccountProblem.google,
          code: e is GoogleAuthException ? e.message : null);
    }
  }

  static RecoveryKey _parseRecoveryKey(String text) {
    try {
      return RecoveryKey.parse(text);
    } on RecoveryKeyException catch (e) {
      throw AccountFailure(e.problem == RecoveryKeyProblem.typo
          ? AccountProblem.recoveryKeyTypo
          : AccountProblem.recoveryKeyFormat);
    }
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

  static Future<T> _guard<T>(Future<T> Function() call) => guardApi(call);
}
