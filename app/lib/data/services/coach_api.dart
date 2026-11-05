import 'dart:convert';

import 'package:beaza/data/services/sync_api.dart' show kSyncServer;
import 'package:http/http.dart' as http;

class CoachPlan {
  const CoachPlan({
    required this.text,
    required this.fromModel,
    this.provider,
    this.reason,
  });

  final String text;

  /// False when the server wrote the plan by rules (model off, busy, or its
  /// reply used a number it was not given).
  final bool fromModel;

  /// Which AI wrote it: "gemini" or "workers-ai" (null from an older server).
  final String? provider;

  /// Why the model's plan was not used (the AI's own error), when not.
  final String? reason;
}

class CoachException implements Exception {
  const CoachException(this.code);

  /// `coach_busy` (daily limit reached), `coach_disabled`, `network`, or
  /// the server's error code.
  final String code;

  @override
  String toString() => 'CoachException($code)';
}

abstract class CoachApi {
  Future<CoachPlan> plan(Map<String, Object> request);
}

/// POST /v1/coach on Beaza's server, which asks Google's Gemini
/// Workers AI. No account and no API key on the phone.
class HttpCoachApi implements CoachApi {
  HttpCoachApi({
    http.Client? client,
    String baseUrl = kSyncServer,
    this.timeout = const Duration(seconds: 45),
  })  : _client = client ?? http.Client(),
        _base = Uri.parse(baseUrl);

  final http.Client _client;
  final Uri _base;
  final Duration timeout;

  @override
  Future<CoachPlan> plan(Map<String, Object> request) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            _base.resolve('/v1/coach'),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(request),
          )
          .timeout(timeout);
    } on Exception {
      throw const CoachException('network');
    }
    Map<String, Object?> body;
    try {
      body = jsonDecode(res.body) as Map<String, Object?>;
    } on Object {
      throw const CoachException('server_error');
    }
    if (res.statusCode != 200) {
      throw CoachException(body['error'] as String? ?? 'server_error');
    }
    final text = body['plan'];
    if (text is! String || text.trim().isEmpty) {
      throw const CoachException('server_error');
    }
    return CoachPlan(
      text: text.trim(),
      fromModel: body['source'] == 'model',
      provider: body['provider'] as String?,
      reason: body['reason'] as String?,
    );
  }
}
