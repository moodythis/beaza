import 'package:flutter/services.dart';

/// Phone settings and files, which only Android can reach
/// (Channels.kt, channel `beaza/device`).
abstract class DeviceService {
  /// True when battery saving may stop Beaza while it is closed, so bank
  /// messages are read and alerts shown only when the app is opened. Null
  /// when unknown.
  Future<bool?> batteryRestricted();

  /// Opens Beaza's page in the phone's settings (App info), where Battery
  /// can be set to Unrestricted.
  Future<void> openAppSettings();

  /// Asks the person where to save [text] as a file named [fileName].
  /// True when saved, false when they cancelled.
  Future<bool> saveText({required String fileName, required String text});
}

class PlatformDeviceService implements DeviceService {
  static const _channel = MethodChannel('beaza/device');

  @override
  Future<bool?> batteryRestricted() =>
      _channel.invokeMethod<bool>('batteryRestricted');

  @override
  Future<void> openAppSettings() =>
      _channel.invokeMethod<void>('openAppSettings');

  @override
  Future<bool> saveText({
    required String fileName,
    required String text,
  }) async =>
      await _channel.invokeMethod<bool>(
        'saveText',
        {'name': fileName, 'text': text},
      ) ??
      false;
}
