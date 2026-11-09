import 'dart:async';
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

  /// Which AI wrote it: "gemini" (null from an older server).
  final String? provider;

  /// Why the model's plan was not used (the AI's own error), when not.
  final String? reason;
}

class CoachException implements Exception {
  const CoachException(this.code, {this.detail});

  /// What the phone's network layer said (no request data), so a failure
  /// can be told apart on the phone: DNS, TLS, connection refused.
  final String? detail;

  /// `coach_busy` (daily limit reached), `coach_disabled`, `network` (the
  /// server could not be reached), `timeout` (it took too long), or the
  /// server's error code.
  final String code;

  @override
  String toString() => 'CoachException($code)';
}

/// One AI idea for spending less at a shop. A suggestion to check, never a
/// price or an offer (the server drops any idea with a number in it).
class CheaperOption {
  const CheaperOption({required this.shop, required this.idea});

  final String shop;
  final String idea;
}

class CheaperOptions {
  const CheaperOptions({required this.options, this.provider, this.reason});

  final List<CheaperOption> options;
  final String? provider;

  /// Why there are none (the AI's own error), when there are none.
  final String? reason;
}

abstract class CoachApi {
  Future<CoachPlan> plan(Map<String, Object> request);

  /// POST /v1/alternatives with the shop names and visit counts of a plan
  /// request.
  Future<CheaperOptions> alternatives(Map<String, Object> request);
}

/// POST /v1/coach on Beaza's server, which asks Google's Gemini. No
/// account and no API key on the phone.
class HttpCoachApi implements CoachApi {
  HttpCoachApi({
    http.Client? client,
    String baseUrl = kSyncServer,
    this.timeout = const Duration(seconds: 75),
  })  : _client = client ?? http.Client(),
        _base = Uri.parse(baseUrl);

  final http.Client _client;
  final Uri _base;
  final Duration timeout;

  @override
  Future<CheaperOptions> alternatives(Map<String, Object> request) async {
    final body = await _post('/v1/alternatives', request);
    final list = body['alternatives'];
    if (list is! List) throw const CoachException('server_error');
    return CheaperOptions(
      options: [
        for (final x in list)
          if (x is Map && x['shop'] is String && x['idea'] is String)
            CheaperOption(shop: x['shop'] as String, idea: x['idea'] as String),
      ],
      provider: body['provider'] as String?,
      reason: body['reason'] as String?,
    );
  }

  @override
  Future<CoachPlan> plan(Map<String, Object> request) async {
    final body = await _post('/v1/coach', request);
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

  Future<Map<String, Object?>> _post(
      String path, Map<String, Object> request) async {
    final http.Response res;
    try {
      res = await _client
          .post(
            _base.resolve(path),
            headers: {'content-type': 'application/json'},
            body: jsonEncode(request),
          )
          .timeout(timeout);
    } on TimeoutException {
      throw const CoachException('timeout');
    } on Exception catch (e) {
      final text = e.toString().replaceAll(RegExp(r'\s+'), ' ');
      throw CoachException('network',
          detail: text.length > 160 ? text.substring(0, 160) : text);
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
    return body;
  }
}
