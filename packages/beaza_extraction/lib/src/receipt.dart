/// Text read from a receipt photo or a payment screenshot (on-device OCR),
/// to a purchase: total, shop, date. Rules only, so the same text always
/// gives the same result and nothing leaves the phone.
///
/// Written before any real receipt was collected: the keyword lists are a
/// first guess and must be checked against real samples (SRS FR-9.x).
library;

import 'classifier.dart' show MessageKind;
import 'guardrail.dart' show kBahrainOffset;
import 'merchant.dart';
import 'tier1.dart' show TxDirection;
import 'validator.dart';

class ReceiptReader {
  const ReceiptReader({this.merchants = const MerchantNormalizer()});

  final MerchantNormalizer merchants;

  /// Lines that name the amount to pay, strongest first.
  static final RegExp _grandTotal = RegExp(
    r'grand\s*total|net\s*(?:total|amount|payable)|total\s*(?:amount|due|payable|incl|inc\b|bhd|bd)|amount\s*(?:due|payable|paid)|balance\s*due|الاجمالي|الإجمالي|المجموع\s*الكلي|المبلغ\s*الاجمالي|المبلغ\s*الإجمالي|الصافي|المطلوب',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _total = RegExp(r'\btotal\b|المجموع|المبلغ',
      caseSensitive: false, unicode: true);

  /// Lines whose amount is never the total.
  static final RegExp _notTotal = RegExp(
    r'sub\s*-?\s*total|\bvat\b|\btax\b|discount|change|cash|tendered|saving|\bqty\b|quantity|items?\b|الضريبة|ضريبة|خصم|الباقي|نقدا|نقدًا|الكمية',
    caseSensitive: false,
    unicode: true,
  );

  /// Lines that are not the shop's name.
  static final RegExp _notShop = RegExp(
    r'tax\s*invoice|invoice|receipt|welcome|\bvat\b|c\.?\s?r\.?\s*(?:no|#)|\btel\b|phone|mobile|\bdate\b|\btime\b|www|http|فاتورة|ضريبية|اهلا|أهلا|مرحبا|شكرا|سجل\s*تجاري',
    caseSensitive: false,
    unicode: true,
  );

  static final RegExp _inclusive =
      RegExp(r'incl|inclusive|شامل', caseSensitive: false, unicode: true);

  /// A VAT or tax line is skipped unless it is the total including it.
  static bool _skip(String l) => _notTotal.hasMatch(l) && !_inclusive.hasMatch(l);

  /// 3.300, 12,450, 22.00. Not part of a date such as 03.11.2026.
  static final RegExp _amount = RegExp(r'(?<![\d.,])(\d{1,5})[.,](\d{2,3})(?![\d.,])');

  static final RegExp _onlyAmount = RegExp(
    r'^\s*(?:bhd|bd|usd|\$|د\.?\s?ب)?\s*\d{1,5}[.,]\d{2,3}\s*(?:bhd|bd|usd|د\.?\s?ب)?\s*$',
    caseSensitive: false,
    unicode: true,
  );
  static final RegExp _onlyCurrency = RegExp(r'^\s*(?:bhd|bd|usd|\$|د\.?\s?ب)\s*$',
      caseSensitive: false, unicode: true);

  ExtractionResult read(String text, {required DateTime now}) {
    final lines = _digits(text)
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final flags = <ExtractionFlag>[];

    // Total: the last "grand total" style line, else the last "total" line,
    // else the largest amount on the receipt (marked as a guess).
    var found = _byKeyword(lines, _grandTotal) ?? _byKeyword(lines, _total);
    var confidence = found == null ? 0.0 : (found.$2 ? 0.9 : 0.8);
    if (found == null) {
      final guess = _largest(lines);
      if (guess != null) {
        found = (guess, true);
        confidence = 0.4;
        flags.add(ExtractionFlag.totalGuessed);
      }
    }

    final currency = _currency(text);
    if (currency == null) {
      flags.add(ExtractionFlag.currencyAssumed);
    } else if (currency != 'BHD') {
      flags.add(ExtractionFlag.foreignCurrency);
    }

    var at = _dateTime(lines.join('\n'), now);
    if (at == null) {
      at = now;
      flags.add(ExtractionFlag.timestampFromReceipt);
    }

    final shop = _shop(lines);
    final info = merchants.normalize(shop);

    if (found == null) {
      return ExtractionResult(
        status: ExtractionStatus.unparsed,
        kind: MessageKind.transaction,
        currency: currency ?? 'BHD',
        merchantRaw: shop,
        merchantNorm: info?.name,
        category: info?.category,
        timestamp: at.toUtc(),
        issues: const [ValidationIssue.amountMissing],
        flags: flags,
        templateVersion: kReceiptReaderVersion,
      );
    }
    return ExtractionResult(
      status: ExtractionStatus.transaction,
      kind: MessageKind.transaction,
      amountFils: found.$1,
      currency: currency ?? 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantRaw: shop,
      merchantNorm: info?.name,
      category: info?.category,
      timestamp: at.toUtc(),
      confidence: confidence,
      templateVersion: kReceiptReaderVersion,
      flags: flags,
    );
  }

  /// Arabic-Indic digits and the Arabic decimal mark to ASCII.
  static String _digits(String s) {
    final b = StringBuffer();
    for (final r in s.runes) {
      if (r >= 0x0660 && r <= 0x0669) {
        b.writeCharCode(0x30 + r - 0x0660);
      } else if (r >= 0x06F0 && r <= 0x06F9) {
        b.writeCharCode(0x30 + r - 0x06F0);
      } else if (r == 0x066B) {
        b.write('.');
      } else {
        b.writeCharCode(r);
      }
    }
    return b.toString();
  }

  static int _fils(RegExpMatch m) =>
      int.parse(m[1]!) * 1000 + int.parse(m[2]!.padRight(3, '0'));

  /// (fils, amount on the same line). OCR often puts the labels in one
  /// column and the amounts in another, so the amount may follow on one of
  /// the next lines.
  (int, bool)? _byKeyword(List<String> lines, RegExp keyword) {
    (int, bool)? last;
    for (var i = 0; i < lines.length; i++) {
      final l = lines[i];
      if (!keyword.hasMatch(l) || _skip(l)) continue;
      final same = _amount.allMatches(l).toList();
      if (same.isNotEmpty) {
        last = (_fils(same.last), true);
        continue;
      }
      for (var j = i + 1; j < lines.length && j <= i + 3; j++) {
        if (_onlyCurrency.hasMatch(lines[j])) continue;
        if (_onlyAmount.hasMatch(lines[j])) {
          last = (_fils(_amount.firstMatch(lines[j])!), false);
          break;
        }
        if (!keyword.hasMatch(lines[j]) && !_grandTotal.hasMatch(lines[j])) {
          break;
        }
      }
    }
    return last;
  }

  int? _largest(List<String> lines) {
    int? best;
    for (final l in lines) {
      if (_skip(l)) continue;
      for (final m in _amount.allMatches(l)) {
        final f = _fils(m);
        if (f > 0 && (best == null || f > best)) best = f;
      }
    }
    return best;
  }

  static String? _currency(String text) {
    final t = text.toUpperCase();
    if (RegExp(r'\bBHD\b|\bBD\b|د\.?\s?ب|دينار').hasMatch(t)) return 'BHD';
    if (RegExp(r'\bUSD\b|\$').hasMatch(t)) return 'USD';
    if (RegExp(r'\bSAR\b|ريال').hasMatch(t)) return 'SAR';
    if (RegExp(r'\bAED\b|درهم').hasMatch(t)) return 'AED';
    if (RegExp(r'\bEUR\b|€').hasMatch(t)) return 'EUR';
    return null;
  }

  /// The printed date and time (Bahrain time) as UTC; null when there is no
  /// usable date. A date far from [now] is treated as misread.
  static DateTime? _dateTime(String text, DateTime now) {
    int? y, mo, d;
    final dmy = RegExp(r'(?<!\d)(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{4}|\d{2})(?!\d)')
        .firstMatch(text);
    final ymd = RegExp(r'(?<!\d)(\d{4})[/\-.](\d{1,2})[/\-.](\d{1,2})(?!\d)')
        .firstMatch(text);
    if (ymd != null) {
      y = int.parse(ymd[1]!);
      mo = int.parse(ymd[2]!);
      d = int.parse(ymd[3]!);
    } else if (dmy != null) {
      d = int.parse(dmy[1]!);
      mo = int.parse(dmy[2]!);
      y = int.parse(dmy[3]!);
      if (y < 100) y += 2000;
    }
    if (y == null || mo! < 1 || mo > 12 || d! < 1 || d > 31) return null;
    var h = 12, mi = 0;
    final time = RegExp(r'(?<!\d)(\d{1,2}):(\d{2})(?::\d{2})?\s*(am|pm|ص|م)?(?![\d])',
            caseSensitive: false, unicode: true)
        .firstMatch(text);
    if (time != null) {
      h = int.parse(time[1]!);
      mi = int.parse(time[2]!);
      final ap = time[3]?.toLowerCase();
      if ((ap == 'pm' || ap == 'م') && h < 12) h += 12;
      if ((ap == 'am' || ap == 'ص') && h == 12) h = 0;
      if (h > 23 || mi > 59) {
        h = 12;
        mi = 0;
      }
    }
    final at = DateTime.utc(y, mo, d, h, mi).subtract(kBahrainOffset);
    final diff = at.difference(now.toUtc());
    if (diff > const Duration(days: 1) || diff < const Duration(days: -400)) {
      return null;
    }
    return at;
  }

  String? _shop(List<String> lines) {
    for (final l in lines.take(4)) {
      final letters = RegExp(r'[A-Za-z؀-ۿ]').allMatches(l).length;
      if (letters < 3) continue;
      if (_notShop.hasMatch(l) || _amount.hasMatch(l)) continue;
      return l.replaceAll(RegExp(r'\s+'), ' ');
    }
    return null;
  }
}

/// Stored as the result's template version, so receipts can be told apart.
const String kReceiptReaderVersion = 'receipt-2026-11-04';
