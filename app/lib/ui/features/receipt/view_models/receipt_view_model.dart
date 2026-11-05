import 'package:beaza/domain/use_cases/custom_categories.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/services/media_ai_api.dart';
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
    this.ai,
    this.consent,
  })  : _scanner = scanner,
        _ledger = ledger,
        _clock = clock ?? DateTime.now;

  final ReceiptScanner _scanner;
  final LedgerRepository _ledger;
  final DateTime Function() _clock;
  final ReceiptReader reader;

  /// Reading the photo with AI, after the person agreed; null hides it.
  final MediaAiApi? ai;
  final MediaAiConsent? consent;

  bool _fromAi = false;

  /// What is shown was read by the AI from the photo.
  bool get fromAi => _fromAi;

  bool _aiFailed = false;

  /// The AI was asked but gave nothing usable, so the phone's own reading
  /// is shown; [retryAi] asks again.
  bool get aiFailed => _aiFailed;

  String? _aiDetail;

  /// Why the AI failed, in the server's or the network's words.
  String? get aiDetail => _aiDetail;

  String? _provider;

  /// Which AI read the photo ("gemini" or "workers-ai").
  String? get provider => _provider;

  bool _aiTried = false;

  /// The photo went to the AI (the switch was on).
  bool get aiTried => _aiTried;

  bool _aiBusy = false;
  bool get aiBusy => _aiBusy;

  // Kept only while the review is open, for a retry; never stored.
  String? _jpeg;
  String _language = 'ar';
  ExtractionResult? _local;

  /// Sends the same photo to the AI again.
  Future<void> retryAi() async {
    final jpeg = _jpeg;
    final local = _local;
    if (ai == null || jpeg == null || local == null || _aiBusy) return;
    _aiBusy = true;
    if (!_disposed) notifyListeners();
    await _askAi(jpeg, local, _clock());
    _aiBusy = false;
    _duplicate = likelySamePayment(await _ledger.entries(), _result!);
    if (!_disposed) notifyListeners();
  }

  Future<void> _askAi(String jpeg, ExtractionResult local, DateTime now) async {
    _aiTried = true;
    try {
      final a = await ai!.readReceipt(jpeg, _language);
      if (a != null) {
        _provider = a.provider;
        _result = resultFromAi(a, local, now);
        _fromAi = true;
        _aiFailed = false;
        _aiDetail = null;
      } else {
        _aiFailed = true;
        _aiDetail = 'no_amount';
      }
    } on Object catch (e) {
      _aiFailed = true; // the phone's own reading stays
      _aiDetail = e.toString();
    }
  }

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

  /// The platform's own words for the failure, shown small so a problem on
  /// one phone can be told apart from another.
  String? _detail;
  String? get detail => _detail;

  bool _disposed = false;

  Future<void> scan(ReceiptSource source, {String language = 'ar'}) async {
    _set(ReceiptStep.scanning);
    _fromAi = false;
    _aiFailed = false;
    _aiTried = false;
    _aiDetail = null;
    _jpeg = null;
    try {
      final useAi = ai != null && (await consent?.isOn() ?? false);
      final String text;
      String? jpeg;
      if (useAi) {
        final scanned = await _scanner.scanWithImage(source);
        if (scanned == null) {
          _set(ReceiptStep.choose);
          return;
        }
        text = scanned.text;
        jpeg = scanned.jpeg;
      } else {
        final t = await _scanner.scan(source);
        if (t == null) {
          _set(ReceiptStep.choose);
          return;
        }
        text = t;
      }
      final now = _clock();
      final r = reader.read(text, now: now);
      _result = r;
      _local = r;
      _language = language;
      if (useAi && jpeg != null) {
        _jpeg = jpeg;
        await _askAi(jpeg, r, now);
      }
      _duplicate = likelySamePayment(await _ledger.entries(), _result!);
      _set(ReceiptStep.review);
    } on PlatformException catch (e) {
      _error = e.code;
      _detail = e.message;
      _set(ReceiptStep.failed);
    }
  }

  /// Saves what the person confirmed (BHD only). The guardrail and its
  /// alerts update from the ledger as for any other transaction.
  /// The person's own categories, for the category list.
  Future<List<String>> customCategories() async =>
      customCategoriesIn(await _ledger.entries());

  Future<void> save({
    required int amountFils,
    String? merchant,
    String? category,
  }) async {
    _jpeg = null; // the photo goes once the person decided
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
    _jpeg = null;
    _local = null;
    _fromAi = false;
    _aiFailed = false;
    _aiTried = false;
    _aiDetail = null;
    _duplicate = null;
    _error = null;
    _detail = null;
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

/// A receipt as the AI read it, keeping what the phone found when the AI
/// left a field out. Nothing is saved until the person confirms.
ExtractionResult resultFromAi(AiReceipt a, ExtractionResult local, DateTime now) {
  final at = _aiTime(a, now);
  final shop = a.shop ?? local.merchantRaw;
  if (a.kind == 'declined' || a.kind == 'refund') {
    return ExtractionResult(
      status: ExtractionStatus.nonTransaction,
      kind: a.kind == 'declined' ? MessageKind.declined : MessageKind.refund,
      amountFils: a.fils,
      currency: a.currency,
      merchantRaw: shop,
      timestamp: at ?? local.timestamp,
      templateVersion: 'receipt-ai',
    );
  }
  return ExtractionResult(
    status: ExtractionStatus.transaction,
    kind: MessageKind.transaction,
    amountFils: a.fils,
    currency: a.currency,
    type: a.kind == 'transfer' ? TxnType.transferOut : TxnType.purchase,
    direction: TxDirection.outgoing,
    merchantRaw: shop,
    // A known shop keeps its category; otherwise the AI's choice. The
    // person can change it on the review screen.
    category: const MerchantNormalizer().normalize(shop)?.category ??
        (kCategories.contains(a.category) ? a.category : null) ??
        local.category,
    timestamp: at ?? local.timestamp ?? now,
    templateVersion: 'receipt-ai',
    flags: [
      if (at == null && local.timestamp == null) ExtractionFlag.timestampFromReceipt,
    ],
  );
}

/// The printed date and time (Bahrain) as an instant, when it is sensible:
/// not in the future and not more than about a year old.
DateTime? _aiTime(AiReceipt a, DateTime now) {
  final d = a.date?.split('-').map(int.tryParse).toList();
  if (d == null || d.length != 3 || d.contains(null)) return null;
  final t = a.time?.split(':').map(int.tryParse).toList();
  final h = t != null && t.length == 2 && t[0] != null ? t[0]! : 12;
  final m = t != null && t.length == 2 && t[1] != null ? t[1]! : 0;
  final at = DateTime.utc(d[0]!, d[1]!, d[2]!, h, m).subtract(kBahrainOffset);
  if (at.isAfter(now.toUtc().add(const Duration(days: 1)))) return null;
  if (at.isBefore(now.toUtc().subtract(const Duration(days: 400)))) return null;
  return at;
}

