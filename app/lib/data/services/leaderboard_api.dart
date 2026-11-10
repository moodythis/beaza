import 'dart:async';
import 'dart:convert';

import 'package:beaza/data/services/sync_api.dart' show kSyncServer;
import 'package:beaza/domain/use_cases/leaderboard.dart';
import 'package:http/http.dart' as http;

/// The version of the online leaderboard consent (server:
/// BOARD_CONSENT_VERSION).
const String kBoardConsentVersion = '2026-11-10.1';

class BoardException implements Exception {
  const BoardException(this.code);

  /// `network`, `timeout`, `board_busy`, `consent_required`, or the
  /// server's error code.
  final String code;

  @override
  String toString() => 'BoardException($code)';
}

/// The board as the server returned it, with this phone's place.
class OnlineBoard {
  const OnlineBoard({required this.rows, required this.rank});

  final List<BoardRow> rows;

  /// This phone's place; null when its score is outside the top 50.
  final int? rank;
}

/// The optional online leaderboard. What is sent is exactly [request]:
/// a random id, the display mode, an optional nickname, points and streak.
abstract class LeaderboardApi {
  Future<OnlineBoard> post(Map<String, Object> request);
  Future<void> leave(String boardId);
}

/// What the phone sends: nothing else is ever added to it.
Map<String, Object> boardRequest({
  required String boardId,
  required String? nickname,
  required int points,
  required int streak,
}) =>
    {
      'consent': kBoardConsentVersion,
      'boardId': boardId,
      'displayMode': nickname == null ? 'persona' : 'nickname',
      if (nickname != null) 'nickname': nickname,
      'points30d': points.clamp(0, 5000),
      'streakDays': streak.clamp(0, 365),
    };

class HttpLeaderboardApi implements LeaderboardApi {
  HttpLeaderboardApi({
    http.Client? client,
    Uri? base,
    this.timeout = const Duration(seconds: 20),
  })  : _client = client ?? http.Client(),
        _base = base ?? Uri.parse(kSyncServer);

  final http.Client _client;
  final Uri _base;
  final Duration timeout;

  @override
  Future<OnlineBoard> post(Map<String, Object> request) async {
    final body = await _post('/v1/leaderboard', request);
    final list = body['rows'];
    if (list is! List) throw const BoardException('server_error');
    return OnlineBoard(
      rows: [
        for (final x in list)
          if (x is Map &&
              x['points'] is int &&
              x['streak'] is int &&
              x['number'] is int)
            BoardRow(
              points: x['points'] as int,
              streak: x['streak'] as int,
              number: x['number'] as int,
              nickname: x['nickname'] is String ? x['nickname'] as String : null,
              me: x['me'] == true,
            ),
      ],
      rank: body['rank'] is int ? body['rank'] as int : null,
    );
  }

  @override
  Future<void> leave(String boardId) async {
    await _post('/v1/leaderboard/leave', {'boardId': boardId});
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
      throw const BoardException('timeout');
    } on Exception {
      throw const BoardException('network');
    }
    Map<String, Object?> body;
    try {
      body = jsonDecode(res.body) as Map<String, Object?>;
    } on Object {
      throw const BoardException('server_error');
    }
    if (res.statusCode != 200) {
      throw BoardException(body['error'] as String? ?? 'server_error');
    }
    return body;
  }
}
