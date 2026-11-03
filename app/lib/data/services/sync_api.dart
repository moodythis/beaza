import 'dart:async';
import 'dart:convert';

import 'package:beaza_crypto/beaza_crypto.dart';
import 'package:http/http.dart' as http;

/// The sync server. Can be changed for a test build with
/// `--dart-define=BEAZA_SERVER=https://...`.
const String kSyncServer = String.fromEnvironment(
  'BEAZA_SERVER',
  defaultValue: 'https://beaza-sync.moodythis.workers.dev',
);

/// The server answered with an error, for example `invalid_credentials`.
class ApiException implements Exception {
  const ApiException(this.status, this.code, {this.retryAfterSeconds});

  final int status;
  final String code;
  final int? retryAfterSeconds;

  @override
  String toString() => 'ApiException($status, $code)';
}

/// The server could not be reached (no internet, timeout, bad answer).
class NetworkException implements Exception {
  const NetworkException();

  @override
  String toString() => 'NetworkException';
}

/// What the person agreed to at sign-up. Each part is a separate tick box:
/// consent to data processing is never bundled with the terms.
class Consent {
  const Consent({
    required this.privacyVersion,
    required this.termsVersion,
    required this.adult,
  });

  final String privacyVersion;
  final String termsVersion;

  /// "I am 18 or older".
  final bool adult;

  Map<String, Object?> toJson() =>
      {'privacy': privacyVersion, 'terms': termsVersion, 'adult': adult};
}

/// What the server holds about the account, in readable form (right of
/// access). The records themselves are encrypted, so only their number is
/// shown.
class AccountInfo {
  const AccountInfo({
    required this.email,
    required this.createdAt,
    required this.privacyVersion,
    required this.termsVersion,
    required this.consentAt,
    required this.encryptedRecords,
    required this.activeSessions,
  });

  factory AccountInfo.fromJson(Map<String, Object?> json) {
    final consent = json['consent'] as Map<String, Object?>;
    DateTime? time(Object? ms) =>
        ms is int ? DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true) : null;
    return AccountInfo(
      email: json['email'] as String,
      createdAt: time(json['createdAt'])!,
      privacyVersion: consent['privacy'] as String?,
      termsVersion: consent['terms'] as String?,
      consentAt: time(consent['at']),
      encryptedRecords: json['encryptedRecords'] as int,
      activeSessions: json['activeSessions'] as int,
    );
  }

  final String email;
  final DateTime createdAt;
  final String? privacyVersion;
  final String? termsVersion;
  final DateTime? consentAt;
  final int encryptedRecords;
  final int activeSessions;
}

/// One page of records from [SyncApi.pullRecords].
class RecordPage {
  const RecordPage({
    required this.records,
    required this.nextSince,
    required this.more,
    this.latest,
  });

  final List<EncryptedRecord> records;

  /// Ask for records after this number next time.
  final int nextSince;

  /// More records are waiting after this page.
  final bool more;

  /// The account's latest change number on the server (null from an older
  /// server). Below what this phone already pulled means the server lost
  /// changes.
  final int? latest;
}

/// Talks to the sync server (server/README.md lists the calls). Everything
/// sent is either a key proof, a locked key bundle or an encrypted record.
class SyncApi {
  SyncApi({
    http.Client? client,
    String baseUrl = kSyncServer,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _base = Uri.parse(baseUrl);

  final http.Client _client;
  final Uri _base;
  final Duration timeout;

  Future<String> register({
    required String email,
    required List<int> authKey,
    required List<int> recoveryAuthKey,
    required KeyBundle bundle,
    required Consent consent,
  }) async {
    final body = await _send('POST', '/v1/register', {
      'email': email,
      'authKey': toBase64(authKey),
      'recoveryAuthKey': toBase64(recoveryAuthKey),
      'bundle': bundle.toJson(),
      'consent': consent.toJson(),
    });
    return body['token'] as String;
  }

  /// Salt and Argon2id setting to use for [email]. The phone checks the
  /// setting itself (PasswordKeys refuses weak ones).
  Future<({List<int> salt, KdfParams params})> kdf(String email) async {
    final body = await _send('POST', '/v1/kdf', {'email': email});
    return (
      salt: fromBase64(body['salt'] as String),
      params: KdfParams.fromJson(body['kdf'] as Map<String, Object?>),
    );
  }

  Future<({String token, KeyBundle bundle})> login(
    String email,
    List<int> authKey,
  ) async {
    final body = await _send(
        'POST', '/v1/login', {'email': email, 'authKey': toBase64(authKey)});
    return _session(body);
  }

  Future<({String token, KeyBundle bundle})> recover(
    String email,
    List<int> recoveryAuthKey,
  ) async {
    final body = await _send('POST', '/v1/recover',
        {'email': email, 'recoveryAuthKey': toBase64(recoveryAuthKey)});
    return _session(body);
  }

  Future<void> setPassword(
    String token,
    List<int> authKey,
    KeyBundle bundle,
  ) =>
      _send(
        'POST',
        '/v1/password',
        {'authKey': toBase64(authKey), 'bundle': bundle.toJson()},
        token: token,
      );

  Future<void> logout(String token) =>
      _send('POST', '/v1/logout', const {}, token: token);

  Future<AccountInfo> accountInfo(String token) async =>
      AccountInfo.fromJson(await _send('GET', '/v1/account', null, token: token));

  /// Deletes the account and every synced record. Needs the password key as
  /// well as the session, so a stolen session alone cannot delete it.
  /// Whether this Google account already has a Beaza account; Google has
  /// just confirmed the person owns it.
  /// [password]: the account has a password (an email account with the same
  /// Gmail, or one already linked), so the phone asks for it.
  Future<({bool exists, String email, bool password})> googleCheck(
      String idToken) async {
    final body = await _send('POST', '/v1/google/check', {'idToken': idToken});
    return (
      exists: body['exists'] as bool,
      email: body['email'] as String,
      password: body['password'] as bool? ?? false,
    );
  }

  /// A Google account: no password, the recovery key is the only lock.
  Future<String> googleRegister({
    required String idToken,
    required List<int> recoveryAuthKey,
    required KeyBundle bundle,
    required Consent consent,
  }) async {
    final body = await _send('POST', '/v1/google/register', {
      'idToken': idToken,
      'recoveryAuthKey': toBase64(recoveryAuthKey),
      'bundle': bundle.toJson(),
      'consent': consent.toJson(),
    });
    return body['token'] as String;
  }

  /// Logging in on a phone with Google needs a key that opens the data as
  /// well: the password key ([authKey]) or the recovery proof.
  Future<({String token, KeyBundle bundle})> googleLogin(
    String idToken, {
    List<int>? authKey,
    List<int>? recoveryAuthKey,
  }) async {
    final body = await _send('POST', '/v1/google/login', {
      'idToken': idToken,
      if (authKey != null) 'authKey': toBase64(authKey),
      if (recoveryAuthKey != null) 'recoveryAuthKey': toBase64(recoveryAuthKey),
    });
    return _session(body);
  }

  /// Deletes a Google account; [idToken] is a fresh one for the same account.
  Future<void> deleteGoogleAccount(String token, String idToken) => _send(
        'POST',
        '/v1/account/delete',
        {'idToken': idToken},
        token: token,
      );

  Future<void> deleteAccount(String token, List<int> authKey) => _send(
        'POST',
        '/v1/account/delete',
        {'authKey': toBase64(authKey)},
        token: token,
      );

  /// Stores or replaces encrypted records (at most 100 per call). Returns
  /// the account's change number after them.
  Future<int> pushRecords(String token, List<EncryptedRecord> records) async {
    final body = await _send(
      'POST',
      '/v1/records',
      {'records': [for (final r in records) r.toJson()]},
      token: token,
    );
    return body['seq'] as int;
  }

  /// Records changed after change number [since], oldest first.
  Future<RecordPage> pullRecords(String token, int since,
      {int limit = 500}) async {
    final body = await _send(
        'GET', '/v1/records?since=$since&limit=$limit', null,
        token: token);
    return RecordPage(
      records: [
        for (final r in body['records'] as List<Object?>)
          EncryptedRecord.fromJson(r as Map<String, Object?>),
      ],
      nextSince: body['nextSince'] as int,
      more: body['more'] as bool,
      latest: body['latest'] as int?,
    );
  }

  ({String token, KeyBundle bundle}) _session(Map<String, Object?> body) => (
        token: body['token'] as String,
        bundle: KeyBundle.fromJson(body['bundle'] as Map<String, Object?>),
      );

  Future<Map<String, Object?>> _send(
    String method,
    String path,
    Map<String, Object?>? body, {
    String? token,
  }) async {
    final request = http.Request(method, _base.resolve(path))
      ..headers['content-type'] = 'application/json'
      ..headers['accept'] = 'application/json';
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(
          await _client.send(request).timeout(timeout));
    } on http.ClientException {
      throw const NetworkException();
    } on TimeoutException {
      throw const NetworkException();
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw ApiException(response.statusCode, 'bad_response');
    }
    if (decoded is! Map<String, Object?>) {
      throw ApiException(response.statusCode, 'bad_response');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ApiException(
        response.statusCode,
        decoded['error'] as String? ?? 'unknown',
        retryAfterSeconds: decoded['retryAfterSeconds'] as int?,
      );
    }
    return decoded;
  }
}
