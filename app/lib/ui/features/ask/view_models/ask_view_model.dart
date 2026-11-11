import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza_assistant/beaza_assistant.dart';
import 'package:flutter/foundation.dart';

/// One question and its answer on the questions screen.
class AskTurn {
  AskTurn(this.question, this.answer);

  final String question;
  final AssistantResponse answer;

  /// The drafts in [answer] were added to the list.
  bool added = false;
}

/// Questions about spending, answered on the phone by rules from the
/// ledger (beaza_assistant): no network, no AI. Nothing is stored; the
/// conversation is gone when the screen closes.
class AskViewModel extends ChangeNotifier {
  AskViewModel({
    required LedgerRepository ledger,
    required SettingsRepository settings,
    required Future<void> Function(List<DraftTransaction>) addDrafts,
    DateTime Function()? clock,
  })  : _ledger = ledger,
        _settings = settings,
        _addDrafts = addDrafts,
        _clock = clock ?? DateTime.now;

  final LedgerRepository _ledger;
  final SettingsRepository _settings;
  final Future<void> Function(List<DraftTransaction>) _addDrafts;
  final DateTime Function() _clock;

  final List<AskTurn> _turns = [];
  List<AskTurn> get turns => List.unmodifiable(_turns);

  bool _disposed = false;

  Future<void> ask(String text) async {
    final q = text.trim();
    if (q.isEmpty) return;
    final assistant =
        BeazaAiAssistant(settings: await _settings.load(), clock: _clock);
    // The last question, so "and on Sunday?" asks it again for Sunday.
    final previous = _turns.isEmpty ? null : _turns.last.question;
    _turns.add(AskTurn(
        q,
        assistant.answerLocally(q, await _ledger.entries(),
            previous: previous)));
    if (!_disposed) notifyListeners();
  }

  /// Saves the drafts of one answer (cash spending said in words).
  Future<void> add(AskTurn turn) async {
    if (turn.added || turn.answer.draftTransactions.isEmpty) return;
    await _addDrafts(turn.answer.draftTransactions);
    turn.added = true;
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
