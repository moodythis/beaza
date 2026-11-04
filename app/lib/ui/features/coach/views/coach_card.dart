import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/coach/view_models/coach_view_model.dart';
import 'package:flutter/material.dart';

/// "AI savings plan": asks for the separate consent the first time, showing
/// exactly what will be sent, then shows the plan.
class CoachCard extends StatelessWidget {
  const CoachCard({super.key, required this.viewModel});

  final CoachViewModel viewModel;

  Future<void> _ask(BuildContext context) async {
    final language = Localizations.localeOf(context).languageCode;
    if (!viewModel.consented) {
      final preview = await viewModel.preview(language);
      if (!context.mounted) return;
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _ConsentSheet(request: preview),
      );
      if (ok != true) return;
      await viewModel.agree();
    }
    if (!context.mounted) return;
    viewModel.requestPlan(language);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PlanSheet(viewModel: viewModel),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return Card(
      key: const Key('coachCard'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome_outlined, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(l10n.coachTitle, style: theme.textTheme.titleMedium),
                ),
              ],
            ),
            const SizedBox(height: 2),
            Text(l10n.coachSubtitle, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            FilledButton.tonalIcon(
              key: const Key('coachAsk'),
              onPressed: () => _ask(context),
              icon: const Icon(Icons.auto_awesome),
              label: Text(l10n.coachAsk),
            ),
          ],
        ),
      ),
    );
  }
}

/// The lines a person reads to know exactly what is sent.
List<String> requestLines(AppLocalizations l10n, Map<String, Object> r) {
  String money(Object? fils) => l10n.bhd(formatFils(fils as int));
  final lines = <String>[
    l10n.coachSendTotal(money(r['week_total_fils'])),
    l10n.coachSendBefore(money(r['previous_week_total_fils'])),
  ];
  if ((r['daily_limit_fils'] as int) > 0) {
    lines.add(l10n.coachSendLimit(
        money(r['daily_limit_fils']), r['days_over_limit'] as int));
  }
  lines.add(l10n.coachSendSmall(
      r['small_purchases_count'] as int, money(r['small_purchases_fils'])));
  for (final c in (r['categories'] as List).cast<Map<String, Object>>()) {
    lines.add(l10n.coachSendCategory(categoryName(l10n, c['category'] as String),
        money(c['fils']), c['percent'] as int));
  }
  return lines;
}

class _ConsentSheet extends StatelessWidget {
  const _ConsentSheet({required this.request});

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
            Text(l10n.coachConsentTitle, style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(l10n.coachConsentBody),
            const SizedBox(height: 12),
            Text(l10n.coachConsentWhat, style: theme.textTheme.titleSmall),
            const SizedBox(height: 4),
            for (final line in requestLines(l10n, request))
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text('• $line', style: theme.textTheme.bodySmall),
              ),
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('coachAgree'),
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.coachAgree),
            ),
            TextButton(
              key: const Key('coachNotNow'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.coachNotNow),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlanSheet extends StatelessWidget {
  const _PlanSheet({required this.viewModel});

  final CoachViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final plan = viewModel.plan;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.coachTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                if (viewModel.step == CoachStep.loading) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  Text(l10n.coachLoading, textAlign: TextAlign.center),
                ],
                if (viewModel.step == CoachStep.failed)
                  Text(
                    switch (viewModel.error) {
                      'coach_busy' => l10n.coachBusy,
                      'network' => l10n.coachNetwork,
                      _ => l10n.coachFailed,
                    },
                    key: const Key('coachError'),
                  ),
                if (viewModel.step == CoachStep.ready && plan != null) ...[
                  SelectableText(plan.text, key: const Key('coachPlan')),
                  const SizedBox(height: 12),
                  Text(
                    plan.fromModel ? l10n.coachFromModel : l10n.coachFromRules,
                    key: const Key('coachSource'),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 16),
                TextButton(
                  key: const Key('coachWithdraw'),
                  onPressed: () async {
                    final navigator = Navigator.of(context);
                    await viewModel.withdraw();
                    navigator.pop();
                  },
                  child: Text(l10n.coachWithdraw),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
