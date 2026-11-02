import 'package:beaza/l10n/app_localizations.dart';
import 'package:beaza/ui/core/formatting.dart';
import 'package:beaza/ui/features/home/views/home_view.dart' show levelText;
import 'package:beaza_extraction/beaza_extraction.dart';

/// Title and body of a guardrail notification. Amounts first, no blame.
({String title, String body}) alertText(
  AppLocalizations l10n,
  GuardrailAlert alert,
) {
  final s = alert.summary;
  String bhd(int fils) => l10n.bhd(formatFils(fils));
  final micro = l10n.microToday(s.micro.count, bhd(s.micro.totalFils));
  // With no limit set there is nothing to be over: just say what was spent.
  final status = s.limitFils <= 0
      ? l10n.spentToday(bhd(s.spentFils))
      : s.remainingFils < 0
          ? l10n.alertSpentOver(bhd(s.spentFils), bhd(-s.remainingFils))
          : l10n.alertSpentLeft(bhd(s.spentFils), bhd(s.remainingFils));

  if (alert.level == AlertLevel.normal) {
    return (title: micro, body: status);
  }
  final showMicro = alert.includesMicroTotal ||
      (alert.level == AlertLevel.level2 && s.micro.count > 0);
  return (
    title: levelText(l10n, alert.level),
    body: showMicro ? '$status\n$micro' : status,
  );
}

/// A separate notification for each level of each day. Reusing one id made
/// Android update the old notification in place, so the 100% alert could
/// look like the earlier 50% one was still showing.
int alertId(Day day, AlertLevel level) =>
    (day.year * 10000 + day.month * 100 + day.day) * 10 + level.index;
