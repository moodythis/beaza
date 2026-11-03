/// End-to-end encryption for Beaza sync.
///
/// Keys are made and used only on the phone. The server receives a
/// [KeyBundle] (the data key, locked) and [EncryptedRecord]s, and cannot
/// read either. See README.md for the design and what the server can and
/// cannot learn.
library beaza_crypto;

export 'src/account_keys.dart';
export 'src/bytes.dart' show fromBase64, randomId, toBase64;
export 'src/envelope.dart' show DecryptionFailed;
export 'src/password_keys.dart';
export 'src/record_cipher.dart';
export 'src/recovery_key.dart';
