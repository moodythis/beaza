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
  AskTurn(this.question, this.answer,
      {this.chatFailed = false, this.mayBeSent = false, this.chatReason});

  final String question;
  final AssistantResponse answer;

  /// "Smarter answers" was on but Gemini gave no answer this time (offline,
  /// busy, or its reply failed the number check), so [answer] is the
  /// phone's own.
  final bool chatFailed;

  /// Why Gemini gave no answer, when the server's check said so: one of
  /// `unchecked_number`, `off_topic`, `format`, `too_long`, `empty_reply`, or
  /// `offline` (no reply at all). Never the reply itself.
  final String? chatReason;

  /// The question was sent to Gemini ("Smarter answers" was on, the phone
  /// judged it to be about spending, and Gemini did not refuse it), so it may
  /// go along as the previous question of the next one.
  final bool mayBeSent;

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

  /// A question is being answered; another cannot be sent yet.
  bool get busy => _asking;

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
    final previousForChat =
        _turns.isEmpty || !_turns.last.mayBeSent ? null : _turns.last.question;
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
    String? reason;
    var refused = false;
    final chat = _chat;
    // A question that is not about spending, text the rules do not take to
    // be about money, and a cash expense said in words are answered on the
    // phone and never sent.
    final eligible = _mayBeSent(local, asked.aboutMoney);
    final chatWasOn = _chatOn;
    if (_chatOn && chat != null && eligible) {
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
            refused = true;
            // Gemini judged it not to be about the person's spending: a rules
            // answer to a question that was not asked would mislead, so say
            // what this screen is for.
            // The phone's own affordability and guardrail answers stay: they
            // come from the person's plan, not from a guess about words.
            if (local.intent != AssistantIntent.canIBuy &&
                local.intent != AssistantIntent.guardrailAdvice) {
              answer = AssistantResponse(
                intent: AssistantIntent.outOfScope,
                replyText: kAssistantScope.reply(arabic: asked.arabic),
              );
            }
          } else if (reply.text != null) {
            answer = local.withText(reply.text!, ResponseSource.llm);
          } else {
            failed = true;
            reason = reply.reason;
          }
        } catch (_) {
          // Offline, busy or refused: the phone's own answer is already right.
          failed = true;
          reason = 'offline';
        } finally {
          _pending = null;
        }
      }
    }
    // Only a question that was really sent while chat was on, and not
    // refused, may ride along as the "previous question" later.
    final wasSent = chatWasOn && eligible && !refused;
    _turns.add(AskTurn(q, answer,
        chatFailed: failed, mayBeSent: wasSent, chatReason: reason));
    _changed();
  }

  /// Only a question the phone's own rules take to be about spending may be
  /// sent: not a turned-away question, not a cash expense said in words, and
  /// not text the rules did not understand unless it has a money word or an
  /// amount (what is left is whatever the person typed).
  static bool _mayBeSent(AssistantResponse a, bool aboutMoney) =>
      switch (a.intent) {
        AssistantIntent.spendingQuery ||
        AssistantIntent.guardrailAdvice ||
        AssistantIntent.canIBuy =>
          true,
        AssistantIntent.unknown => aboutMoney,
        AssistantIntent.outOfScope || AssistantIntent.logExpense => false,
      };

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
