import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:test/test.dart';

/// Cheap Argon2id setting so tests run fast. Real accounts use
/// [KdfParams.recommended]; one test below measures it.
const fast = KdfParams(memoryKiB: 64, iterations: 1, parallelism: 1);
final salt = List.generate(16, (i) => i);

Future<PasswordKeys> derive(String password, {List<int>? withSalt}) =>
    PasswordKeys.derive(
      password: password,
      salt: withSalt ?? salt,
      params: fast,
      minimum: fast,
    );

void main() {
  test('same password and salt give the same keys (another phone can log in)',
      () async {
    final a = await derive('my password');
    final b = await derive('my password');
    expect(a.authKey, b.authKey);
    expect(await a.wrapKey.extractBytes(), await b.wrapKey.extractBytes());
  });

  test('a different password or salt gives different keys', () async {
    final a = await derive('my password');
    expect((await derive('my passwore')).authKey, isNot(a.authKey));
    expect(
        (await derive('my password', withSalt: List.filled(16, 9))).authKey,
        isNot(a.authKey));
  });

  test('the key sent to the server is not the key that opens the data',
      () async {
    final k = await derive('my password');
    expect(k.authKey, hasLength(32));
    expect(await k.wrapKey.extractBytes(), isNot(k.authKey));
  });

  test('Arabic passwords work', () async {
    final a = await derive('كلمة سر طويلة');
    final b = await derive('كلمة سر طويله');
    expect(a.authKey, isNot(b.authKey));
  });

  test('a weak setting from the server is refused', () {
    expect(
      () => PasswordKeys.derive(
          password: 'my password', salt: salt, params: fast),
      throwsA(isA<WeakKdfParams>()),
    );
    expect(
      () => PasswordKeys.derive(
        password: 'my password',
        salt: salt,
        params: const KdfParams(memoryKiB: 19456, iterations: 1, parallelism: 1),
      ),
      throwsA(isA<WeakKdfParams>()),
    );
  });

  test('empty password or short salt is refused', () {
    expect(() => derive(''), throwsArgumentError);
    expect(() => derive('my password', withSalt: [1, 2, 3]),
        throwsArgumentError);
  });

  test('the setting survives a trip through JSON', () {
    final json = KdfParams.recommended.toJson();
    expect(json, {'alg': 'argon2id', 'm': 19456, 't': 2, 'p': 1});
    expect(KdfParams.fromJson(json), KdfParams.recommended);
  });

  test('the real setting (19 MiB, 2 passes) takes a moment, not minutes',
      () async {
    final watch = Stopwatch()..start();
    final keys = await PasswordKeys.derive(
      password: 'my password',
      salt: salt,
      params: KdfParams.recommended,
    );
    watch.stop();
    // Printed for the report: each password guess costs an attacker this much.
    // ignore: avoid_print
    print('Argon2id with ${KdfParams.recommended}: '
        '${watch.elapsedMilliseconds} ms on the CI machine');
    expect(keys.authKey, hasLength(32));
  }, timeout: const Timeout(Duration(minutes: 3)));

  test('never printed', () async {
    expect((await derive('my password')).toString(), 'PasswordKeys(hidden)');
  });
}
