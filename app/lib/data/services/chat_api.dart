import 'package:beaza/data/services/coach_api.dart'
    show CoachException, postCoachJson;
import 'package:beaza/data/services/sync_api.dart' show kSyncServer;
import 'package:http/http.dart' as http;

/// What the server said to a question about the person's spending.
class ChatAnswer {
  const ChatAnswer({this.text, this.refused = false, this.reason, this.provider});

  /// Gemini's answer, after the server checked it; null when there is none.
  final String? text;

  /// The AI said the question is not about the person's spending.
  final bool refused;

  /// Why there is no [text] (the AI's own error or the check that failed).
  final String? reason;

  final String? provider;
}

abstract class ChatApi {
  /// POST /v1/chat. Throws [CoachException] when the server cannot be
  /// reached, is busy (`coach_busy`) or refuses the request.
  Future<ChatAnswer> ask(Map<String, Object> request);
}

/// The spending chat on Beaza's server, which asks Google's Gemini with a
/// fixed prompt. No account and no API key on the phone.
class HttpChatApi implements ChatApi {
  HttpChatApi({
    http.Client? client,
    String baseUrl = kSyncServer,
    this.timeout = const Duration(seconds: 30),
  })  : _client = client ?? http.Client(),
        _base = Uri.parse(baseUrl);

  final http.Client _client;
  final Uri _base;
  final Duration timeout;

  @override
  Future<ChatAnswer> ask(Map<String, Object> request) async {
    final body =
        await postCoachJson(_client, _base, '/v1/chat', request, timeout);
    final text = body['answer'];
    return ChatAnswer(
      text: text is String && text.trim().isNotEmpty ? text.trim() : null,
      refused: body['source'] == 'refused',
      reason: body['reason'] as String?,
      provider: body['provider'] as String?,
    );
  }
}
