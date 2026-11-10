import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/rewards_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/rewards.dart' as rw;
import 'package:beaza/domain/use_cases/rewards.dart' show DemoOffer, kDemoOffers, rankOffers;
import 'package:beaza/domain/use_cases/daily_close.dart';
import 'package:beaza/domain/use_cases/leaderboard.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza/domain/use_cases/streak.dart';
import 'package:beaza/ui/features/savings/view_models/leaderboard_sync.dart';
import 'package:beaza/domain/use_cases/subscriptions.dart';
import 'package:beaza_extraction/beaza_extraction.dart' show Day;
import 'package:flutter/foundation.dart';

/// Savings goal, cooling-off holds and repeating charges.
class SavingsViewModel extends ChangeNotifier {
  SavingsViewModel({
    required this.repo,
    required LedgerRepository ledger,
    this.rewards,
    this.board,
    SettingsRepository? settings,
    DateTime Function()? clock,
  })  : _ledger = ledger,
        _settings = settings,
        _clock = clock ?? DateTime.now {
    repo.addListener(load);
    _ledger.addListener(load);
    rewards?.addListener(load);
  }

  /// Demo points and offers; null hides them.
  final RewardsRepository? rewards;
  final SettingsRepository? _settings;

  int pointsEarned = 0;
  List<Redemption> redeemed = const [];
  List<DemoOffer> offers = kDemoOffers;
  bool personalOffers = false;

  /// Finished days in a row within the limit (a frozen day is skipped).
  int streak = 0;

  /// A streak freeze is held, ready for the next day over the limit.
  bool freezeHeld = false;

  /// The day the freeze was just used on (to tell the person once).
  Day? freezeUsedOn;

  /// The nickname chosen for the board; null shows the persona title.
  String? nickname;

  /// This phone's persona number.
  int boardNumber = 100;

  /// The online board's opt-in and state; null hides the switch.
  final LeaderboardSync? board;

  /// The board to show: the online one when joined and fetched, else the
  /// practice board with this phone's row in it.
  List<BoardRow> get boardRows {
    final online = board?.rows;
    if (online != null) return online;
    return rankBoard([
      ...practiceBoard(Day.of(_clock())),
      BoardRow(
        points: pointsEarned,
        streak: streak,
        number: boardNumber,
        nickname: nickname,
        me: true,
      ),
    ]);
  }

  bool get boardOnline => board?.rows != null;

  /// Joins the online board (the person agreed on the card).
  Future<void> joinBoard() async {
    await board?.join();
    await load();
  }

  /// Leaves it: the row is deleted on the server and this phone gets a
  /// new id for next time.
  Future<void> leaveBoard() async {
    final b = board;
    final r = rewards;
    if (b == null || r == null) return;
    await b.leave(await r.boardId());
    await r.forgetBoardId();
    await load();
  }

  /// Buys a streak freeze for [kFreezeCost] points. False when one is
  /// held already or the points are not enough.
  Future<bool> buyFreeze() async {
    final r = rewards;
    if (r == null || freezeHeld || pointsBalance < kFreezeCost) return false;
    final bought = await r.buyFreeze(kFreezeCost);
    if (bought) await load();
    return bought;
  }

  /// Sets or clears the nickname. Returns the problem, or null when saved.
  Future<NicknameProblem?> setNickname(String? raw) async {
    final r = rewards;
    if (r == null) return null;
    if (raw == null) {
      await r.setNickname(null);
      await load();
      return null;
    }
    final problem = nicknameProblem(raw);
    if (problem != null) return problem;
    await r.setNickname(tidyNickname(raw));
    await load();
    return null;
  }

  int get pointsBalance =>
      pointsEarned - redeemed.fold(0, (a, r) => a + r.cost);

  /// Redeems [offer] if there are enough points; returns the code.
  Future<String?> redeem(DemoOffer offer) async {
    final r = rewards;
    if (r == null || pointsBalance < offer.cost) return null;
    final code = offer.codeFor(redeemed.length + 1);
    await r.redeem(offer.id, code, offer.cost);
    return code;
  }

  final SavingsRepository repo;
  final LedgerRepository _ledger;
  final DateTime Function() _clock;

  DateTime now() => _clock();

  List<Hold> holds = const [];
  Goal? goal;
  List<Subscription> subscriptions = const [];
  bool loaded = false;
  bool _disposed = false;

  Future<void> _queue = Future.value();

  /// Works everything out again. One run at a time: a change that arrives
  /// while a run is going waits for it, so the online board never gets the
  /// same score twice.
  Future<void> load() {
    final run = _queue.then((_) => _load());
    _queue = run.then((_) {}, onError: (Object _) {});
    return run;
  }

  Future<void> _load() async {
    await board?.load();
    holds = await repo.holds();
    goal = await repo.goal();
    final entries = await _ledger.entries();
    subscriptions = withManual(findSubscriptions(entries),
        await repo.manualSubscriptions(), Day.of(_clock()));
    final r = rewards;
    final s = _settings;
    if (r != null && s != null) {
      final today = Day.of(_clock());
      final settings = await s.load();
      pointsEarned = rw.pointsEarned(entries, settings, holds, today,
          sweeps: sweepsInLast30(await repo.closes(), today));
      // The streak, with the freeze used at once on the day that needs it.
      final streakNow = streakWithFreeze(
        entries,
        today,
        settings.dailyLimitFils,
        limitOn: await repo.limitHistory(),
        frozen: await r.frozenDays(),
        freezeBoughtOn: await r.freezeBoughtOn(),
      );
      if (streakNow.usedOn != null) await r.useFreeze(streakNow.usedOn!);
      streak = streakNow.days;
      freezeHeld = streakNow.freezeHeld;
      freezeUsedOn = streakNow.usedOn ?? freezeUsedOn;
      nickname = await r.nickname();
      boardNumber = personaNumber(await r.boardId());
      redeemed = await r.redeemed();
      personalOffers = await r.personal();
      offers = rankOffers(
        spendingByCategory(entries, today.addDays(-6), today),
        personal: personalOffers,
      );
    }
    loaded = true;
    if (!_disposed) notifyListeners();
    // The online board gets the new score after the screen is drawn.
    final b = board;
    if (b != null && b.joined && rewards != null) {
      final changed = await b.push(
        boardId: await rewards!.boardId(),
        nickname: nickname,
        points: pointsEarned,
        streak: streak,
      );
      if (changed && !_disposed) notifyListeners();
    }
  }

  Future<void> addSubscription(
          String name, int amountFils, bool weekly, Day lastPaid) =>
      repo.addSubscription(name, amountFils, weekly, lastPaid);

  Future<void> removeSubscription(String id) => repo.removeSubscription(id);

  List<Hold> get waiting => [for (final h in holds) if (h.decision == null) h];
  List<Hold> get decided => [for (final h in holds) if (h.decision != null) h];

  int get goalSaved => goal == null ? 0 : goalSavedFils(goal!, holds);
  int get skippedTotal => skippedFils(holds);
  int get subscriptionsMonthly =>
      subscriptions.fold(0, (a, s) => a + s.monthlyFils);

  @override
  void dispose() {
    _disposed = true;
    repo.removeListener(load);
    _ledger.removeListener(load);
    rewards?.removeListener(load);
    super.dispose();
  }
}
