import 'dart:convert';

import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/weekly_challenge.dart';
import 'package:beaza/ui/features/challenge/view_models/challenge_view_model.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter_test/flutter_test.dart';

// "today" is 14 Nov 2026; the last 7 days are 8-14 Nov.
const today = Day(2026, 11, 14);

DateTime bh(int day, [int hour = 12]) =>
    DateTime.utc(2026, 11, day, hour).subtract(kBahrainOffset);

int _n = 0;
ExtractionResult tx(int fils, DateTime at, {String? shop, String? category}) =>
    ExtractionResult(
      status: ExtractionStatus.transaction,
      amountFils: fils,
      currency: 'BHD',
      type: TxnType.purchase,
      direction: TxDirection.outgoing,
      merchantRaw: shop,
      category: category,
      reference: 'C${_n++}',
      timestamp: at,
    );

List<LedgerEntry> ledger(List<ExtractionResult> rs) =>
    const Reconciler().reconcile(rs, OwnAccounts());

void main() {
  group('the suggestion comes from last week\'s weak spot', () {
    test('a shop visited 5 times: at most 3 visits', () {
      final c = suggestChallenge(
          ledger([for (var d = 8; d <= 12; d++) tx(2000, bh(d), shop: 'COSTA')]),
          today)!;
      expect(c.kind, ChallengeKind.shop);
      expect(c.shop, 'COSTA');
      expect(c.target, 3);
      expect(c.savingFils, 4000); // two visits of 2.000
    });

    test('late nights: none for a week', () {
      final c = suggestChallenge(
          ledger([
            tx(1500, bh(9, 23)),
            tx(1200, bh(10, 1)),
            tx(1800, bh(11, 22)),
          ]),
          today)!;
      expect(c.kind, ChallengeKind.lateNight);
      expect(c.target, 0);
      expect(c.savingFils, 4500);
    });

    test('small purchases: half as many', () {
      final c = suggestChallenge(
          ledger([for (var d = 8; d <= 13; d++) tx(1000, bh(d), shop: 'S$d')]),
          today)!;
      expect(c.kind, ChallengeKind.small);
      expect(c.target, 3);
      expect(c.savingFils, 3000);
    });

    test('a big discretionary category: 20% less', () {
      final c = suggestChallenge(
          ledger([tx(12000, bh(10), category: 'shopping')]), today)!;
      expect(c.kind, ChallengeKind.category);
      expect(c.category, 'shopping');
      expect(c.target, 9600);
      expect(c.savingFils, 2400);
    });

    test('nothing stands out: no challenge', () {
      expect(suggestChallenge(ledger([tx(3000, bh(10), category: 'bills')]), today),
          isNull);
    });
  });

  test('progress counts only the challenge days', () {
    final c = const Challenge(
      kind: ChallengeKind.shop,
      shop: 'COSTA',
      target: 2,
      savingFils: 4000,
      start: Day(2026, 11, 10),
    );
    final entries = ledger([
      tx(2000, bh(9), shop: 'COSTA'), // before the start
      tx(2000, bh(10), shop: 'Costa'),
      tx(2000, bh(12), shop: 'COSTA 77'),
      tx(2000, bh(13), shop: 'COSTA'),
    ]);
    final p = challengeProgress(c, entries, today);
    expect(p.value, 3);
    expect(p.daysLeft, 3); // 14, 15, 16 Nov
    expect(p.finished, isFalse);
    expect(challengeKept(c, p), isFalse);

    final after = challengeProgress(c, entries, const Day(2026, 11, 17));
    expect(after.finished, isTrue);
    expect(after.daysLeft, 0);
  });

  test('a challenge reads back from what is saved', () {
    const c = Challenge(
      kind: ChallengeKind.category,
      category: 'food',
      target: 8000,
      savingFils: 2000,
      start: Day(2026, 11, 5),
    );
    final back = Challenge.fromJson(jsonDecode(jsonEncode(c.toJson())))!;
    expect(back.kind, c.kind);
    expect(back.category, 'food');
    expect(back.target, 8000);
    expect(back.start, const Day(2026, 11, 5));
    expect(Challenge.fromJson({'kind': 'nope'}), isNull);
  });

  test('the view model: suggest, accept today, then progress', () async {
    final prefs = MemoryPreferencesStore();
    final repo = InMemoryLedgerRepository(initial: [
      for (var d = 8; d <= 12; d++) tx(2000, bh(d), shop: 'COSTA'),
    ]);
    final vm = ChallengeViewModel(
      preferences: prefs,
      ledger: repo,
      settings: InMemorySettingsRepository(
          const GuardrailSettings(dailyLimitFils: 10000)),
      clock: () => bh(14),
    );
    await vm.load();
    expect(vm.active, isNull);
    expect(vm.suggestion!.kind, ChallengeKind.shop);

    await vm.accept();
    expect(vm.active!.start, today);
    expect(vm.progress!.value, 0);
    expect(vm.kept, isTrue);
    expect(prefs.values[ChallengeViewModel.prefName], isNotNull);

    await repo.addManual(amountFils: 2000, merchant: 'COSTA', at: bh(14, 16));
    await Future<void>.delayed(Duration.zero);
    await vm.load();
    expect(vm.progress!.value, 1);

    await vm.clear();
    expect(vm.active, isNull);
    vm.dispose();
  });
}
