import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/preferences_store.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/data/services/chat_api.dart';
import 'package:beaza/domain/use_cases/chat_request.dart';
import 'package:beaza/domain/use_cases/daily_budget.dart';
import 'package:beaza_assistant/beaza_assistant.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/foundation.dart';

/// One question and its answer on the questions screen.
class AskTurn {
  AskTurn(this.question, this.answer, {this.chatFailed = false});

  final String question;
  final AssistantResponse answer;

  /// "Smarter answers" was on but Gemini gave no answer this time (offline,
  /// busy, or its reply failed the number check), so [answer] is the
  /// phone's own.
  final bool chatFailed;

  /// Gemini wrote [answer], from numbers the phone worked out.
  bool get viaChat => answer.source == ResponseSource.llm;

  /// The drafts in [answer] were added to the list.
  bool added = false;
}

/// Questions about spending. The phone's rules answer first, from the
/// ledger (beaza_assistant). If the person turned on "Smarter answers" (a
/// separate, withdrawable consent), a question that is about spending, but
/// is not a cash expense said in words, also goes to Gemini with numbers
/// worked out on the phone ([chatRequest]); Gemini's answer replaces the
/// rules' only if the server's checks pass. A question that is not about
/// spending, and every failure, keep the phone's own answer. Nothing is
/// stored; the conversation is gone when the screen closes.
class AskViewModel extends ChangeNotifier {
  AskViewModel({
    required LedgerRepository ledger,
    required SettingsRepository settings,
    required Future<void> Function(List<DraftTransaction>) addDrafts,
    Future<AffordFacts?> Function(int priceFils)? afford,
    ChatApi? chat,
    PreferencesStore? preferences,
    BudgetPlan? Function()? plan,
    DateTime Function()? clock,
  })  : _ledger = ledger,
        _afford = afford,
        _settings = settings,
        _addDrafts = addDrafts,
        _chat = chat,
        _prefs = preferences,
        _plan = plan,
        _clock = clock ?? DateTime.now;

  /// Where the chat consent is kept (the value is [kChatConsentVersion]).
  static const String consentPref = 'chatConsent';

  final LedgerRepository _ledger;
  final SettingsRepository _settings;
  final Future<void> Function(List<DraftTransaction>) _addDrafts;

  /// The home screen's "Can I buy it?" for a price, from the budget plan.
  final Future<AffordFacts?> Function(int priceFils)? _afford;
  final ChatApi? _chat;
  final PreferencesStore? _prefs;
  final BudgetPlan? Function()? _plan;
  final DateTime Function() _clock;

  final List<AskTurn> _turns = [];
  List<AskTurn> get turns => List.unmodifiable(_turns);

  bool _disposed = false;

  /// Whether the screen can offer "Smarter answers" at all.
  bool get chatAvailable => _chat != null && _prefs != null;

  bool _chatOn = false;
  bool get chatOn => _chatOn;

  /// The question waiting for Gemini's answer, if any.
  String? _pending;
  String? get pending => _pending;

  Future<void> loadChat() async {
    final prefs = _prefs;
    if (_chat == null || prefs == null) return;
    _chatOn = await prefs.read(consentPref) == kChatConsentVersion;
    _changed();
  }

  /// Exactly what a question would send, to show before agreeing. The
  /// question itself is a stand-in.
  Future<Map<String, Object>> chatPreview(String language) async =>
      chatRequest(
        entries: await _ledger.entries(),
        settings: await _settings.load(),
        today: Day.of(_clock()),
        language: language,
        question: '...',
        plan: _plan?.call(),
      )!;

  Future<void> agreeChat() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.write(consentPref, kChatConsentVersion);
    _chatOn = true;
    _changed();
  }

  /// Withdraws the consent; nothing is sent again until the person agrees.
  Future<void> withdrawChat() async {
    final prefs = _prefs;
    if (prefs == null) return;
    await prefs.write(consentPref, null);
    _chatOn = false;
    _changed();
  }

  bool _asking = false;

  Future<void> ask(String text) async {
    final q = text.trim();
    if (q.isEmpty || _asking) return;
    _asking = true;
    try {
      await _ask(q);
    } finally {
      _asking = false;
    }
  }

  Future<void> _ask(String q) async {
    final assistant =
        BeazaAiAssistant(settings: await _settings.load(), clock: _clock);
    // The last question, so "and on Sunday?" asks it again for Sunday.
    final previous = _turns.isEmpty ? null : _turns.last.question;
    // The question before is sent along only if it was itself one that may
    // be sent: not a turned-away question, not a cash expense.
    final previousForChat = _turns.isEmpty || !_mayBeSent(_turns.last.answer)
        ? null
        : _turns.last.question;
    final asked = assistant.detector.detect(q);
    final price = asked.priceFils;
    final afford = _afford;
    final facts = asked.intent == AssistantIntent.canIBuy &&
            price != null &&
            afford != null
        ? await afford(price)
        : null;
    final entries = await _ledger.entries();
    final local = assistant.answerLocally(q, entries,
        previous: previous, afford: facts);

    var answer = local;
    var failed = false;
    final chat = _chat;
    // A question that is not about spending, and a cash expense said in
    // words, are answered on the phone and never sent.
    if (_chatOn && chat != null && _mayBeSent(local)) {
      final request = chatRequest(
        entries: entries,
        settings: await _settings.load(),
        today: Day.of(_clock()),
        language: asked.arabic ? 'ar' : 'en',
        question: q,
        previousQuestion: previousForChat,
        metrics: local.referencedMetrics,
        plan: _plan?.call(),
      );
      if (request != null) {
        _pending = q;
        _changed();
        try {
          final reply = await chat.ask(request);
          if (reply.refused) {
            answer = AssistantResponse(
              intent: AssistantIntent.outOfScope,
              replyText: kAssistantScope.reply(arabic: asked.arabic),
            );
          } else if (reply.text != null) {
            answer = local.withText(reply.text!, ResponseSource.llm);
          } else {
            failed = true;
          }
        } catch (_) {
          // Offline, busy or refused: the phone's own answer is already right.
          failed = true;
        } finally {
          _pending = null;
        }
      }
    }
    _turns.add(AskTurn(q, answer, chatFailed: failed));
    _changed();
  }

  static bool _mayBeSent(AssistantResponse a) =>
      a.intent != AssistantIntent.outOfScope &&
      a.intent != AssistantIntent.logExpense;

  /// Saves the drafts of one answer (cash spending said in words).
  Future<void> add(AskTurn turn) async {
    if (turn.added || turn.answer.draftTransactions.isEmpty) return;
    await _addDrafts(turn.answer.draftTransactions);
    turn.added = true;
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
