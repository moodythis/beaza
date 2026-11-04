import 'package:flutter/services.dart';

/// Speech to text inside Beaza (MainActivity, `beaza/device` methods
/// `listen` and `stopListening`, live text on `beaza/speech_events`).
/// The phone's speech service turns the audio into text; Beaza keeps only
/// the text and stores no audio.
abstract class VoiceInput {
  /// What the person said, or null when nothing was heard. Throws a
  /// [PlatformException] with code `no_permission` (microphone refused),
  /// `no_speech` (no speech service), `network` or `speech_error`.
  Future<String?> listen({required String language});

  /// Ends listening early; [listen] still answers with what was heard.
  Future<void> stop();

  /// The words heard so far, while listening.
  Stream<String> get partials;
}

class PlatformVoiceInput implements VoiceInput {
  static const _channel = MethodChannel('beaza/device');
  static const _events = EventChannel('beaza/speech_events');

  @override
  Future<String?> listen({required String language}) =>
      _channel.invokeMethod<String>('listen', {'language': language});

  @override
  Future<void> stop() => _channel.invokeMethod<void>('stopListening');

  @override
  Stream<String> get partials => _events
      .receiveBroadcastStream()
      .map((e) => e is Map ? e['partial'] : null)
      .where((p) => p is String && p.isNotEmpty)
      .cast<String>();
}

/// The speech language: Bahraini Arabic or English.
String speechLanguage(String appLanguage) =>
    appLanguage == 'ar' ? 'ar-BH' : 'en-US';
