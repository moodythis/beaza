import 'dart:convert';

import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:flutter/foundation.dart';

class Redemption {
  const Redemption(this.offerId, this.code, this.cost, this.at);

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
}
