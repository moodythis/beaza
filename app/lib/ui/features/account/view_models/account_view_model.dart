import 'package:beaza/data/repositories/account_repository.dart';
import 'package:beaza/data/services/sync_api.dart';
import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:flutter/foundation.dart';

/// Runs one account action at a time for a screen and keeps its outcome, so
/// the screen can show a progress bar or the reason it failed.
class AccountViewModel extends ChangeNotifier {
  AccountViewModel(this.repository);

  final AccountRepository repository;

  bool _busy = false;
  bool get busy => _busy;

  AccountFailure? _failure;
  AccountFailure? get failure => _failure;

  AccountInfo? _info;

  /// What the server holds about the account, once loaded.
  AccountInfo? get info => _info;

  bool _disposed = false;

  Future<RecoveryKey?> signUp({
    required String email,
    required String password,
    required Consent consent,
  }) =>
      _run(() => repository.signUp(
          email: email, password: password, consent: consent));

  Future<bool> logIn({required String email, required String password}) =>
      _ok(() => repository.logIn(email: email, password: password));

  Future<bool> recover({
    required String email,
    required String recoveryKey,
    required String newPassword,
  }) =>
      _ok(() => repository.recover(
          email: email, recoveryKey: recoveryKey, newPassword: newPassword));

  /// Google's account picker, then whether that account exists. Null when
  /// cancelled or failed ([failure] says why).
  Future<GoogleStart?> startGoogle() =>
      _run<GoogleStart?>(repository.startGoogle);

  Future<RecoveryKey?> signUpWithGoogle(GoogleStart start, Consent consent) =>
      _run(() => repository.signUpWithGoogle(start, consent));

  Future<bool> logInWithGoogle(GoogleStart start,
          {String? password, String? recoveryKey}) =>
      _ok(() => repository.logInWithGoogle(start,
          password: password, recoveryKey: recoveryKey));

  Future<bool> deleteGoogleAccount() async {
    final done = await _run(repository.deleteGoogleAccount) ?? false;
    if (done) _info = null;
    return done;
  }

  Future<void> loadInfo() async {
    _info = await _run(repository.info);
    _notify();
  }

  Future<bool> deleteAccount(String password) async {
    final ok = await _ok(() => repository.deleteAccount(password));
    if (ok) _info = null;
    return ok;
  }

  Future<void> logOut() async {
    await _ok(repository.logOut);
    _info = null;
    _notify();
  }

  /// Forgets the last failure when a form opens, so an old error from
  /// another screen is not shown. Called from initState, while widgets are
  /// being built, so it does not notify: the form reads the cleared state
  /// when it builds, and the screens behind it do not show sign-in errors.
  void forgetFailure() => _failure = null;

  Future<bool> _ok(Future<void> Function() action) async =>
      await _run(() async {
        await action();
        return true;
      }) ??
      false;

  Future<T?> _run<T>(Future<T> Function() action) async {
    if (_busy) return null;
    _busy = true;
    _failure = null;
    _notify();
    try {
      return await action();
    } on AccountFailure catch (e) {
      _failure = e;
      return null;
    } on Exception {
      _failure = const AccountFailure(AccountProblem.server);
      return null;
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
