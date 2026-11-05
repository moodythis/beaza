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

/// A short recording (at most 60 s, AAC) for speech to text with AI, only
/// after the person agreed. The file is deleted on the phone once read.
abstract class VoiceRecorder {
  /// Throws a [PlatformException] `no_permission` when the microphone is
  /// not allowed yet (Android then asks).
  Future<void> start();

  /// The recording as base64, or null when nothing was recorded.
  Future<String?> stop();

  Future<void> cancel();
}

class PlatformVoiceRecorder implements VoiceRecorder {
  static const _channel = MethodChannel('beaza/device');

  @override
  Future<void> start() => _channel.invokeMethod<void>('recordStart');

  @override
  Future<String?> stop() => _channel.invokeMethod<String>('recordStop');

  @override
  Future<void> cancel() => _channel.invokeMethod<void>('recordCancel');
}
