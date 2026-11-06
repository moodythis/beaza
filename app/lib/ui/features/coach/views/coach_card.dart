import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/features/account/legal_text.dart';
import 'package:beaza/ui/features/account/views/account_widgets.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/coach/view_models/coach_view_model.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// "AI savings plan": asks for the separate consent the first time, showing
/// exactly what will be sent, then shows the plan.
class CoachCard extends StatelessWidget {
  const CoachCard({super.key, required this.viewModel});

  final CoachViewModel viewModel;

  Future<void> _ask(BuildContext context, {bool cheaper = false}) async {
    final language = Localizations.localeOf(context).languageCode;
    if (!viewModel.consented) {
      final preview = await viewModel.preview(language);
      if (!context.mounted) return;
      final ok = await showModalBottomSheet<bool>(
        context: context,
        useSafeArea: true,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _ConsentSheet(request: preview),
      );
      if (ok != true) return;
      await viewModel.agree();
    }
    if (!context.mounted) return;
    if (cheaper) {
      viewModel.requestAlternatives(language);
    } else {
      viewModel.requestPlan(language);
    }
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => cheaper
          ? _CheaperSheet(viewModel: viewModel)
          : _PlanSheet(viewModel: viewModel),
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
            const SizedBox(height: 8),
            OutlinedButton.icon(
              key: const Key('coachCheaper'),
              onPressed: () => _ask(context, cheaper: true),
              icon: const Icon(Icons.local_offer_outlined),
              label: Text(l10n.cheaperAsk),
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
  final late = r['late_night_count'] as int? ?? 0;
  if (late > 0) {
    lines.add(l10n.coachSendLate(late, money(r['late_night_fils'])));
  }
  lines.add(l10n.coachSendWeekend(money(r['weekend_fils'] ?? 0)));
  if (r['month_left_fils'] != null) {
    lines.add(l10n.coachSendMonth(
        money(r['month_left_fils']), r['days_left_in_month'] as int));
  }
  for (final x in ((r['shops'] as List?) ?? const []).cast<Map<String, Object>>()) {
    lines.add(l10n.coachSendShop(
        x['name'] as String, money(x['fils']), x['count'] as int));
  }
  final locale = l10n.localeName;
  const days = ['mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
  for (final x in ((r['recent'] as List?) ?? const []).cast<Map<String, Object>>()) {
    // 2 Nov 2026 is a Monday.
    final day = DateFormat.E(locale)
        .format(DateTime(2026, 11, 2 + days.indexOf(x['weekday'] as String)));
    final hour = (x['hour'] as int).toString().padLeft(2, '0');
    lines.add(l10n.coachSendRecent(day, '$hour:00', money(x['fils']),
        categoryName(l10n, x['category'] as String), (x['shop'] as String?) ?? '-'));
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
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                key: const Key('coachPrivacy'),
                style: TextButton.styleFrom(padding: EdgeInsets.zero),
                onPressed: () => openLegal(context, privacyNotice,
                    section: kPrivacyCoachSection),
                child: Text(l10n.privacyDetails),
              ),
            ),
            // The exact list, folded so the buttons stay in view.
            ExpansionTile(
              key: const Key('coachWhat'),
              tilePadding: EdgeInsets.zero,
              childrenPadding: const EdgeInsets.only(bottom: 8),
              expandedCrossAxisAlignment: CrossAxisAlignment.start,
              title: Text(l10n.coachConsentWhat,
                  style: theme.textTheme.titleSmall),
              children: [
                for (final line in requestLines(l10n, request))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text('• $line', style: theme.textTheme.bodySmall),
                  ),
              ],
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
                      'timeout' => l10n.coachTimeout,
                      _ => l10n.coachFailed,
                    },
                    key: const Key('coachError'),
                  ),
                if (viewModel.step == CoachStep.ready && plan != null) ...[
                  SelectableText(plan.text, key: const Key('coachPlan')),
                  const SizedBox(height: 12),
                  Text(
                    plan.fromModel
                        ? '${l10n.coachFromModel}${providerLabel(plan.provider)}'
                        : plan.reason == null
                            ? l10n.coachFromRules
                            : '${l10n.coachFromRules} (${plan.reason})',
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

/// "Cheaper options": one AI idea per shop where the person spends most.
class _CheaperSheet extends StatelessWidget {
  const _CheaperSheet({required this.viewModel});

  final CoachViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return SafeArea(
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final result = viewModel.alternatives;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.cheaperTitle, style: theme.textTheme.titleLarge),
                const SizedBox(height: 12),
                if (viewModel.altStep == CoachStep.loading) ...[
                  const Center(child: CircularProgressIndicator()),
                  const SizedBox(height: 12),
                  Text(l10n.coachLoading, textAlign: TextAlign.center),
                ],
                if (viewModel.altStep == CoachStep.failed)
                  Text(
                    switch (viewModel.error) {
                      'coach_busy' => l10n.coachBusy,
                      'network' => l10n.coachNetwork,
                      'timeout' => l10n.coachTimeout,
                      _ => l10n.coachFailed,
                    },
                    key: const Key('cheaperError'),
                  ),
                if (viewModel.altStep == CoachStep.ready) ...[
                  if (viewModel.noShops)
                    Text(l10n.cheaperNoShops, key: const Key('cheaperNoShops'))
                  else if (result == null || result.options.isEmpty)
                    Text(
                      result?.reason == null
                          ? l10n.cheaperNone
                          : '${l10n.cheaperNone} (${result!.reason})',
                      key: const Key('cheaperNone'),
                    )
                  else ...[
                    for (final o in result.options)
                      ListTile(
                        key: Key('cheaper_${o.shop}'),
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.storefront_outlined),
                        title: Text(o.shop),
                        subtitle: Text(o.idea),
                      ),
                    const SizedBox(height: 8),
                    Text(
                      '${l10n.cheaperNote}${providerLabel(result.provider)}',
                      key: const Key('cheaperNote'),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

/// " (Gemini)", so the person (and a tester) can see which AI answered.
String providerLabel(String? provider) => switch (provider) {
      'gemini' => ' (Gemini)',
      _ => '',
    };

