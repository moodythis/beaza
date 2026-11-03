import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/foundation.dart';

/// One Bahrain day of the history, newest first.
class HistoryDay {
  const HistoryDay(this.day, this.entries, this.spentFils);

  final Day day;

  /// Newest first.
  final List<LedgerEntry> entries;

  /// Counted spending of the day, in BHD.
  final int spentFils;
}

/// Every transaction, by day. Copies and unreadable messages are left out.
class HistoryViewModel extends ChangeNotifier {
  HistoryViewModel({required LedgerRepository ledger}) : _ledger = ledger {
    _ledger.addListener(load);
  }

  final LedgerRepository _ledger;

  List<HistoryDay> _days = const [];
  List<HistoryDay> get days => _days;

  bool _loaded = false;
  bool get loaded => _loaded;

  bool _disposed = false;

  Future<void> load() async {
    final entries = await _ledger.entries();
    final byDay = <String, List<LedgerEntry>>{};
    final dayOf = <String, Day>{};
    for (final e in entries) {
      final t = e.result.timestamp;
      if (t == null) continue;
      if (e.role != EntryRole.spending &&
          e.role != EntryRole.income &&
          e.role != EntryRole.internalTransfer) {
        continue;
      }
      final d = Day.of(t);
      dayOf[d.toString()] = d;
      (byDay[d.toString()] ??= []).add(e);
    }
    final keys = byDay.keys.toList()..sort((a, b) => b.compareTo(a));
    _days = [
      for (final k in keys)
        HistoryDay(
          dayOf[k]!,
          (byDay[k]!..sort((a, b) =>
                  b.result.timestamp!.compareTo(a.result.timestamp!))),
          Reconciler.spentFils(byDay[k]!.where((e) => e.countsTowardSpending)),
        ),
    ];
    _loaded = true;
    if (!_disposed) notifyListeners();
  }

  Future<void> setCategory(LedgerEntry entry, String category) =>
      _ledger.setCategory(entry, category);

  @override
  void dispose() {
    _disposed = true;
    _ledger.removeListener(load);
    super.dispose();
  }
}
