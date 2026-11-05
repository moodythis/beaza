import 'dart:convert';

import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/services/sync_api.dart' show kSyncServer;
import 'package:http/http.dart' as http;

/// The version of the photo and voice consent (server: MEDIA_CONSENT_VERSION).
const String kMediaConsentVersion = '2026-11-05';

/// What the AI read on a receipt photo. [date] is YYYY-MM-DD and [time]
/// HH:MM when printed; [kind] is purchase, refund, declined or transfer.
class AiReceipt {
  const AiReceipt({
    required this.fils,
    required this.currency,
    required this.kind,
    this.shop,
    this.date,
    this.time,
    this.category,
  });

  final int fils;
  final String currency;
  final String kind;
  final String? shop;
  final String? date;
  final String? time;

  /// One of the app's categories, chosen by the AI from what was bought.
  final String? category;

  static AiReceipt? fromJson(Object? j) {
    if (j is! Map) return null;
    final fils = j['fils'];
    if (fils is! int || fils <= 0) return null;
    return AiReceipt(
      fils: fils,
      currency: j['currency'] is String ? j['currency'] as String : 'BHD',
      kind: j['kind'] is String ? j['kind'] as String : 'purchase',
      shop: j['shop'] as String?,
      date: j['date'] as String?,
      time: j['time'] as String?,
      category: j['category'] as String?,
    );
  }
}

/// The AI was reached but could not read it; [reason] is the server's
/// code (model_error, empty_reply, no_amount) and [detail] its words.
class MediaAiException implements Exception {
  const MediaAiException(this.reason, [this.detail]);
  final String reason;
  final String? detail;

  @override
  String toString() => detail == null ? reason : '$reason: $detail';
}

/// One cash expense the AI understood.
class AiDraft {
  const AiDraft({required this.item, required this.fils, this.category});

  final String item;
  final int fils;
  final String? category;
}

abstract class MediaAiApi {
  /// Null when nothing could be read. Throws on a network or server error.
  Future<AiReceipt?> readReceipt(String jpegBase64, String language);

  /// What was said and the expenses in it.
  Future<({String text, List<AiDraft> drafts})> readVoice(
      String audioBase64, String language);

  Future<List<AiDraft>> readExpenses(String text, String language);
}

class HttpMediaAiApi implements MediaAiApi {
  HttpMediaAiApi({
    http.Client? client,
    String baseUrl = kSyncServer,
    this.timeout = const Duration(seconds: 60),
  })  : _client = client ?? http.Client(),
        _base = Uri.parse(baseUrl);

  final http.Client _client;
  final Uri _base;
  final Duration timeout;

  Future<Map<Object?, Object?>> _post(String path, Map<String, Object> body) async {
    final res = await _client
        .post(
          _base.resolve(path),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'consent': kMediaConsentVersion, ...body}),
        )
        .timeout(timeout);
    final json = jsonDecode(res.body);
    if (res.statusCode != 200 || json is! Map) {
      throw Exception('${json is Map ? json['error'] : res.statusCode}');
    }
    return json;
  }

  static List<AiDraft> _drafts(Object? list) => [
        if (list is List)
          for (final d in list)
            if (d is Map && d['fils'] is int && (d['fils'] as int) > 0)
              AiDraft(
                item: d['item'] is String ? d['item'] as String : '',
                fils: d['fils'] as int,
                category: d['category'] as String?,
              ),
      ];

  @override
  Future<AiReceipt?> readReceipt(String jpegBase64, String language) async {
    final j = await _post('/v1/receipt', {'language': language, 'image': jpegBase64});
    final r = AiReceipt.fromJson(j['receipt']);
    if (r == null && j['reason'] is String) {
      throw MediaAiException(j['reason'] as String, j['detail'] as String?);
    }
    return r;
  }

  @override
  Future<({String text, List<AiDraft> drafts})> readVoice(
      String audioBase64, String language) async {
    final j = await _post('/v1/voice', {'language': language, 'audio': audioBase64});
    return (text: j['text'] is String ? j['text'] as String : '', drafts: _drafts(j['drafts']));
  }

  @override
  Future<List<AiDraft>> readExpenses(String text, String language) async =>
      _drafts((await _post('/v1/expenses', {'language': language, 'text': text}))['drafts']);
}

/// The person's separate yes to sending photos and voice to the AI.
class MediaAiConsent {
  MediaAiConsent(this._prefs);

  static const String prefName = 'mediaAiConsent';
  final PreferencesStore _prefs;

  Future<bool> isOn() async => await _prefs.read(prefName) == kMediaConsentVersion;
  Future<void> turnOn() => _prefs.write(prefName, kMediaConsentVersion);
  Future<void> turnOff() => _prefs.write(prefName, null);
}
