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

  /// The text and a smaller JPEG (base64) for reading with AI, only after
  /// the person agreed. The picture is still never kept on the phone.
  Future<({String text, String? jpeg})?> scanWithImage(ReceiptSource source) async {
    final text = await scan(source);
    return text == null ? null : (text: text, jpeg: null);
  }
}

class PlatformReceiptScanner implements ReceiptScanner {
  static const _channel = MethodChannel('beaza/device');

  @override
  Future<String?> scan(ReceiptSource source) =>
      _channel.invokeMethod<String>('scanReceipt', {'source': source.name});

  @override
  Future<({String text, String? jpeg})?> scanWithImage(ReceiptSource source) async {
    final r = await _channel.invokeMethod<Object>(
        'scanReceipt', {'source': source.name, 'withImage': true});
    if (r == null) return null;
    if (r is String) return (text: r, jpeg: null);
    final m = r as Map;
    return (text: (m['text'] as String?) ?? '', jpeg: m['jpeg'] as String?);
  }
}
