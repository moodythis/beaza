import 'package:flutter/services.dart';

/// Shows a system notification. Texts are already localized.
abstract class AlertNotifier {
  /// Asks for the notification permission (Android 13+). True when allowed.
  Future<bool> requestPermission();

  Future<void> show({required int id, required String title, required String body});
}

class PlatformAlertNotifier implements AlertNotifier {
  static const _channel = MethodChannel('beaza/notify');

  @override
  Future<bool> requestPermission() async =>
      await _channel.invokeMethod<bool>('requestPermission') ?? false;

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) =>
      _channel.invokeMethod<void>(
        'show',
        {'id': id, 'title': title, 'body': body},
      );
}
