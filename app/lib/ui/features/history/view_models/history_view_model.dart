import 'package:beaza/domain/use_cases/custom_categories.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/domain/use_cases/auto_categorize.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
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
  HistoryViewModel({
    required LedgerRepository ledger,
    bool unsortedOnly = false,
    this.autoSort,
  })  : _ledger = ledger,
        _unsortedOnly = unsortedOnly {
    _ledger.addListener(load);
  }

  final LedgerRepository _ledger;

  List<HistoryDay> _days = const [];
  List<HistoryDay> get days => _days;

  bool _loaded = false;
  bool get loaded => _loaded;

  bool _disposed = false;

  bool _unsortedOnly;

  /// AI sorting of shop names (FR-8.14); null hides it.
  final AutoCategorizer? autoSort;

  bool _autoSortOn = false;
  bool get autoSortOn => _autoSortOn;

  /// Turns AI sorting on (the person agreed) and sorts now. Returns how
  /// many shops got a category.
  Future<int> turnOnAutoSort() async {
    final a = autoSort;
    if (a == null) return 0;
    await a.turnOn();
    _autoSortOn = true;
    if (!_disposed) notifyListeners();
    final n = await a.run();
    await load();
    return n;
  }

  Future<void> turnOffAutoSort() async {
    await autoSort?.turnOff();
    _autoSortOn = false;
    if (!_disposed) notifyListeners();
  }

  /// Shows only purchases without a category, so they can be sorted.
  bool get unsortedOnly => _unsortedOnly;

  int _unsortedCount = 0;

  /// Purchases without a category, in the whole list.
  int get unsortedCount => _unsortedCount;

  Future<void> showUnsortedOnly(bool value) async {
    _unsortedOnly = value;
    await load();
  }

  static bool _unsorted(LedgerEntry e) =>
      e.role == EntryRole.spending && bucketOf(e.result) == kUnsortedBucket;

  Future<void> load() async {
    _autoSortOn = await autoSort?.isOn() ?? false;
    final all = await _ledger.entries();
    _unsortedCount = all.where(_unsorted).length;
    final entries = _unsortedOnly ? all.where(_unsorted) : all;
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

  /// The person's own categories, for the category list.
  Future<List<String>> customCategories() async =>
      customCategoriesIn(await _ledger.entries());

  Future<void> remove(LedgerEntry entry) => _ledger.remove(entry);

  Future<void> edit(LedgerEntry entry,
          {required int amountFils, String? merchant}) =>
      _ledger.edit(entry, amountFils: amountFils, merchant: merchant);

  @override
  void dispose() {
    _disposed = true;
    _ledger.removeListener(load);
    super.dispose();
  }
}
