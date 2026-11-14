import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/account/legal_text.dart';
import 'package:beaza/ui/features/account/views/account_widgets.dart';
import 'package:beaza/ui/features/ask/view_models/ask_view_model.dart';
import 'package:beaza/ui/features/coach/views/coach_card.dart' show requestLines;
import 'package:beaza_assistant/beaza_assistant.dart' show AssistantIntent;
import 'package:flutter/material.dart';

/// Ask about your spending ("How much did I spend on food this week?"),
/// answered on the phone from your own list, or, if the person turned on
/// "Smarter answers", by Gemini from totals the phone worked out.
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
  void initState() {
    super.initState();
    vm.loadChat();
  }

  Future<void> _turnOn() async {
    final language = AppLocalizations.of(context).localeName;
    final request = await vm.chatPreview(language.startsWith('ar') ? 'ar' : 'en');
    if (!mounted) return;
    final agreed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ChatConsentSheet(request: request),
    );
    if (agreed == true) await vm.agreeChat();
  }

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
                      Text(vm.chatOn ? l10n.askIntroChat : l10n.askIntro,
                          style: theme.textTheme.bodySmall),
                      if (vm.chatAvailable) ...[
                        const SizedBox(height: 8),
                        _ChatSwitch(
                          on: vm.chatOn,
                          onTurnOn: _turnOn,
                          onTurnOff: vm.withdrawChat,
                        ),
                      ],
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
                        if (t.viaChat || t.chatFailed)
                          Padding(
                            padding: const EdgeInsetsDirectional.only(
                                start: 4, top: 2),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                t.viaChat ? l10n.chatByGemini : l10n.chatFallback,
                                key: Key(t.viaChat ? 'chatByGemini' : 'chatFallback'),
                                style: theme.textTheme.labelSmall,
                              ),
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
                      if (vm.pending != null) ...[
                        const SizedBox(height: 16),
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: _Bubble(
                            text: vm.pending!,
                            color: theme.colorScheme.primaryContainer,
                            textColor: theme.colorScheme.onPrimaryContainer,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: Row(
                            key: const Key('chatThinking'),
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                              const SizedBox(width: 8),
                              Text(l10n.chatThinking,
                                  style: theme.textTheme.bodySmall),
                            ],
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

/// "Smarter answers": off, a card that explains it and asks; on, a line to
/// turn it off again.
class _ChatSwitch extends StatelessWidget {
  const _ChatSwitch({
    required this.on,
    required this.onTurnOn,
    required this.onTurnOff,
  });

  final bool on;
  final VoidCallback onTurnOn;
  final VoidCallback onTurnOff;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    if (on) {
      return Row(
        key: const Key('chatOn'),
        children: [
          const Icon(Icons.auto_awesome, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(l10n.chatOnLabel, style: theme.textTheme.bodySmall),
          ),
          TextButton(
            key: const Key('chatTurnOff'),
            onPressed: onTurnOff,
            child: Text(l10n.chatTurnOff),
          ),
        ],
      );
    }
    return Card(
      key: const Key('chatBanner'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.chatBannerTitle,
                      style: theme.textTheme.titleSmall),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(l10n.chatBannerBody, style: theme.textTheme.bodySmall),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: FilledButton.tonal(
                key: const Key('chatTurnOn'),
                onPressed: onTurnOn,
                child: Text(l10n.chatTurnOn),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lines a person reads to know exactly what a question sends: the
/// savings plan's list, plus what the chat adds.
List<String> chatRequestLines(AppLocalizations l10n, Map<String, Object> r) {
  String money(Object? fils) => l10n.bhd(formatFils(fils as int));
  final periods = r['periods'] as Map<String, Object>;
  String total(String k) => money((periods[k]! as Map<String, Object>)['fils']);
  return [
    l10n.chatSendQuestion,
    ...requestLines(l10n, r),
    l10n.chatSendToday(money(r['today_spent_fils'])),
    l10n.chatSendPeriods(
      total('today'),
      total('yesterday'),
      total('week'),
      total('last_week'),
      total('month'),
      total('last_month'),
    ),
    for (final c in (r['month_categories'] as List).cast<Map<String, Object>>())
      l10n.chatSendMonthCategory(categoryName(l10n, c['category'] as String),
          money(c['fils']), c['percent'] as int),
    for (final x in (r['month_shops'] as List).cast<Map<String, Object>>())
      l10n.chatSendMonthShop(
          x['name'] as String, money(x['fils']), x['count'] as int),
    l10n.chatSendMetrics,
  ];
}

class _ChatConsentSheet extends StatelessWidget {
  const _ChatConsentSheet({required this.request});

  final Map<String, Object> request;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(l10n.chatConsentTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l10n.chatConsentBody),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('chatPrivacy'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => openLegal(context, privacyNotice,
                    section: kPrivacyChatSection),
                child: Text(l10n.privacyDetails),
              ),
            ),
            // The exact list, folded so the buttons stay in view.
            ExpansionTile(
              key: const Key('chatWhat'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text(l10n.chatConsentWhat,
                  style: theme.textTheme.titleSmall),
              children: [
                for (final line in chatRequestLines(l10n, request))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• $line', style: theme.textTheme.bodySmall),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('chatAgree'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.chatAgree),
            ),
            TextButton(
              key: const Key('chatNotNow'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.coachNotNow),
            ),
          ],
        ),
      ),
    );
  }
}
