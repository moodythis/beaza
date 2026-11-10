import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/services/leaderboard_api.dart';
import 'package:beaza/domain/use_cases/leaderboard.dart';

/// The online leaderboard, for a person who joined it with its own
/// consent. Until then nothing is sent and the practice board is shown.
class LeaderboardSync {
  LeaderboardSync({required LeaderboardApi api, required PreferencesStore preferences})
      : _api = api,
        _prefs = preferences;

  static const String prefName = 'boardConsent';

  final LeaderboardApi _api;
  final PreferencesStore _prefs;

  bool _joined = false;
  bool get joined => _joined;

  /// The online board as last fetched; null before that, or when not
  /// joined.
  List<BoardRow>? rows;

  /// This phone's place online; null when outside the top 50.
  int? rank;

  /// Why the last update failed (`network`, `timeout`, ...); null when it
  /// worked.
  String? error;

  Map<String, Object>? _lastSent;

  Future<void> load() async {
    _joined = await _prefs.read(prefName) == kBoardConsentVersion;
  }

  /// The person agreed on the leaderboard card.
  Future<void> join() async {
    await _prefs.write(prefName, kBoardConsentVersion);
    _joined = true;
  }

  /// Leaves: the consent is withdrawn first, then the server is asked to
  /// delete the row. If it cannot be reached the row still goes by itself
  /// after 30 days without an update.
  Future<void> leave(String boardId) async {
    await _prefs.write(prefName, null);
    _joined = false;
    rows = null;
    rank = null;
    error = null;
    _lastSent = null;
    try {
      await _api.leave(boardId);
    } on BoardException {
      // Nothing more is sent from now on either way.
    }
  }

  /// Sends the score when it changed (or was never sent) and keeps the
  /// board that comes back. True when what is on screen changed.
  Future<bool> push({
    required String boardId,
    required String? nickname,
    required int points,
    required int streak,
  }) async {
    if (!_joined) return false;
    final request = boardRequest(
        boardId: boardId, nickname: nickname, points: points, streak: streak);
    if (rows != null && _same(request, _lastSent)) return false;
    try {
      final board = await _api.post(request);
      rows = board.rows;
      rank = board.rank;
      error = null;
      _lastSent = request;
      // Outside the top 50 the server keeps no row: show it at the end.
      if (!board.rows.any((r) => r.me)) {
        rows = [
          ...board.rows,
          BoardRow(
            points: points,
            streak: streak,
            number: personaNumber(boardId),
            nickname: nickname,
            me: true,
          ),
        ];
      }
    } on BoardException catch (e) {
      error = e.code;
      rows = null;
    }
    return true;
  }

  static bool _same(Map<String, Object> a, Map<String, Object>? b) =>
      b != null &&
      a.length == b.length &&
      a.entries.every((e) => b[e.key] == e.value);
}
