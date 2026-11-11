import 'dart:convert';
import 'dart:math';

import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/domain/use_cases/daily_close.dart';
import 'package:beaza_extraction/beaza_extraction.dart' show Day;
import 'package:flutter/foundation.dart';

/// How long a demo voucher stays usable after it is redeemed.
const Duration kVoucherLife = Duration(days: 7);

class Redemption {
  const Redemption(this.offerId, this.code, this.cost, this.at);

  DateTime get expiresAt => at.add(kVoucherLife);

  bool activeAt(DateTime now) => now.isBefore(expiresAt);

  /// Whole days left (rounded up); 0 once it has expired.
  int daysLeft(DateTime now) {
    final left = expiresAt.difference(now);
    if (left <= Duration.zero) return 0;
    return (left.inMinutes + 24 * 60 - 1) ~/ (24 * 60);
  }

  final String offerId;
  final String code;
  final int cost;
  final DateTime at;

  Map<String, Object?> toJson() =>
      {'offer': offerId, 'code': code, 'cost': cost, 'at': at.toUtc().toIso8601String()};

  static Redemption fromJson(Map<String, Object?> j) => Redemption(
      j['offer']! as String, j['code']! as String, j['cost']! as int,
      DateTime.parse(j['at']! as String));
}

/// Redeemed demo offers and the "offers by my spending" switch, on this
/// phone only.
class RewardsRepository extends ChangeNotifier {
  RewardsRepository(this._prefs, {DateTime Function()? clock})
      : _clock = clock ?? DateTime.now;

  static const String redeemedKey = 'rewards.v1';
  static const String personalKey = 'offersPersonal';
  static const String freezeKey = 'streak.freeze';
  static const String frozenKey = 'streak.frozen';
  static const String boardIdKey = 'board.id';
  static const String nicknameKey = 'board.nickname';

  /// The offer id a streak freeze is recorded under among the redemptions.
  static const String freezeOffer = 'streak-freeze';

  final PreferencesStore _prefs;
  final DateTime Function() _clock;

  Future<List<Redemption>> redeemed() async {
    final raw = await _prefs.read(redeemedKey);
    if (raw == null) return [];
    try {
      return [
        for (final j in jsonDecode(raw) as List)
          Redemption.fromJson((j as Map).cast<String, Object?>()),
      ];
    } on Object {
      return [];
    }
  }

  Future<void> redeem(String offerId, String code, int cost) async {
    final list = [...await redeemed(), Redemption(offerId, code, cost, _clock())];
    await _prefs.write(redeemedKey, jsonEncode([for (final r in list) r.toJson()]));
    notifyListeners();
  }

  Future<bool> personal() async => await _prefs.read(personalKey) == 'on';

  Future<void> setPersonal(bool on) async {
    await _prefs.write(personalKey, on ? 'on' : null);
    notifyListeners();
  }

  /// The Bahrain day the held streak freeze was bought on; null when none
  /// is held.
  Future<Day?> freezeBoughtOn() async {
    final raw = await _prefs.read(freezeKey);
    try {
      return raw == null ? null : parseDayKey(raw);
    } on Object {
      return null;
    }
  }

  /// Buys a freeze for [cost] points. One at a time: false when one is
  /// already held.
  Future<bool> buyFreeze(int cost) async {
    if (await freezeBoughtOn() != null) return false;
    final now = _clock();
    await _prefs.write(freezeKey, dayKey(Day.of(now)));
    final list = [...await redeemed(), Redemption(freezeOffer, '', cost, now)];
    await _prefs.write(redeemedKey, jsonEncode([for (final r in list) r.toJson()]));
    notifyListeners();
    return true;
  }

  /// Days over the limit that a freeze covered.
  Future<Set<Day>> frozenDays() async {
    final raw = await _prefs.read(frozenKey);
    if (raw == null) return {};
    try {
      return {for (final d in jsonDecode(raw) as List) parseDayKey(d as String)};
    } on Object {
      return {};
    }
  }

  /// The held freeze was used on [day]. Does not notify: it is written
  /// while the screen is being worked out.
  Future<void> useFreeze(Day day) async {
    final days = await frozenDays()..add(day);
    await _prefs.write(frozenKey, jsonEncode([for (final d in days) dayKey(d)]));
    await _prefs.write(freezeKey, null);
  }

  /// This phone's random board id, made the first time it is asked for.
  /// It is linked to nothing: not the account, not the e-mail.
  Future<String> boardId() async {
    final had = await _prefs.read(boardIdKey);
    if (had != null && had.length >= 16) return had;
    final r = Random.secure();
    final id = [
      for (var i = 0; i < 16; i++) r.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ].join();
    await _prefs.write(boardIdKey, id);
    return id;
  }

  /// A fresh board id (after leaving the online board).
  Future<void> forgetBoardId() => _prefs.write(boardIdKey, null);

  /// The nickname shown on the board; null means the persona title.
  Future<String?> nickname() => _prefs.read(nicknameKey);

  Future<void> setNickname(String? name) async {
    await _prefs.write(nicknameKey, name);
    notifyListeners();
  }
}
