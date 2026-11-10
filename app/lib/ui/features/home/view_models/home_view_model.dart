import 'dart:async';

import 'package:beaza/domain/use_cases/streak.dart';
import 'package:beaza/domain/use_cases/custom_categories.dart';
import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/auto_categorize.dart';
import 'package:beaza/domain/use_cases/daily_budget.dart' as daily;
import 'package:beaza/domain/use_cases/daily_budget.dart' show BudgetPlan, PurchaseCheck, safeDailyLimitFils;
import 'package:beaza/data/services/device_service.dart';
import 'package:beaza/data/services/media_ai_api.dart';
import 'package:beaza/data/services/receipt_scanner.dart';
import 'package:beaza/data/services/voice_input.dart';
import 'package:beaza/domain/use_cases/data_export.dart';
import 'package:beaza/domain/use_cases/message_intake.dart';
import 'package:beaza/ui/features/challenge/view_models/challenge_view_model.dart';
import 'package:beaza/ui/features/coach/view_models/coach_view_model.dart';
import 'package:beaza/ui/features/savings/view_models/savings_view_model.dart';
import 'package:beaza/domain/use_cases/savings_tips.dart';
import 'package:beaza/domain/use_cases/spending_by_category.dart';
import 'package:beaza_assistant/beaza_assistant.dart' show DraftTransaction, ExpenseParser;
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:beaza/domain/use_cases/day_pace.dart';
import 'package:flutter/foundation.dart';

/// What the home screen shows for one Bahrain day. Immutable snapshot.
@immutable
class HomeState {
  const HomeState({
    required this.summary,
    required this.today,
    required this.weekMicro,
    this.weekByCategory = const [],
    this.tips = const [],
    this.streakDays = 0,
    this.pace,
  });

  /// Today against the person's usual day; null with too little history.
  final DayPace? pace;

  final DaySummary summary;

  /// Today's counted spending, newest first.
  final List<LedgerEntry> today;
  final MicroStats weekMicro;

  /// Spending of the last 7 days per category, largest first.
  final List<CategoryTotal> weekByCategory;

  /// Saving tips from rules on this phone (empty when there is too little).
  final List<SavingsTip> tips;

  /// Days in a row, ending yesterday, within the limit.
  final int streakDays;
}

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required LedgerRepository ledger,
    required SettingsRepository settings,
    MessageIntake? intake,
    DeviceService? device,
    this.voice,
    this.receipts,
    this.coach,
    this.savings,
    this.challenge,
    this.autoSort,
    this.mediaAi,
    this.mediaConsent,
    this.recorder,
    this.export,
    PreferencesStore? preferences,
    DateTime Function()? clock,
    this.arrivalDelay = const Duration(seconds: 3),
  })  : _ledger = ledger,
        _settings = settings,
        _intake = intake,
        _device = device,
        _prefs = preferences,
        _clock = clock ?? DateTime.now {
    _ledger.addListener(load);
    _settings.addListener(load);
    // The SMS app writes the inbox a moment after the broadcast.
    _arrivals = _intake?.arrivals.listen(
      (_) => Future<void>.delayed(arrivalDelay, checkMessages),
      onError: (Object _) {},
    );
  }

  final LedgerRepository _ledger;
  final SettingsRepository _settings;
  final MessageIntake? _intake;
  final DeviceService? _device;
  final PreferencesStore? _prefs;
  final DateTime Function() _clock;

  /// Speech to text for quick add; null hides the microphone.
  final VoiceInput? voice;

  /// Goal, cooling-off and subscriptions; null hides its card.
  final SavingsViewModel? savings;

  /// This week's challenge; null hides its card.
  final ChallengeViewModel? challenge;

  /// AI sorting of shop names, run after new messages are read; null
  /// when not available.
  final AutoCategorizer? autoSort;

  /// Photos and voice read with AI, after a separate consent; null hides
  /// the switch.
  final MediaAiApi? mediaAi;
  final MediaAiConsent? mediaConsent;

  /// Records the voice for the AI (instead of the phone's speech service).
  final VoiceRecorder? recorder;

  /// For the questions screen.
  SettingsRepository get settings => _settings;

  /// The optional AI savings plan; null hides its card.
  final CoachViewModel? coach;

  /// Receipt photos to text on the phone; null hides the receipt button.
  final ReceiptScanner? receipts;

  /// The clock, for screens that work on the same "now" (receipts).
  DateTime now() => _clock();

  static const ExpenseParser _parser = ExpenseParser();

  /// Cash expenses in the person's words ("شريت كرك بربيتين وشاورما بـ 800
  /// فلس"): drafts to show for confirmation, nothing saved yet.
  List<DraftTransaction> draftsFrom(String text) => _parser.parse(text, _clock());

  /// Saves the drafts the person confirmed, at the time they confirm.
  Future<void> addDrafts(List<DraftTransaction> drafts) async {
    for (final d in drafts) {
      await _ledger.addManual(
        amountFils: d.amountFils,
        merchant: d.merchantRaw,
        at: d.timestamp,
        category: d.category,
      );
    }
  }

  /// For the history screen.
  LedgerRepository get ledger => _ledger;

  /// Saves a copy of the person's data (account screen); null hides it.
  final DataExport? export;
  final Duration arrivalDelay;
  StreamSubscription<void>? _arrivals;

  /// Null until checked, or when there is no SMS support (tests, other OS).
  bool? _smsAllowed;
  bool? get smsAllowed => _smsAllowed;

  /// True after the user refused the permission dialog in this session.
  bool _smsDenied = false;
  bool get smsDenied => _smsDenied;

  /// For the review screen; null when SMS reading is not available.
  MessageIntake? get intake => _intake;

  int _notUnderstood = 0;
  int get notUnderstood => _notUnderstood;

  bool _offerEarlier = false;

  /// Messages were just turned on: ask once whether to add earlier ones.
  bool get offerEarlier => _offerEarlier;

  /// What adding the last [days] days would bring in; nothing is stored.
  Future<EarlierPreview> previewEarlier(int days) =>
      _intake?.previewEarlier(days) ?? Future.value(const EarlierPreview());

  Future<void> addEarlier(int days) async {
    final intake = _intake;
    if (intake == null) return;
    _offerEarlier = false;
    _notUnderstood = (await intake.addEarlier(days)).notUnderstood;
    _notify();
  }

  Future<void> declineEarlier() async {
    _offerEarlier = false;
    await _intake?.declineEarlier();
    _notify();
  }

  bool _batteryRestricted = false;

  /// True when battery saving may stop Beaza while it is closed, so bank
  /// messages are read and alerts shown late. Checked with the messages.
  bool get batteryRestricted => _batteryRestricted;

  int _duplicates = 0;

  /// Transactions that repeat an earlier one read from the same message.
  int get duplicates => _duplicates;

  HomeState? _state;
  HomeState? get state => _state;

  bool _loading = false;
  bool get isLoading => _loading;

  Object? _error;
  Object? get error => _error;

  bool _disposed = false;

  /// Recomputes everything from the ledger (FR-5.1), so an edit or a
  /// deletion can move the day back to a lower alert state.
  Future<void> load() async {
    _loading = true;
    _notify();
    try {
      final entries = await _ledger.entries();
      _duplicates = await _ledger.countDuplicates();
      var settings = await _settings.load();
      _budget = await _readBudget();
      final plan = _budget;
      if (plan != null) {
        // The limit follows the month: each day it is worked out again from
        // what is left, so yesterday's overspending is already in it.
        final fils = safeDailyLimitFils(plan, entries, Day.of(_clock()));
        if (fils != settings.dailyLimitFils) {
          settings = settings.copyWith(dailyLimitFils: fils);
          await _settings.save(settings);
        }
      }
      final guardrail = Guardrail(settings);
      final day = Day.of(_clock());
      final summary = guardrail.summarize(entries, day);
      _state = HomeState(
        summary: summary,
        pace: dayPace(entries, _clock(), limitFils: summary.limitFils),
        today: guardrail.spendingOn(entries, day).reversed.toList(),
        weekMicro: guardrail.weeklyMicro(entries, day),
        weekByCategory: spendingByCategory(entries, day.addDays(-6), day),
        tips: savingsTips(entries, day,
            dailyLimitFils: settings.dailyLimitFils,
            microThresholdFils: settings.microThresholdFils),
        streakDays: streakDays(entries, day, settings.dailyLimitFils),
      );
      _error = null;
    } on Exception catch (e) {
      _error = e;
    } finally {
      _loading = false;
      _notify();
    }
  }

  /// Changes the category of one transaction (the person tapped it).
  Future<void> setCategory(LedgerEntry entry, String category) =>
      _ledger.setCategory(entry, category);

  /// Reads new bank messages if allowed. Called at start, on resume and
  /// when an SMS arrives. Also checks battery saving, which decides whether
  /// messages are read while the app is closed.
  Future<void> checkMessages() async {
    if (_disposed) return;
    await _checkBattery();
    final intake = _intake;
    if (intake == null) {
      _notify();
      return;
    }
    try {
      _smsAllowed = await intake.hasPermission();
      if (_smsAllowed == true) {
        _notUnderstood = (await intake.scan()).notUnderstood;
        _offerEarlier = await intake.offersEarlier();
        // Only does something once the person turned it on.
        await autoSort?.run();
      }
    } on Exception {
      // Reading SMS is a convenience: a failure must not break the screen.
    }
    _notify();
  }

  Future<void> enableMessages() async {
    final intake = _intake;
    if (intake == null) return;
    try {
      _smsAllowed = await intake.requestPermission();
    } on Exception {
      _smsAllowed = false;
    }
    _smsDenied = _smsAllowed != true;
    _notify();
    if (_smsAllowed == true) await checkMessages();
  }

  Future<void> _checkBattery() async {
    final device = _device;
    if (device == null) return;
    try {
      _batteryRestricted = await device.batteryRestricted() ?? false;
    } on Exception {
      _batteryRestricted = false;
    }
  }

  /// Opens Beaza's page in the phone's settings. The card goes away when the
  /// person comes back (the app re-checks on resume).
  Future<void> openBatterySettings() async {
    try {
      await _device?.openAppSettings();
    } on Exception {
      // Nothing to do: the card stays and the person can try again.
    }
  }

  /// Removes the repeats; the ledger notifies, so the screen recomputes.
  Future<int> removeDuplicates() => _ledger.removeDuplicates();

  Future<void> addExpense({
    required int amountFils,
    String? merchant,
    String? category,
  }) =>
      _ledger.addManual(
        amountFils: amountFils,
        merchant: merchant,
        at: _clock(),
        category: category,
      );

  /// The person's own categories, for the category list.
  Future<List<String>> customCategories() async =>
      customCategoriesIn(await _ledger.entries());

  BudgetPlan? _budget;

  /// The income and fixed commitments the limit is worked out from; null
  /// while the person sets the limit by hand.
  BudgetPlan? get budget => _budget;

  Future<BudgetPlan?> _readBudget() async {
    final prefs = _prefs;
    return prefs == null ? null : daily.readBudgetPlan(prefs);
  }


  /// "Can I buy it?" for [itemFils]: today's room and, with a budget plan,
  /// the limit from tomorrow with and without it. Nothing is saved.
  Future<PurchaseCheck> checkPurchase(int itemFils) async {
    final summary = _state?.summary;
    return daily.checkPurchase(
      itemFils: itemFils,
      dailyLimitFils: summary?.limitFils ?? 0,
      spentTodayFils: summary?.spentFils ?? 0,
      entries: await _ledger.entries(),
      today: Day.of(_clock()),
      plan: _budget,
    );
  }

  /// Turns on the worked-out limit.
  Future<void> setBudget(BudgetPlan plan) async {
    final prefs = _prefs;
    if (prefs != null) await daily.writeBudgetPlan(prefs, plan);
    await load();
  }

  /// Back to a limit set by hand; the last worked-out value stays as it is.
  Future<void> clearBudget() async {
    final prefs = _prefs;
    if (prefs != null) await daily.clearBudgetPlan(prefs);
    await load();
  }

  /// Today's limit [plan] would give, for the setup screen's preview.
  Future<int> previewLimit(BudgetPlan plan) async =>
      safeDailyLimitFils(plan, await _ledger.entries(), Day.of(_clock()));

  Future<void> setDailyLimit(int fils) async {
    // A hand-set limit replaces the worked-out one.
    final prefs = _prefs;
    if (prefs != null) await daily.clearBudgetPlan(prefs);
    final current = await _settings.load();
    await _settings.save(current.copyWith(dailyLimitFils: fils));
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _arrivals?.cancel();
    _ledger.removeListener(load);
    _settings.removeListener(load);
    super.dispose();
  }
}
