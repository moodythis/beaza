import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/ask/view_models/ask_view_model.dart';
import 'package:beaza_assistant/beaza_assistant.dart' show AssistantIntent;
import 'package:flutter/material.dart';

/// Ask about your spending ("How much did I spend on food this week?"),
/// answered on the phone from your own list.
class AskView extends StatefulWidget {
  const AskView({super.key, required this.viewModel});

  final AskViewModel viewModel;

  @override
  State<AskView> createState() => _AskViewState();
}

class _AskViewState extends State<AskView> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();

  AskViewModel get vm => widget.viewModel;

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    vm.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    final q = preset ?? _text.text;
    if (q.trim().isEmpty) return;
    _text.clear();
    await vm.ask(q);
    await Future<void>.delayed(Duration.zero);
    if (_scroll.hasClients) {
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final examples = [
      l10n.askExampleWeek,
      l10n.askExampleWhere,
      l10n.askExampleLeft,
      l10n.askExampleTip,
      l10n.askExampleLog,
    ];
    return Scaffold(
      appBar: AppBar(title: Text(l10n.askTitle)),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListenableBuilder(
                listenable: vm,
                builder: (context, _) {
                  final turns = vm.turns;
                  return ListView(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    children: [
                      Text(l10n.askIntro, style: theme.textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          for (var i = 0; i < examples.length; i++)
                            ActionChip(
                              key: Key('askExample$i'),
                              label: Text(examples[i]),
                              onPressed: () => _send(examples[i]),
                            ),
                        ],
                      ),
                      for (final t in turns) ...[
                        const SizedBox(height: 16),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: _Bubble(
                            text: t.question,
                            color: theme.colorScheme.primaryContainer,
                            textColor: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _Bubble(
                            key: const Key('askAnswer'),
                            text: t.answer.replyText,
                            color: theme.colorScheme.surfaceContainerHighest,
                            textColor: theme.colorScheme.onSurface,
                          ),
                        ),
                        if (t.answer.intent == AssistantIntent.logExpense &&
                            t.answer.draftTransactions.isNotEmpty)
                          Align(
                            alignment: AlignmentDirectional.centerStart,
                            child: Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: t.added
                                  ? Text(l10n.askAdded,
                                      key: const Key('askAddedText'))
                                  : FilledButton.tonal(
                                      key: const Key('askAdd'),
                                      onPressed: () => vm.add(t),
                                      child: Text(l10n.askAdd),
                                    ),
                            ),
                          ),
                      ],
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const Key('askField'),
                      controller: _text,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                        hintText: l10n.askHint,
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    key: const Key('askSend'),
                    tooltip: l10n.askSend,
                    icon: const Icon(Icons.send),
                    onPressed: _send,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.text,
    required this.color,
    required this.textColor,
  });

  final String text;
  final Color color;
  final Color textColor;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.8),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Text(text, style: TextStyle(color: textColor)),
          ),
        ),
      );
}
