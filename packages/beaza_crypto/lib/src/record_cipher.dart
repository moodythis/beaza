import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import 'account_keys.dart';
import 'bytes.dart';
import 'envelope.dart';

/// One record as the server sees it: a random id, which list it belongs to,
/// and an opaque blob. The amount, merchant, time and every other field are
/// inside the blob.
class EncryptedRecord {
  const EncryptedRecord({
    required this.collection,
    required this.id,
    required this.blob,
  });

  factory EncryptedRecord.fromJson(Map<String, Object?> json) =>
      EncryptedRecord(
        collection: json['collection'] as String,
        id: json['id'] as String,
        blob: fromBase64(json['blob'] as String),
      );

  final String collection;
  final String id;
  final Uint8List blob;

  Map<String, Object?> toJson() =>
      {'collection': collection, 'id': id, 'blob': toBase64(blob)};
}

/// Encrypts and decrypts records with the record key.
///
/// Each record is bound to its collection and id: the server cannot move a
/// record to another id or list, or replace one with another, without the
/// phone noticing. The plaintext is padded to a multiple of [block] bytes so
/// the blob size does not reveal, for example, how many digits an amount
/// has or how long a merchant name is.
class RecordCipher {
  RecordCipher._(this._key);

  static Future<RecordCipher> create(DataKey dataKey) async =>
      RecordCipher._(await dataKey.recordKey());

  static const int block = 64;
  static final RegExp _collectionPattern = RegExp(r'^[a-z][a-z_]{0,31}$');
  static final RegExp _idPattern = RegExp(r'^[A-Za-z0-9_-]{1,64}$');

  final SecretKey _key;

  Future<EncryptedRecord> encrypt({
    required String collection,
    required String id,
    required Map<String, Object?> fields,
  }) async {
    _check(collection, id);
    final plain = pad(utf8.encode(jsonEncode(fields)));
    return EncryptedRecord(
      collection: collection,
      id: id,
      blob: await Envelope.seal(plain, _key, _context(collection, id)),
    );
  }

  Future<Map<String, Object?>> decrypt(EncryptedRecord record) async {
    _check(record.collection, record.id);
    final plain = await Envelope.open(
        record.blob, _key, _context(record.collection, record.id));
    return jsonDecode(utf8.decode(unpad(plain))) as Map<String, Object?>;
  }

  static String _context(String collection, String id) =>
      'beaza/v1/record/$collection/$id';

  static void _check(String collection, String id) {
    if (!_collectionPattern.hasMatch(collection)) {
      throw ArgumentError.value(collection, 'collection');
    }
    if (!_idPattern.hasMatch(id)) throw ArgumentError.value(id, 'id');
  }

  /// ISO/IEC 7816-4 padding: a 0x80 byte, then zeros up to a multiple of
  /// [block]. Always adds at least one byte, so it can always be removed.
  static Uint8List pad(List<int> data) {
    final length = (data.length ~/ block + 1) * block;
    return Uint8List(length)
      ..setAll(0, data)
      ..[data.length] = 0x80;
  }

  static Uint8List unpad(List<int> padded) {
    var i = padded.length - 1;
    while (i >= 0 && padded[i] == 0) {
      i--;
    }
    if (i < 0 || padded[i] != 0x80) throw const DecryptionFailed();
    return Uint8List.fromList(padded.sublist(0, i));
  }
}
