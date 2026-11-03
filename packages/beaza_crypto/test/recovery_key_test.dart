import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:test/test.dart';

final fixed = RecoveryKey.fromSecret(List.generate(18, (i) => i * 13 % 256));

RecoveryKeyProblem? problemOf(String typed) {
  try {
    RecoveryKey.parse(typed);
    return null;
  } on RecoveryKeyException catch (e) {
    return e.problem;
  }
}

void main() {
  test('shown as 8 groups of 4 characters from the alphabet', () {
    final text = RecoveryKey.generate().format();
    expect(text, matches(RegExp(r'^([0-9A-HJKMNP-TV-Z]{4}-){7}[0-9A-HJKMNP-TV-Z]{4}$')));
  });

  test('reading the shown text gives the same key', () {
    final key = RecoveryKey.generate();
    expect(RecoveryKey.parse(key.format()), key);
  });

  test('two new keys differ', () {
    expect(RecoveryKey.generate(), isNot(RecoveryKey.generate()));
  });

  test('forgiving typing: lower case, spaces, no dashes, look-alikes', () {
    final text = fixed.format();
    expect(RecoveryKey.parse(text.toLowerCase()), fixed);
    expect(RecoveryKey.parse(text.replaceAll('-', ' ')), fixed);
    expect(RecoveryKey.parse(text.replaceAll('-', '')), fixed);
    expect(
        RecoveryKey.parse(
            text.replaceAll('0', 'O').replaceAll('1', 'l')),
        fixed);
  });

  test('Arabic-Indic digits are read as digits', () {
    const arabic = '٠١٢٣٤٥٦٧٨٩';
    final text = fixed
        .format()
        .split('')
        .map((c) => '0123456789'.contains(c) ? arabic['0123456789'.indexOf(c)] : c)
        .join();
    expect(RecoveryKey.parse(text), fixed);
  });

  test('any single wrong character is caught as a typo', () {
    final chars = fixed.format().replaceAll('-', '');
    for (var i = 0; i < chars.length; i++) {
      final current = RecoveryKey.alphabet.indexOf(chars[i]);
      final other = RecoveryKey.alphabet[(current + 7) % 32];
      final typed = chars.replaceRange(i, i + 1, other);
      expect(problemOf(typed), RecoveryKeyProblem.typo, reason: 'position $i');
    }
  });

  test('too short, too long, or a letter outside the alphabet', () {
    final chars = fixed.format().replaceAll('-', '');
    expect(problemOf(chars.substring(1)), RecoveryKeyProblem.length);
    expect(problemOf('${chars}A'), RecoveryKeyProblem.length);
    expect(problemOf(''), RecoveryKeyProblem.length);
    expect(problemOf(chars.replaceRange(0, 1, 'U')),
        RecoveryKeyProblem.character);
  });

  test('never printed, so it cannot leak into logs', () {
    expect(fixed.toString(), 'RecoveryKey(hidden)');
    expect('$fixed'.contains(fixed.format().substring(0, 4)), false);
  });
}
