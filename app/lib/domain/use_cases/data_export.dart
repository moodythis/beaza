import 'dart:convert';

import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/device_service.dart';
import 'package:beaza_extraction/beaza_extraction.dart';

/// Gives the person a copy of their data (SRS FR-1.7, GDPR Art. 20): every
/// transaction and the settings, as one JSON file saved where they choose.
/// Nothing is sent anywhere; works with or without an account.
class DataExport {
  DataExport({
    required LedgerRepository ledger,
    required SettingsRepository settings,
    required DeviceService device,
    DateTime Function()? clock,
  })  : _ledger = ledger,
        _settings = settings,
        _device = device,
        _clock = clock ?? DateTime.now;

  final LedgerRepository _ledger;
  final SettingsRepository _settings;
  final DeviceService _device;
  final DateTime Function() _clock;

  /// Bumped when the file layout changes.
  static const int version = 1;

  /// The file's contents. Amounts are in fils (integers) and as text with
  /// three decimals; no floating point (NFR-1).
  Future<Map<String, Object?>> build() async {
    final entries = await _ledger.entries();
    final s = await _settings.load();
    return {
      'format': 'beaza-export',
      'version': version,
      'exportedAt': _clock().toUtc().toIso8601String(),
      'settings': {
        'dailyLimitFils': s.dailyLimitFils,
        'microThresholdFils': s.microThresholdFils,
        'alertCap': s.alertCap,
        'microCountForTotal': s.microCountForTotal,
        'rollover': s.rollover,
        'rolloverCapPercent': s.rolloverCapPercent,
      },
      'transactions': [for (final e in entries) _entry(e)],
    };
  }

  /// For example `beaza-export-2026-11-03.json` (the Bahrain date).
  String fileName() {
    final d = Day.of(_clock());
    String two(int n) => n.toString().padLeft(2, '0');
    return 'beaza-export-${d.year}-${two(d.month)}-${two(d.day)}.json';
  }

  /// Asks where to save the file. True when saved, false when cancelled.
  Future<bool> save() async => _device.saveText(
        fileName: fileName(),
        text: const JsonEncoder.withIndent('  ').convert(await build()),
      );

  static Map<String, Object?> _entry(LedgerEntry e) {
    final r = e.result;
    final fils = r.amountFils;
    return {
      'amountFils': fils,
      'amount': fils == null ? null : amountText(fils),
      'currency': r.currency,
      'type': r.type?.name,
      'direction': r.direction.name,
      'role': e.role.name,
      'countsTowardSpending': e.countsTowardSpending,
      'merchant': r.merchantRaw,
      'merchantNormalized': r.merchantNorm,
      'category': r.category,
      'channel': r.channel?.name,
      'cardLast4': r.last4,
      'counterpartyLast4': r.counterpartyLast4,
      'reference': r.reference,
      'time': r.timestamp?.toUtc().toIso8601String(),
      'source': r.templateVersion == InMemoryLedgerRepository.manualTemplate
          ? 'manual'
          : 'message',
      'template': r.templateVersion,
      'confidence': r.confidence,
    };
  }

  /// 1250 -> "1.250"; -5 -> "-0.005".
  static String amountText(int fils) {
    final sign = fils < 0 ? '-' : '';
    final abs = fils.abs();
    return '$sign${abs ~/ 1000}.${(abs % 1000).toString().padLeft(3, '0')}';
  }
}
