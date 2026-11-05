import 'dart:convert';

import 'package:beaza/data/services/sync_api.dart' show kSyncServer;
import 'package:http/http.dart' as http;

/// The version of the AI sorting consent (server: CATEGORIZE_CONSENT_VERSION).
const String kCategorizeConsentVersion = '2026-11-05';

abstract class CategorizeApi {
  /// A category for each shop name the model recognised. Throws on a
  /// network or server error; an empty map means it could not tell.
  Future<Map<String, String>> categorize(List<String> names);
}

/// POST /v1/categorize: shop names only, no account, no key on the phone.
class HttpCategorizeApi implements CategorizeApi {
  HttpCategorizeApi({
    http.Client? client,
    String baseUrl = kSyncServer,
    this.timeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _base = Uri.parse(baseUrl);

  final http.Client _client;
  final Uri _base;
  final Duration timeout;

  @override
  Future<Map<String, String>> categorize(List<String> names) async {
    final res = await _client
        .post(
          _base.resolve('/v1/categorize'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'consent': kCategorizeConsentVersion, 'names': names}),
        )
        .timeout(timeout);
    final body = jsonDecode(res.body);
    if (res.statusCode != 200 || body is! Map) {
      throw Exception('categorize ${res.statusCode}');
    }
    final cats = body['categories'];
    if (cats is! Map) return const {};
    return {
      for (final e in cats.entries)
        if (e.key is String && e.value is String) e.key as String: e.value as String,
    };
  }
}
