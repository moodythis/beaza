import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/services/receipt_scanner.dart';
import 'package:beaza/domain/use_cases/same_payment.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum ReceiptStep { choose, scanning, review, saving, saved, failed }

/// Picture -> text (on the phone) -> purchase -> check for a bank message
/// of the same payment -> the person reviews -> saved. The picture and its
/// text are never stored: only what the person confirms.
class ReceiptViewModel extends ChangeNotifier {
  ReceiptViewModel({
    required ReceiptScanner scanner,
    required LedgerRepository ledger,
    DateTime Function()? clock,
    this.reader = const ReceiptReader(),
  })  : _scanner = scanner,
        _ledger = ledger,
        _clock = clock ?? DateTime.now;

  final ReceiptScanner _scanner;
  final LedgerRepository _ledger;
  final DateTime Function() _clock;
  final ReceiptReader reader;

  ReceiptStep _step = ReceiptStep.choose;
  ReceiptStep get step => _step;

  ExtractionResult? _result;

  /// What was read, for the review form.
  ExtractionResult? get result => _result;

  LedgerEntry? _duplicate;

  /// A transaction already in the ledger that is probably this payment.
  LedgerEntry? get duplicate => _duplicate;

  String? _error;

  /// The platform error code when [step] is [ReceiptStep.failed].
  String? get error => _error;

  bool _disposed = false;

  Future<void> scan(ReceiptSource source) async {
    _set(ReceiptStep.scanning);
    try {
      final text = await _scanner.scan(source);
      if (text == null) {
        _set(ReceiptStep.choose);
        return;
      }
      final r = reader.read(text, now: _clock());
      _result = r;
      _duplicate = likelySamePayment(await _ledger.entries(), r);
      _set(ReceiptStep.review);
    } on PlatformException catch (e) {
      _error = e.code;
      _set(ReceiptStep.failed);
    }
  }

  /// Saves what the person confirmed (BHD only). The guardrail and its
  /// alerts update from the ledger as for any other transaction.
  Future<void> save({
    required int amountFils,
    String? merchant,
    String? category,
  }) async {
    _set(ReceiptStep.saving);
    await _ledger.addManual(
      amountFils: amountFils,
      merchant: merchant,
      at: _result?.timestamp ?? _clock(),
      category: category,
    );
    _set(ReceiptStep.saved);
  }

  void startOver() {
    _result = null;
    _duplicate = null;
    _error = null;
    _set(ReceiptStep.choose);
  }

  void _set(ReceiptStep s) {
    _step = s;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
