import 'package:beaza/domain/use_cases/message_intake.dart';
import 'package:flutter/foundation.dart';

/// Loads the bank messages that were not understood. The text lives only in
/// this object while the screen is open.
class ReviewViewModel extends ChangeNotifier {
  ReviewViewModel(this._intake);

  final MessageIntake _intake;

  List<UnreadMessage>? _items;
  List<UnreadMessage>? get items => _items;

  bool _failed = false;
  bool get failed => _failed;

  bool _disposed = false;

  Future<void> load() async {
    try {
      _items = await _intake.unreadable();
      _failed = false;
    } on Exception {
      _failed = true;
    }
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _items = null;
    super.dispose();
  }
}
