import 'package:beaza/data/repositories/ledger_repository.dart';
import 'package:beaza/data/repositories/savings_repository.dart';
import 'package:beaza/data/repositories/settings_repository.dart';
import 'package:beaza/domain/use_cases/weekly_report.dart';
import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/category_style.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/core/privacy_button.dart';
import 'package:beaza/ui/features/challenge/views/challenge_card.dart';
import 'package:beaza/ui/features/home/views/category_donut.dart';
import 'package:beaza/ui/features/home/views/home_shell.dart';
import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

/// Builds the report for the week shown and moves between weeks.
class WeeklyReportViewModel extends ChangeNotifier {
  WeeklyReportViewModel({
    required LedgerRepository ledger,
    required SettingsRepository settings,
    SavingsRepository? savings,
    DateTime Function()? clock,
  })  : _ledger = ledger,
        _settings = settings,
        _savings = savings,
        _clock = clock ?? DateTime.now;

  final LedgerRepository _ledger;
  final SettingsRepository _settings;
  final SavingsRepository? _savings;
  final DateTime Function() _clock;

  /// 0 = the last 7 days up to today, 1 = the week before, and so on.
  int _weeksBack = 0;
  int get weeksBack => _weeksBack;

  WeeklyReport? _report;
  WeeklyReport? get report => _report;

  Future<void> load() async {
    final settings = await _settings.load();
    final end = Day.of(_clock()).addDays(-7 * _weeksBack);
    _report = buildWeeklyReport(
      await _ledger.entries(),
      end,
      dailyLimitFils: settings.dailyLimitFils,
      microThresholdFils: settings.microThresholdFils,
      holds: await _savings?.holds() ?? const [],
    );
    notifyListeners();
  }

  Future<void> older() async {
    _weeksBack++;
    await load();
  }

  Future<void> newer() async {
    if (_weeksBack == 0) return;
    _weeksBack--;
    await load();
  }
}

class WeeklyReportView extends StatelessWidget {
  const WeeklyReportView({super.key, required this.viewModel});

  final WeeklyReportViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.weeklyReport),
        actions: const [PrivacyButton()],
      ),
      body: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          final r = viewModel.report;
          if (r == null) return const Center(child: CircularProgressIndicator());
          final sections = _sections(context, r);
          return ListView(
            key: const Key('reportList'),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _WeekSwitcher(viewModel: viewModel, report: r),
              const SizedBox(height: 8),
              for (final (i, s) in sections.indexed)
                Rise(index: i, child: s),
            ],
          );
        },
      ),
    );
  }

  List<Widget> _sections(BuildContext context, WeeklyReport r) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toString();
    String money(int f) => l10n.bhd(formatFils(f));
    String dayName(Day d) =>
        DateFormat.EEEE(locale).format(DateTime.utc(d.year, d.month, d.day));
    Widget section(Key key, String title, List<Widget> children) => Card(
          key: key,
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                ...children,
              ],
            ),
          ),
        );
    Widget line(String text, {Color? color, Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Text(text, key: key, style: TextStyle(color: color)),
        );

    if (r.isEmpty) {
      return [
        section(const Key('reportEmpty'), l10n.weeklyReport,
            [line(l10n.reportEmpty)]),
      ];
    }

    final good = theme.brightness == Brightness.dark
        ? const Color(0xFF3DD68C)
        : const Color(0xFF13804C);
    final warn = theme.brightness == Brightness.dark
        ? const Color(0xFFF5B84B)
        : const Color(0xFF8A5A00);
    final p = r.deltaPercent;
    final trend = r.previousFils <= 0
        ? line(l10n.reportNoPrevious)
        : r.deltaFils < 0
            ? line(l10n.reportLess(money(-r.deltaFils), -p!),
                color: good, key: const Key('reportTrend'))
            : r.deltaFils > 0
                ? line(l10n.reportMore(money(r.deltaFils), p!),
                    color: warn, key: const Key('reportTrend'))
                : line(l10n.reportSame, key: const Key('reportTrend'));

    final dotColor = {
      DayStatus.good: good,
      DayStatus.close: warn,
      DayStatus.over: theme.colorScheme.error,
      DayStatus.none: theme.colorScheme.outlineVariant,
    };
    final cheap = r.cheapestDay;
    final heavy = r.heaviestDay;
    final mover = r.mover;
    final channelName = {
      PayChannel.card: l10n.channelCard,
      PayChannel.wallet: l10n.channelWallet,
      PayChannel.transfer: l10n.channelTransfer,
      PayChannel.cash: l10n.channelCash,
      PayChannel.atm: l10n.channelAtm,
      PayChannel.other: l10n.channelOther,
    };
    final slotName = {
      TimeSlot.morning: l10n.slotMorning,
      TimeSlot.afternoon: l10n.slotAfternoon,
      TimeSlot.evening: l10n.slotEvening,
      TimeSlot.lateNight: l10n.slotLate,
    };
    final channels = r.channels.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return [
      section(const Key('reportHeadline'), l10n.reportHeadline, [
        Text(money(r.totalFils),
            key: const Key('reportTotal'),
            style: theme.textTheme.headlineMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        trend,
        if (r.dailyLimitFils > 0) ...[
          line(l10n.reportAverage(
              money(r.dailyAverageFils), money(r.dailyLimitFils))),
          line(
              r.netSavedFils >= 0
                  ? l10n.reportPoolLeft(money(r.netSavedFils))
                  : l10n.reportPoolOver(money(-r.netSavedFils)),
              color: r.netSavedFils >= 0 ? good : warn),
        ],
      ]),
      section(const Key('reportDiscipline'), l10n.reportDiscipline, [
        Row(
          children: [
            for (final d in r.days)
              Expanded(
                child: Tooltip(
                  message: '${dayName(d.day)} ${money(d.spentFils)}',
                  child: Column(
                    children: [
                      Container(
                        height: 28,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: dotColor[d.status],
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                          DateFormat.E(locale).format(
                              DateTime.utc(d.day.year, d.day.month, d.day.day)),
                          style: theme.textTheme.labelSmall),
                    ],
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),
        if (r.dailyLimitFils > 0)
          line(l10n.reportDaysWithin(r.daysWithinLimit),
              key: const Key('reportDaysWithin')),
        if (cheap != null)
          line(l10n.reportCheapest(dayName(cheap.day), money(cheap.spentFils))),
        if (heavy != null && heavy != cheap)
          line(l10n.reportHeaviest(dayName(heavy.day), money(heavy.spentFils))),
      ]),
      if (r.categories.isNotEmpty) ...[
        CategoryDonut(totals: r.categories),
        if (mover != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              mover.changeFils > 0
                  ? l10n.reportMoverUp(
                      categoryName(l10n, mover.bucket), money(mover.changeFils))
                  : l10n.reportMoverDown(categoryName(l10n, mover.bucket),
                      money(-mover.changeFils)),
              key: const Key('reportMover'),
            ),
          ),
      ],
      if (r.topShops.isNotEmpty || r.largest != null)
        section(const Key('reportShops'), l10n.reportShops, [
          for (final (i, s) in r.topShops.indexed)
            line('${i + 1}. ${l10n.reportShopLine(s.name, s.count, money(s.fils))}'),
          if (r.largest != null)
            line(l10n.reportLargest(
                r.largest!.shop.isEmpty ? '-' : r.largest!.shop,
                dayName(r.largest!.day),
                money(r.largest!.fils))),
        ]),
      section(const Key('reportMicro'), l10n.reportMicroTitle, [
        line(l10n.reportMicro(
            r.microCount, r.percentOf(r.microFils), money(r.microFils))),
      ]),
      section(const Key('reportTime'), l10n.reportTimeTitle, [
        line(l10n.reportWeekend(money(r.weekendFils), r.percentOf(r.weekendFils))),
        line(l10n.reportLate(r.lateCount, money(r.lateFils))),
        if (r.peak != null) line(l10n.reportPeak(slotName[r.peak]!)),
      ]),
      if (channels.isNotEmpty)
        section(const Key('reportChannels'), l10n.reportChannels, [
          for (final c in channels)
            line('${channelName[c.key]}: ${money(c.value)} (${r.percentOf(c.value)}%)'),
        ]),
      section(const Key('reportWins'), l10n.reportWins, [
        line(r.skippedCount > 0
            ? l10n.reportSkipped(r.skippedCount, money(r.skippedFils))
            : l10n.reportNoSkipped),
        line(l10n.reportPoints(r.points), key: const Key('reportPoints')),
      ]),
      section(const Key('reportFocus'), l10n.reportFocus, [
        line(r.focus == null
            ? l10n.reportFocusNone
            : ChallengeCard.describe(l10n, r.focus!)),
      ]),
      OutlinedButton.icon(
        key: const Key('reportShare'),
        icon: const Icon(Icons.copy_all_outlined),
        label: Text(l10n.reportShare),
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          final lang = Localizations.localeOf(context).languageCode;
          await Clipboard.setData(ClipboardData(
              text: shareSummary(r, lang, (b) => categoryName(l10n, b))));
          messenger.showSnackBar(SnackBar(content: Text(l10n.reportCopied)));
        },
      ),
    ];
  }
}

class _WeekSwitcher extends StatelessWidget {
  const _WeekSwitcher({required this.viewModel, required this.report});

  final WeeklyReportViewModel viewModel;
  final WeeklyReport report;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toString();
    String d(Day x) =>
        DateFormat.MMMd(locale).format(DateTime.utc(x.year, x.month, x.day));
    return Row(
      children: [
        IconButton(
          key: const Key('reportOlder'),
          tooltip: l10n.reportOlder,
          icon: const Icon(Icons.chevron_left),
          onPressed: viewModel.older,
        ),
        Expanded(
          child: Text(
            viewModel.weeksBack == 0
                ? '${l10n.reportThisWeek} · ${d(report.start)} – ${d(report.end)}'
                : '${d(report.start)} – ${d(report.end)}',
            key: const Key('reportRange'),
            textAlign: TextAlign.center,
          ),
        ),
        IconButton(
          key: const Key('reportNewer'),
          tooltip: l10n.reportNewer,
          icon: const Icon(Icons.chevron_right),
          onPressed: viewModel.weeksBack == 0 ? null : viewModel.newer,
        ),
      ],
    );
  }
}
