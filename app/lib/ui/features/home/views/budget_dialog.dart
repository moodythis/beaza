import 'package:beaza/domain/use_cases/daily_budget.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:flutter/material.dart';

/// What the person returns: a plan to work the limit out from, or "by hand".
class BudgetChoice {
  const BudgetChoice.plan(this.plan);
  const BudgetChoice.byHand() : plan = null;

  final BudgetPlan? plan;
}

/// Income, commitments and how to save. [preview] gives today's limit for a
/// plan, shown live under the choices.
Future<BudgetChoice?> showBudgetDialog(
  BuildContext context, {
  BudgetPlan? current,
  Future<int> Function(BudgetPlan plan)? preview,
}) =>
    Navigator.of(context).push<BudgetChoice>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BudgetSetupView(current: current, preview: preview),
    ));

/// The texts of one way of budgeting.
class ProfileText {
  const ProfileText(this.title, this.source, this.who, this.how);
  final String title;
  final String source;
  final String who;
  final String how;
}

ProfileText profileText(AppLocalizations l10n, BudgetProfile p) => switch (p) {
      BudgetProfile.none => ProfileText(l10n.profileNoneTitle, '',
          l10n.profileNoneWho, l10n.profileNoneHow),
      BudgetProfile.payYourselfFirst => ProfileText(l10n.profilePyfTitle,
          l10n.profilePyfSource, l10n.profilePyfWho, l10n.profilePyfHow),
      BudgetProfile.fiftyThirtyTwenty => ProfileText(l10n.profile503020Title,
          l10n.profile503020Source, l10n.profile503020Who, l10n.profile503020How),
      BudgetProfile.seventyTwentyTen => ProfileText(l10n.profile702010Title,
          l10n.profile702010Source, l10n.profile702010Who, l10n.profile702010How),
      BudgetProfile.weekendWeighted => ProfileText(l10n.profileWeekendTitle,
          l10n.profileWeekendSource, l10n.profileWeekendWho, l10n.profileWeekendHow),
      BudgetProfile.kakeibo => ProfileText(l10n.profileKakeiboTitle,
          l10n.profileKakeiboSource, l10n.profileKakeiboWho, l10n.profileKakeiboHow),
      BudgetProfile.custom => ProfileText(l10n.profileCustomTitle, '',
          l10n.profileCustomWho, l10n.profileCustomHow),
    };

class BudgetSetupView extends StatefulWidget {
  const BudgetSetupView({super.key, this.current, this.preview});

  final BudgetPlan? current;
  final Future<int> Function(BudgetPlan plan)? preview;

  @override
  State<BudgetSetupView> createState() => _BudgetSetupViewState();
}

class _BudgetSetupViewState extends State<BudgetSetupView> {
  late final TextEditingController _income = TextEditingController(
      text: widget.current == null
          ? ''
          : formatFils(widget.current!.incomeFils, group: false));
  late final TextEditingController _fixed = TextEditingController(
      text: widget.current == null || widget.current!.fixedFils == 0
          ? ''
          : formatFils(widget.current!.fixedFils, group: false));
  late final TextEditingController _custom = TextEditingController(
      text: widget.current?.profile == BudgetProfile.custom
          ? formatFils(widget.current!.savingsFils, group: false)
          : '');
  late BudgetProfile _profile =
      widget.current?.profile ?? BudgetProfile.payYourselfFirst;
  String? _error;
  int? _limit;
  int _previewRun = 0;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void dispose() {
    _income.dispose();
    _fixed.dispose();
    _custom.dispose();
    super.dispose();
  }

  /// The plan the fields describe, or null while they are not complete.
  BudgetPlan? get _plan {
    final income = parseBhdToFils(_income.text);
    final fixed = _fixed.text.trim().isEmpty ? 0 : parseBhdToFils(_fixed.text);
    final custom =
        _custom.text.trim().isEmpty ? 0 : parseBhdToFils(_custom.text);
    if (income == null || income <= 0 || fixed == null || custom == null) {
      return null;
    }
    return BudgetPlan.withProfile(
      incomeFils: income,
      fixedFils: fixed,
      profile: _profile,
      customSavingsFils: custom,
    );
  }

  Future<void> _refresh() async {
    final plan = _plan;
    final run = ++_previewRun;
    final preview = widget.preview;
    final limit = plan == null || !plan.isValid || preview == null
        ? null
        : await preview(plan);
    if (!mounted || run != _previewRun) return;
    setState(() {
      _limit = limit;
      _error = null;
    });
  }

  void _submit() {
    final l10n = AppLocalizations.of(context);
    final plan = _plan;
    if (plan == null) {
      setState(() => _error = l10n.budgetInvalid);
      return;
    }
    if (!plan.isValid) {
      setState(() => _error = l10n.budgetNoRoom);
      return;
    }
    Navigator.of(context).pop(BudgetChoice.plan(plan));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final plan = _plan;
    String bhd(int fils) => l10n.bhd(formatFils(fils));
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.budgetTitle),
        actions: [
          if (widget.current != null)
            TextButton(
              key: const Key('budgetByHand'),
              onPressed: () =>
                  Navigator.of(context).pop(const BudgetChoice.byHand()),
              child: Text(l10n.budgetByHand),
            ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(l10n.budgetExplain),
            const SizedBox(height: 16),
            TextField(
              key: const Key('budgetIncome'),
              controller: _income,
              autofocus: widget.current == null,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: l10n.budgetIncome),
              onChanged: (_) => _refresh(),
            ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('budgetFixed'),
              controller: _fixed,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: l10n.budgetFixed,
                helperText: l10n.budgetFixedHint,
                helperMaxLines: 3,
              ),
              onChanged: (_) => _refresh(),
            ),
            const SizedBox(height: 24),
            Text(l10n.budgetHowToSave, style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final p in BudgetProfile.values) _card(context, p),
            if (_profile == BudgetProfile.custom) ...[
              const SizedBox(height: 8),
              TextField(
                key: const Key('budgetCustomSavings'),
                controller: _custom,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: l10n.budgetSavingsAmount),
                onChanged: (_) => _refresh(),
              ),
            ],
            const SizedBox(height: 16),
            if (plan != null)
              _Preview(
                key: const Key('budgetPreview'),
                lines: [
                  l10n.budgetPreviewIncome(bhd(plan.incomeFils)),
                  l10n.budgetPreviewFixed(bhd(plan.fixedFils)),
                  l10n.budgetPreviewSavings(bhd(plan.savingsFils)),
                  if (plan.isValid && _limit != null)
                    l10n.budgetPreviewLimit(bhd(_limit!)),
                ],
                warning: !plan.isValid
                    ? l10n.budgetNoRoom
                    : plan.profile == BudgetProfile.fiftyThirtyTwenty &&
                            plan.commitmentsOverHalf
                        ? l10n.budgetOverHalf
                        : null,
              ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!,
                  key: const Key('budgetError'),
                  style: TextStyle(color: theme.colorScheme.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              key: const Key('budgetSave'),
              onPressed: _submit,
              child: Text(l10n.save),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(BuildContext context, BudgetProfile p) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final t = profileText(l10n, p);
    final selected = p == _profile;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Semantics(
        selected: selected,
        button: true,
        child: InkWell(
          key: Key('profile_${p.name}'),
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _profile = p);
            _refresh();
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.outlineVariant,
                width: selected ? 2 : 1,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      selected
                          ? Icons.radio_button_checked
                          : Icons.radio_button_unchecked,
                      color: selected ? theme.colorScheme.primary : null,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text(t.title, style: theme.textTheme.titleSmall)),
                  ],
                ),
                if (t.source.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(t.source, style: theme.textTheme.bodySmall),
                ],
                const SizedBox(height: 8),
                Text('${l10n.profileWhoLabel}: ${t.who}',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(fontWeight: FontWeight.w600)),
                if (selected) ...[
                  const SizedBox(height: 4),
                  Text(t.how, style: theme.textTheme.bodyMedium),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({super.key, required this.lines, this.warning});

  final List<String> lines;
  final String? warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(l),
            ),
          if (warning != null) ...[
            const SizedBox(height: 8),
            Text(warning!,
                key: const Key('budgetWarning'),
                style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
    );
  }
}
