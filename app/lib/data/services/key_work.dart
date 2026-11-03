import 'dart:async';
import 'dart:isolate';

import 'package:beaza_crypto/beaza_crypto.dart';

/// The slow part of the encryption (Argon2id, about a second on a phone)
/// runs in a background isolate so the screen does not freeze.
class KeyWork {
  const KeyWork({
    this.params = KdfParams.recommended,
    this.minimum = KdfParams.minimum,
    this.inBackground = true,
  });

  /// Cheap settings and no isolate, for tests only.
  const KeyWork.forTests(KdfParams cheap)
      : params = cheap,
        minimum = cheap,
        inBackground = false;

  final KdfParams params;
  final KdfParams minimum;
  final bool inBackground;

  Future<T> _run<T>(FutureOr<T> Function() work) =>
      inBackground ? Isolate.run(work) : Future.sync(work);

  Future<NewAccount> createAccount(String password) {
    final p = params, m = minimum;
    return _run(
        () => AccountKeys.create(password: password, params: p, minimum: m));
  }

  /// Keys for logging in, with the salt and setting the server returned.
  /// Throws [WeakKdfParams] when the server asks for a weak setting.
  Future<PasswordKeys> derive(
    String password,
    List<int> salt,
    KdfParams serverParams,
  ) {
    final m = minimum;
    // Checked here as well, so the refusal never depends on an isolate.
    if (!serverParams.isAtLeast(m)) {
      return Future.error(WeakKdfParams(serverParams));
    }
    return _run(() => PasswordKeys.derive(
          password: password,
          salt: salt,
          params: serverParams,
          minimum: m,
        ));
  }

  Future<PasswordChange> setPassword(
    KeyBundle bundle,
    DataKey dataKey,
    String password,
  ) {
    final p = params, m = minimum;
    return _run(() => AccountKeys.setPassword(bundle, dataKey, password,
        params: p, minimum: m));
  }
}
