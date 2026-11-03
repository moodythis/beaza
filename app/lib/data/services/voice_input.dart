import 'package:flutter/services.dart';

/// Speech to text through the phone's own speech screen (Channels.kt,
/// `beaza/device` method `listen`). Beaza records nothing itself.
abstract class VoiceInput {
  /// What the person said, or null when they cancelled. Throws a
  /// [PlatformException] with code `no_speech` when the phone has no
  /// speech service.
  Future<String?> listen({required String language});
}

class PlatformVoiceInput implements VoiceInput {
  static const _channel = MethodChannel('beaza/device');

  @override
  Future<String?> listen({required String language}) =>
      _channel.invokeMethod<String>('listen', {'language': language});
}

/// The speech language for the app language: Bahraini Arabic or English.
String speechLanguage(String appLanguage) =>
    appLanguage == 'ar' ? 'ar-BH' : 'en-US';
