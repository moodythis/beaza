import 'package:flutter/services.dart';

enum ReceiptSource { camera, gallery }

/// A receipt photo or screenshot to text, on the phone (MainActivity,
/// `beaza/device` method `scanReceipt`, ML Kit). The picture is never kept:
/// a camera photo is deleted as soon as it is read, a gallery picture is
/// read in place.
abstract class ReceiptScanner {
  /// The text on the picture, or null when the person cancelled. Throws a
  /// [PlatformException] with code `no_camera`, `no_picker` or `ocr`.
  Future<String?> scan(ReceiptSource source);
}

class PlatformReceiptScanner implements ReceiptScanner {
  static const _channel = MethodChannel('beaza/device');

  @override
  Future<String?> scan(ReceiptSource source) =>
      _channel.invokeMethod<String>('scanReceipt', {'source': source.name});
}
