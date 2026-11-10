import 'dart:convert';

import 'package:beaza/data/services/hold_reminders.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/domain/use_cases/daily_close.dart';
import 'package:beaza/domain/use_cases/subscriptions.dart';
import 'package:beaza_extraction/beaza_extraction.dart' show Day;
import 'package:flutter/foundation.dart';

/// A purchase put on hold for [kCoolingOff] before deciding (درع التريث).
@immutable
class Hold {
  const Hold({
    required this.id,
    required this.name,
    required this.amountFils,
    required this.createdAt,
    this.decision,
    this.decidedAt,
  });

  final String id;
  final String name;
  final int amountFils;
  final DateTime createdAt;

  /// Null while waiting, then 'bought' or 'skipped'.
  final String? decision;
  final DateTime? decidedAt;

  bool readyAt(DateTime now) => !now.isBefore(createdAt.add(kCoolingOff));

  Duration leftAt(DateTime now) {
    final left = createdAt.add(kCoolingOff).difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  Hold decide(String d, DateTime at) => Hold(
        id: id,
        name: name,
        amountFils: amountFils,
        createdAt: createdAt,
        decision: d,
        decidedAt: at,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'fils': amountFils,
        'at': createdAt.toUtc().toIso8601String(),
        'decision': decision,
        'decidedAt': decidedAt?.toUtc().toIso8601String(),
      };

  static Hold fromJson(Map<String, Object?> j) => Hold(
        id: j['id']! as String,
        name: j['name']! as String,
        amountFils: j['fils']! as int,
        createdAt: DateTime.parse(j['at']! as String),
        decision: j['decision'] as String?,
        decidedAt: j['decidedAt'] == null
            ? null
            : DateTime.parse(j['decidedAt']! as String),
      );
}

const Duration kCoolingOff = Duration(hours: 24);

/// One savings goal (for example an iPad).
@immutable
class Goal {
  const Goal({
    required this.name,
    required this.targetFils,
    required this.createdAt,
    this.addedFils = 0,
  });

  final String name;
  final int targetFils;
  final DateTime createdAt;

  /// Money the person said they put aside.
  final int addedFils;

  Map<String, Object?> toJson() => {
        'name': name,
        'target': targetFils,
        'at': createdAt.toUtc().toIso8601String(),
        'added': addedFils,
      };

  static Goal fromJson(Map<String, Object?> j) => Goal(
        name: j['name']! as String,
        targetFils: j['target']! as int,
        createdAt: DateTime.parse(j['at']! as String),
        addedFils: (j['added'] as int?) ?? 0,
      );
}

/// Holds and the goal, on this phone only (in the encrypted local
/// database's preferences; not synced).
class SavingsRepository extends ChangeNotifier {
  SavingsRepository(this._prefs, {DateTime Function()? clock, this.reminders})
      : _clock = clock ?? DateTime.now;

  /// Reminds when a hold's 24 hours are up; null in tests.
  final HoldReminders? reminders;

  static const String holdsKey = 'holds.v1';
  static const String goalKey = 'goal.v1';
  static const String subsKey = 'subs.manual.v1';
  static const String closesKey = 'closes.v1';
  static const String limitsKey = 'limits.v1';

  /// Days kept in the close list and the limit history.
  static const int keptDays = 90;

  final PreferencesStore _prefs;
  final DateTime Function() _clock;

  Future<List<Hold>> holds() async {
    final raw = await _prefs.read(holdsKey);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          Hold.fromJson((j as Map).cast<String, Object?>()),
      ];
    } on Object {
      return [];
    }
  }

  Future<void> _saveHolds(List<Hold> list) async {
    await _prefs.write(
        holdsKey, jsonEncode([for (final h in list) h.toJson()]));
    notifyListeners();
  }

  Future<Hold> addHold(String name, int amountFils) async {
    if (amountFils <= 0) throw ArgumentError.value(amountFils, 'amountFils');
    final now = _clock();
    final hold = Hold(
      id: now.microsecondsSinceEpoch.toString(),
      name: name.trim(),
      amountFils: amountFils,
      createdAt: now,
    );
    await _saveHolds([...await holds(), hold]);
    try {
      await reminders?.schedule(hold);
    } on Object {
      // A reminder that cannot be set never stops the hold.
    }
    return hold;
  }

  /// 'bought' or 'skipped'. Only after the waiting time is over.
  Future<void> decide(String id, String decision) async {
    if (decision != 'bought' && decision != 'skipped') {
      throw ArgumentError.value(decision, 'decision');
    }
    final now = _clock();
    final list = await holds();
    for (final h in list) {
      if (h.id == id) await _cancel(h);
    }
    await _saveHolds([
      for (final h in list)
        if (h.id == id && h.decision == null && h.readyAt(now))
          h.decide(decision, now)
        else
          h,
    ]);
  }

  Future<void> removeHold(String id) async {
    final list = await holds();
    for (final h in list) {
      if (h.id == id) await _cancel(h);
    }
    await _saveHolds([for (final h in list) if (h.id != id) h]);
  }

  Future<void> _cancel(Hold h) async {
    try {
      await reminders?.cancel(h);
    } on Object {
      // Nothing to cancel, or no platform: fine.
    }
  }

  Future<Goal?> goal() async {
    final raw = await _prefs.read(goalKey);
    if (raw == null) return null;
    try {
      return Goal.fromJson((jsonDecode(raw) as Map).cast<String, Object?>());
    } on Object {
      return null;
    }
  }

  Future<void> setGoal(String name, int targetFils) async {
    if (targetFils <= 0) throw ArgumentError.value(targetFils, 'targetFils');
    final old = await goal();
    final g = Goal(
      name: name.trim(),
      targetFils: targetFils,
      createdAt: old?.createdAt ?? _clock(),
      addedFils: old?.addedFils ?? 0,
    );
    await _prefs.write(goalKey, jsonEncode(g.toJson()));
    notifyListeners();
  }

  Future<void> addToGoal(int fils) async {
    final g = await goal();
    if (g == null || fils <= 0) return;
    final next = Goal(
      name: g.name,
      targetFils: g.targetFils,
      createdAt: g.createdAt,
      addedFils: g.addedFils + fils,
    );
    await _prefs.write(goalKey, jsonEncode(next.toJson()));
    notifyListeners();
  }

  Future<void> clearGoal() async {
    await _prefs.write(goalKey, null);
    notifyListeners();
  }

  /// Closed days (the daily close), oldest first.
  Future<List<DayClose>> closes() async {
    final raw = await _prefs.read(closesKey);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          DayClose.fromJson((j as Map).cast<String, Object?>()),
      ];
    } on Object {
      return [];
    }
  }

  /// Records that [close.day] was closed. A day is closed once: a second
  /// close of the same day is ignored and returns false.
  Future<bool> addClose(DayClose close) async {
    final list = await closes();
    if (list.any((c) => c.day == close.day)) return false;
    list.add(close);
    final from = Day.of(_clock()).addDays(-keptDays);
    list.removeWhere((c) => c.day.compareTo(from) < 0);
    await _prefs.write(
        closesKey, jsonEncode([for (final c in list) c.toJson()]));
    notifyListeners();
    return true;
  }

  /// The limit the app showed on each of the last [keptDays] days it was
  /// opened.
  Future<Map<Day, int>> limitHistory() async {
    final raw = await _prefs.read(limitsKey);
    if (raw == null) return {};
    try {
      return {
        for (final MapEntry(:key, :value) in (jsonDecode(raw) as Map).entries)
          parseDayKey(key as String): value as int,
      };
    } on Object {
      return {};
    }
  }

  /// Remembers [day]'s limit and returns the history. Does not notify:
  /// nothing on screen depends on it by itself.
  Future<Map<Day, int>> recordLimit(Day day, int limitFils) async {
    final map = await limitHistory();
    if (limitFils <= 0 || map[day] == limitFils) return map;
    map[day] = limitFils;
    final from = day.addDays(-keptDays);
    map.removeWhere((d, _) => d.compareTo(from) < 0);
    await _prefs.write(limitsKey,
        jsonEncode({for (final e in map.entries) dayKey(e.key): e.value}));
    return map;
  }

  Future<List<ManualSubscription>> manualSubscriptions() async {
    final raw = await _prefs.read(subsKey);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          ManualSubscription.fromJson((j as Map).cast<String, Object?>()),
      ];
    } on Object {
      return [];
    }
  }

  Future<void> addSubscription(
      String name, int amountFils, bool weekly, Day lastPaid) async {
    if (amountFils <= 0) throw ArgumentError.value(amountFils, 'amountFils');
    final list = await manualSubscriptions();
    list.add(ManualSubscription(
      id: _clock().microsecondsSinceEpoch.toString(),
      name: name.trim(),
      amountFils: amountFils,
      weekly: weekly,
      lastPaid: lastPaid,
    ));
    await _prefs.write(subsKey, jsonEncode([for (final m in list) m.toJson()]));
    notifyListeners();
  }

  Future<void> removeSubscription(String id) async {
    final list = await manualSubscriptions()
      ..removeWhere((m) => m.id == id);
    await _prefs.write(subsKey,
        list.isEmpty ? null : jsonEncode([for (final m in list) m.toJson()]));
    notifyListeners();
  }
}

/// What the goal has so far: money put aside, plus purchases skipped after
/// waiting since the goal was set.
int goalSavedFils(Goal goal, List<Hold> holds) {
  final skipped = holds
      .where((h) =>
          h.decision == 'skipped' &&
          h.decidedAt != null &&
          !h.decidedAt!.isBefore(goal.createdAt))
      .fold<int>(0, (a, h) => a + h.amountFils);
  return goal.addedFils + skipped;
}

/// Everything skipped after waiting: money not spent thanks to the timer.
int skippedFils(List<Hold> holds) => holds
    .where((h) => h.decision == 'skipped')
    .fold<int>(0, (a, h) => a + h.amountFils);
