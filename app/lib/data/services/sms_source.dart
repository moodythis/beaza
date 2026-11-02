import 'package:flutter/services.dart';

/// One inbox message as listed: no text, only who sent it and when.
class InboxMessage {
  const InboxMessage({
    required this.id,
    required this.sender,
    required this.receivedAt,
  });

  final String id;
  final String sender;

  /// UTC.
  final DateTime receivedAt;
}

/// The phone's SMS inbox. Listing never returns message text; bodies are
/// requested only for ids the caller has already decided to read.
abstract class SmsSource {
  Future<bool> hasPermission();

  /// Shows Android's permission dialog. True when granted.
  Future<bool> requestPermission();

  Future<List<InboxMessage>> listInbox({required DateTime since});

  Future<Map<String, String>> readBodies(List<String> ids);

  /// Fires (with no content) when a new SMS arrives while the app is open.
  Stream<void> get arrivals;
}

class PlatformSmsSource implements SmsSource {
  static const _methods = MethodChannel('beaza/sms');
  static const _events = EventChannel('beaza/sms_events');

  @override
  Future<bool> hasPermission() async =>
      await _methods.invokeMethod<bool>('hasPermission') ?? false;

  @override
  Future<bool> requestPermission() async =>
      await _methods.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<List<InboxMessage>> listInbox({required DateTime since}) async {
    final raw = await _methods.invokeListMethod<Map<Object?, Object?>>(
          'listInbox',
          {'sinceMs': since.toUtc().millisecondsSinceEpoch},
        ) ??
        const [];
    return [
      for (final m in raw)
        InboxMessage(
          id: m['id']! as String,
          sender: m['sender'] as String? ?? '',
          receivedAt: DateTime.fromMillisecondsSinceEpoch(
            (m['dateMs']! as num).toInt(),
            isUtc: true,
          ),
        ),
    ];
  }

  @override
  Future<Map<String, String>> readBodies(List<String> ids) async {
    if (ids.isEmpty) return const {};
    final raw = await _methods
        .invokeMapMethod<String, String>('readBodies', {'ids': ids});
    return raw ?? const {};
  }

  @override
  Stream<void> get arrivals => _events.receiveBroadcastStream().map((_) {});
}
