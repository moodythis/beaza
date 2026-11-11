/// The assistant: understands the request with rules, computes every number
/// on the phone, writes a short reply itself, and only then, if the person
/// allowed it, lets a language model reword that reply. Works fully offline.
library;

import 'package:beaza_extraction/beaza_extraction.dart';

import 'analytics.dart';
import 'expense.dart';
import 'intent.dart';
import 'llm.dart';
import 'response.dart';
import 'sanitizer.dart';
import 'scope.dart';
import 'text.dart';

const String kSystemPrompt = '''
You are the assistant inside Beaza, a daily spending app for young people in Bahrain.
Rewrite "draft_reply" in a friendly, short way (at most two sentences).
If "language" is "ar-gulf", write in plain Gulf Arabic; otherwise in English.
Use only the numbers that appear in "draft_reply" or in "metrics" (use their "display" text exactly).
Never add, subtract, multiply or compute percentages yourself, and never invent a number.
Do not recommend banks, loans, investments or any financial product.
Speak like a Bahraini who helps students organise their spending: practical, kind, specific to the shops and habits named, never preachy.''';

/// A habit is named only from this much in 7 days (BHD 3.000). A first
/// guess, like the app's other tip thresholds.
const int kHabitMinFils = 3000;

/// The weekend is named only from BHD 5.000 (the app's weekend tip uses the
/// same amount).
const int kWeekendMinFils = 5000;

/// "800 فلس", "1.500 د.ب" / "800 fils", "BHD 1.500".
String formatMoney(int fils, {required bool arabic}) {
  final neg = fils < 0;
  final f = fils.abs();
  final String s;
  if (f < 1000) {
    s = arabic ? '$f فلس' : '$f fils';
  } else {
    final d = f ~/ 1000;
    final r = (f % 1000).toString().padLeft(3, '0');
    s = arabic ? '$d.$r د.ب' : 'BHD $d.$r';
  }
  return neg ? '-$s' : s;
}

String bucketName(String bucket, {required bool arabic}) {
  const ar = {
    'food': 'الأكل والمطاعم',
    'groceries': 'البقالة',
    'shopping': 'التسوق',
    'transport': 'المواصلات',
    'bills': 'الفواتير',
    'health': 'الصحة',
    'entertainment': 'الترفيه',
    'education': 'الدراسة',
    'other': 'أشياء ثانية',
    'transfer': 'التحويلات',
    'unsorted': 'غير مصنّف',
  };
  const en = {
    'food': 'food',
    'groceries': 'groceries',
    'shopping': 'shopping',
    'transport': 'transport',
    'bills': 'bills',
    'health': 'health',
    'entertainment': 'entertainment',
    'education': 'education',
    'other': 'other',
    'transfer': 'transfers',
    'unsorted': 'not sorted',
  };
  return (arabic ? ar : en)[bucket] ?? bucket;
}

const List<String> _dayAr = ['الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد'];
const List<String> _dayEn = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

String _periodText(Period p, Day today, {required bool arabic}) => switch (p.kind) {
      PeriodKind.weekday when p.from == today => arabic ? 'اليوم' : 'today',
      PeriodKind.weekday => arabic
          ? 'يوم ${_dayAr[dayOfWeek(p.from) - 1]}'
          : 'on ${_dayEn[dayOfWeek(p.from) - 1]}',
      PeriodKind.lastWeek => arabic ? 'في الأسبوع اللي قبله' : 'in the week before',
      PeriodKind.lastMonth => arabic ? 'الشهر اللي فات' : 'last month',
      PeriodKind.today => arabic ? 'اليوم' : 'today',
      PeriodKind.yesterday => arabic ? 'أمس' : 'yesterday',
      PeriodKind.week => arabic ? 'في آخر 7 أيام' : 'in the last 7 days',
      PeriodKind.month => arabic ? 'هالشهر' : 'this month',
    };

const Set<String> _discretionary = {'food', 'shopping', 'entertainment'};

class BeazaAiAssistant {
  BeazaAiAssistant({
    required this.settings,
    this.llm,
    this.llmAllowed = false,
    DateTime Function()? clock,
    this.timeout = const Duration(seconds: 8),
    this.detector = const IntentDetector(),
    this.expenses = const ExpenseParser(),
    this.sanitizer = const AiContextSanitizer(),
    this.guard = const NumberGuard(),
  }) : _clock = clock ?? DateTime.now;

  final GuardrailSettings settings;

  /// Null: always answer with the built-in sentences.
  final AiLlmClient? llm;

  /// The person's separate consent to send the computed numbers to a model.
  final bool llmAllowed;
  final Duration timeout;
  final IntentDetector detector;
  final ExpenseParser expenses;
  final AiContextSanitizer sanitizer;
  final NumberGuard guard;
  final DateTime Function() _clock;

  Future<AssistantResponse> ask(String text, Iterable<LedgerEntry> entries,
      {String? previous}) async {
    final local = answerLocally(text, entries, previous: previous);
    final client = llm;
    // Drafts are shown as they are; an unknown request has nothing computed.
    if (client == null ||
        !llmAllowed ||
        local.intent == AssistantIntent.logExpense ||
        local.intent == AssistantIntent.unknown ||
        local.intent == AssistantIntent.outOfScope) {
      return local;
    }
    final arabic = detector.detect(text).arabic;
    final context = sanitizer.context(
      intent: local.intent,
      language: arabic ? 'ar-gulf' : 'en',
      question: text,
      metrics: local.referencedMetrics,
      draftReply: local.replyText,
    );
    try {
      final reply = await client
          .complete(LlmPrompt(system: kSystemPrompt, context: context))
          .timeout(timeout);
      final allowed = [
        local.replyText,
        sanitizer.sanitizeText(text),
        for (final m in local.referencedMetrics) m.display ?? '',
      ];
      if (!guard.allows(reply, allowed)) return local;
      return local.withText(reply.trim(), ResponseSource.llm);
    } catch (_) {
      // Offline, slow or failed: the built-in reply is already correct.
      return local;
    }
  }

  /// Offline answer: rules and arithmetic on the phone only.
  ///
  /// [previous] is the person's last question on this screen. A reply that
  /// only names a day or a period ("لا، بس الأحد", "and yesterday?") asks
  /// that same question again for the new period.
  ///
  /// [afford] is what the app's budget plan says about a price; without it
  /// a "can I buy it?" question is answered from the daily limit alone.
  AssistantResponse answerLocally(String text, Iterable<LedgerEntry> entries,
      {String? previous, AffordFacts? afford}) {
    var req = detector.detect(text);
    if (previous != null &&
        req.periodGiven &&
        req.category == null &&
        req.topic == null &&
        !detector.hasMoneyIntent(text)) {
      final before = detector.detect(previous);
      if (before.intent == AssistantIntent.spendingQuery &&
          !before.wantsRemaining) {
        req = before.forPeriodOf(req);
      }
    }
    final now = _clock();
    final s = SpendingSummaryBuilder(entries,
        settings: settings, today: Day.of(now));
    switch (req.intent) {
      case AssistantIntent.logExpense:
        final drafts = expenses.parse(text, now);
        if (drafts.isEmpty) return _unknown(req.arabic);
        return _log(drafts, req.arabic);
      case AssistantIntent.spendingQuery:
        switch (req.kind) {
          case QueryKind.overLimit:
            return _overLimit(s, req);
          case QueryKind.compare:
            return _compare(s, req.arabic);
          case QueryKind.projection:
            return _projection(s, req.arabic);
          case QueryKind.average:
            return _average(s, req);
          case QueryKind.topShop:
            return _topShop(s, req);
          case QueryKind.biggest:
            return _biggest(s, req);
          case QueryKind.total:
            break;
        }
        if (req.wantsRemaining) return _remaining(s, req.arabic);
        if (req.wantsBreakdown) return _breakdown(s, req);
        return _total(s, req);
      case AssistantIntent.guardrailAdvice:
        return _advice(s, req.arabic);
      case AssistantIntent.unknown:
        return _unknown(req.arabic);
      case AssistantIntent.canIBuy:
        return _canIBuy(s, req.priceFils!, afford, req.arabic);
      case AssistantIntent.outOfScope:
        return AssistantResponse(
          intent: AssistantIntent.outOfScope,
          replyText: kAssistantScope.reply(arabic: req.arabic),
        );
    }
  }

  Metric _money(String key, int fils, bool arabic) => Metric(
      key, fils, MetricUnit.fils,
      display: formatMoney(fils, arabic: arabic));

  AssistantResponse _log(List<DraftTransaction> drafts, bool ar) {
    final total = drafts.fold(0, (a, d) => a + d.amountFils);
    final items = [
      for (final d in drafts)
        '${d.merchantRaw ?? (ar ? 'مصروف' : 'expense')} ${formatMoney(d.amountFils, arabic: ar)}',
    ];
    final guessed = drafts.any((d) => d.amountGuessed);
    final b = StringBuffer(ar
        ? 'جهزت لك: ${items.join('، ')}.'
        : 'Ready to add: ${items.join(', ')}.');
    if (drafts.length > 1) {
      b.write(ar
          ? ' المجموع ${formatMoney(total, arabic: true)}.'
          : ' Total ${formatMoney(total, arabic: false)}.');
    }
    if (guessed) {
      b.write(ar
          ? ' ما كتبت العملة، فتأكد من المبلغ.'
          : ' No unit was written, so check the amount.');
    }
    b.write(ar ? ' أكّد قبل الحفظ.' : ' Confirm to save.');
    return AssistantResponse(
      intent: AssistantIntent.logExpense,
      replyText: b.toString(),
      draftTransactions: drafts,
      referencedMetrics: [
        for (var i = 0; i < drafts.length; i++)
          _money('draft_${i}_fils', drafts[i].amountFils, ar),
        _money('drafts_total_fils', total, ar),
      ],
    );
  }

  AssistantResponse _total(SpendingSummaryBuilder s, ParsedRequest req) {
    final ar = req.arabic;
    final p = Period.of(req.period, s.today, weekday: req.weekday);
    final topic = req.topic;
    final category = req.category;
    // A shop the person named ("at Starbucks", "في lulu"), matched on a
    // word of the shop names in their own list.
    final named = topic == null && category == null ? _namedShop(s, req.words) : null;
    if (named != null && named.match == null) {
      return _reply(
          ar
              ? 'ما لقيت مشتريات مسجلة باسم «${named.asked}» في قائمتك.'
              : 'I found no purchases named "${named.asked}" in your list.',
          []);
    }
    final shop = named?.match;
    bool where(ExtractionResult r) => shop != null
        ? _key(_shopOf(r)).contains(shop)
        : topic != null
            ? matchesTopic(topic, r)
            : category != null
                ? r.category == category
                : true;
    final total = s.total(p, where);
    final count = s.count(p, where);
    final label = shop != null
        ? (ar ? 'في ${named!.display}' : 'at ${named!.display}')
        : topic == Topic.coffee
        ? (ar ? 'على القهوة والكافيهات' : 'on coffee')
        : topic == Topic.delivery
            ? (ar ? 'على تطبيقات التوصيل' : 'on delivery apps')
            : category != null
                ? (ar
                    ? 'على ${bucketName(category, arabic: true)}'
                    : 'on ${bucketName(category, arabic: false)}')
                : '';
    final when = _periodText(p, s.today, arabic: ar);
    String text;
    if (total == 0) {
      text = ar
          ? 'ما صرفت شي $label $when.'
          : 'Nothing spent $label $when.';
    } else {
      final ops = ar
          ? (count == 1 ? 'عملية وحدة' : '$count عمليات')
          : (count == 1 ? '1 purchase' : '$count purchases');
      text = ar
          ? 'صرفت ${formatMoney(total, arabic: true)} $label $when ($ops).'
          : 'You spent ${formatMoney(total, arabic: false)} $label $when ($ops).';
    }
    if (topic != null) {
      text += ar ? ' (حسب أسماء المحلات)' : ' (by shop names)';
    }
    return AssistantResponse(
      intent: AssistantIntent.spendingQuery,
      replyText: text.replaceAll(RegExp(r' {2,}'), ' '),
      referencedMetrics: [
        _money('total_fils', total, ar),
        Metric('count', count, MetricUnit.count, display: '$count'),
        Metric('period_days', p.days, MetricUnit.days, display: '${p.days}'),
      ],
    );
  }

  AssistantResponse _breakdown(SpendingSummaryBuilder s, ParsedRequest req) {
    final ar = req.arabic;
    final p = Period.of(req.period, s.today, weekday: req.weekday);
    final buckets = s.byBucket(p);
    final when = _periodText(p, s.today, arabic: ar);
    if (buckets.isEmpty) {
      return AssistantResponse(
        intent: AssistantIntent.spendingQuery,
        replyText: ar ? 'ما في مصروفات $when.' : 'Nothing spent $when.',
        referencedMetrics: [_money('total_fils', 0, ar)],
      );
    }
    final total = buckets.fold(0, (a, b) => a + b.totalFils);
    final top = buckets.take(3).toList();
    final parts = [
      for (final b in top)
        ar
            ? '${bucketName(b.bucket, arabic: true)} ${formatMoney(b.totalFils, arabic: true)} (${b.percent}٪)'
            : '${bucketName(b.bucket, arabic: false)} ${formatMoney(b.totalFils, arabic: false)} (${b.percent}%)',
    ];
    final text = ar
        ? 'صرفت ${formatMoney(total, arabic: true)} $when. أكثرها: ${parts.join('، ')}.'
        : 'You spent ${formatMoney(total, arabic: false)} $when. Most went to: ${parts.join(', ')}.';
    return AssistantResponse(
      intent: AssistantIntent.spendingQuery,
      replyText: text,
      referencedMetrics: [
        _money('total_fils', total, ar),
        for (final b in top) ...[
          _money('bucket_${b.bucket}_fils', b.totalFils, ar),
          Metric('bucket_${b.bucket}_percent', b.percent, MetricUnit.percent,
              display: '${b.percent}'),
        ],
      ],
    );
  }

  AssistantResponse _remaining(SpendingSummaryBuilder s, bool ar) {
    final d = s.todaySummary();
    final metrics = [
      _money('spent_today_fils', d.spentFils, ar),
      _money('limit_fils', d.limitFils, ar),
      _money('remaining_fils', d.remainingFils, ar),
      Metric('percent_used', d.percentUsed, MetricUnit.percent,
          display: '${d.percentUsed}'),
    ];
    final String text;
    if (d.limitFils <= 0) {
      text = ar
          ? 'ما حطيت حد يومي بعد. حطه من الشاشة الرئيسية وأقول لك كم باقي.'
          : 'You have not set a daily limit yet. Set one on the home screen and I can tell you what is left.';
    } else if (d.remainingFils >= 0) {
      text = ar
          ? 'باقي لك ${formatMoney(d.remainingFils, arabic: true)} من حدك اليوم (${formatMoney(d.limitFils, arabic: true)}). صرفت ${formatMoney(d.spentFils, arabic: true)} لين الحين.'
          : 'You have ${formatMoney(d.remainingFils, arabic: false)} left of today\'s limit (${formatMoney(d.limitFils, arabic: false)}). Spent so far: ${formatMoney(d.spentFils, arabic: false)}.';
    } else {
      final over = formatMoney(-d.remainingFils, arabic: ar);
      metrics.add(_money('over_fils', -d.remainingFils, ar));
      text = ar
          ? 'تعديت حدك اليوم بـ $over. صرفت ${formatMoney(d.spentFils, arabic: true)} من ${formatMoney(d.limitFils, arabic: true)}.'
          : 'You are $over over today\'s limit: ${formatMoney(d.spentFils, arabic: false)} of ${formatMoney(d.limitFils, arabic: false)}.';
    }
    return AssistantResponse(
      intent: AssistantIntent.spendingQuery,
      replyText: text,
      referencedMetrics: metrics,
    );
  }

  AssistantResponse _advice(SpendingSummaryBuilder s, bool ar) {
    final d = s.todaySummary();
    final week = Period.of(PeriodKind.week, s.today);
    final micro = s.microIn(week);
    final metrics = <Metric>[];
    final lines = <String>[];

    if (d.limitFils <= 0) {
      lines.add(ar
          ? 'ما حطيت حد يومي. حط حد من الشاشة الرئيسية علشان أنبهك قبل لا تتعداه.'
          : 'Set a daily limit on the home screen so I can warn you before you pass it.');
    } else {
      final rem = formatMoney(d.remainingFils, arabic: ar);
      final pct = d.percentUsed;
      metrics
        ..add(_money('remaining_fils', d.remainingFils, ar))
        ..add(Metric('percent_used', pct, MetricUnit.percent, display: '$pct'));
      switch (d.level) {
        case AlertLevel.level3:
          final over = formatMoney(-d.remainingFils, arabic: ar);
          metrics.add(_money('over_fils', -d.remainingFils, ar));
          lines.add(ar
              ? 'تعديت حدك اليوم بـ $over. خفف باجر وأجّل أي شي مو ضروري.'
              : 'You are $over over today\'s limit. Go easy tomorrow and put off anything that can wait.');
        case AlertLevel.level2:
          lines.add(ar
              ? 'صرفت $pct٪ من حدك اليوم، باقي لك $rem بس. هدّها لين باجر.'
              : 'You have used $pct% of today\'s limit; only $rem left. Slow down until tomorrow.');
        case AlertLevel.level1:
          lines.add(ar
              ? 'راح $pct٪ من حدك اليوم، باقي لك $rem.'
              : '$pct% of today\'s limit is gone; $rem left.');
        case AlertLevel.normal:
          lines.add(ar
              ? 'ماشي زين! صرفت $pct٪ بس من حدك اليوم، باقي لك $rem.'
              : 'Going well: $pct% of today\'s limit used, $rem left.');
      }
    }

    if (micro.count >= 5) {
      metrics
        ..add(Metric('micro_count_week', micro.count, MetricUnit.count,
            display: '${micro.count}'))
        ..add(_money('micro_total_week_fils', micro.totalFils, ar));
      final m = formatMoney(micro.totalFils, arabic: ar);
      lines.add(ar
          ? 'عندك ${micro.count} مصاريف صغيرة في آخر 7 أيام مجموعها $m، الصغيرة تتجمع.'
          : '${micro.count} small purchases in the last 7 days add up to $m.');
    }

    lines.addAll(_habits(s, week, ar, metrics));

    final top = s
        .byBucket(week)
        .where((b) => _discretionary.contains(b.bucket) && b.totalFils >= 10000)
        .firstOrNull;
    if (top != null) {
      final keep = top.totalFils ~/ 5;
      metrics.add(_money('trim_${top.bucket}_fils', keep, ar));
      lines.add(ar
          ? 'لو خففت ${bucketName(top.bucket, arabic: true)} 20٪ توفّر تقريباً ${formatMoney(keep, arabic: true)} بالأسبوع.'
          : 'Spending 20% less on ${bucketName(top.bucket, arabic: false)} would keep about ${formatMoney(keep, arabic: false)} a week.');
    }

    return AssistantResponse(
      intent: AssistantIntent.guardrailAdvice,
      replyText: lines.join(' '),
      referencedMetrics: metrics,
    );
  }

  /// Concrete swaps from this week's own habits, the way someone who helps
  /// students in Bahrain organise their money would put it: coffee and
  /// karak runs, delivery orders, late nights and the weekend (Thursday to
  /// Saturday, as in the app's budget). Only counts and totals worked out
  /// here are quoted; at most two habits, the biggest first.
  List<String> _habits(
      SpendingSummaryBuilder s, Period week, bool ar, List<Metric> metrics) {
    final found = <(int, String)>[];
    String n(int c) => '$c';

    final coffee = s.count(week, (r) => matchesTopic(Topic.coffee, r));
    final coffeeFils = s.total(week, (r) => matchesTopic(Topic.coffee, r));
    if (coffee >= 4 && coffeeFils >= kHabitMinFils) {
      metrics
        ..add(Metric('coffee_count_week', coffee, MetricUnit.count, display: n(coffee)))
        ..add(_money('coffee_week_fils', coffeeFils, ar));
      final m = formatMoney(coffeeFils, arabic: ar);
      found.add((coffeeFils, ar
          ? 'القهوة والكرك $coffee مرات هالأسبوع بـ $m. سوّ قهوتك بالبيت أيام الدوام وخل الكافيه طلعة الويكند.'
          : 'Coffee and karak $coffee times this week, $m. Make it at home on study days and keep the café for the weekend.'));
    }

    final delivery = s.count(week, (r) => matchesTopic(Topic.delivery, r));
    final deliveryFils = s.total(week, (r) => matchesTopic(Topic.delivery, r));
    if (delivery >= 3 && deliveryFils >= kHabitMinFils) {
      metrics
        ..add(Metric('delivery_count_week', delivery, MetricUnit.count, display: n(delivery)))
        ..add(_money('delivery_week_fils', deliveryFils, ar));
      final m = formatMoney(deliveryFils, arabic: ar);
      found.add((deliveryFils, ar
          ? 'طلبت توصيل $delivery مرات بـ $m. اختار استلام من المطعم بدل التوصيل، أو جهّز غداك من الليل.'
          : '$delivery delivery orders, $m. Pick up instead of delivery, or pack lunch the night before.'));
    }

    bool late(ExtractionResult r) {
      final h = r.timestamp!.toUtc().add(kBahrainOffset).hour;
      return h >= 22 || h < 3;
    }

    final lateCount = s.count(week, late);
    final lateFils = s.total(week, late);
    if (lateCount >= 3 && lateFils >= kHabitMinFils) {
      metrics
        ..add(Metric('late_count_week', lateCount, MetricUnit.count, display: n(lateCount)))
        ..add(_money('late_week_fils', lateFils, ar));
      final m = formatMoney(lateFils, arabic: ar);
      found.add((lateFils, ar
          ? '$lateCount مشتريات بعد 10 الليل بـ $m. تعشّى قبل لا تسهر، وشيل التطبيقات من أول شاشة.'
          : '$lateCount purchases after 10 pm, $m. Eat before a late night and move the delivery apps off your home screen.'));
    }

    bool weekend(ExtractionResult r) {
      final w = r.timestamp!.toUtc().add(kBahrainOffset).weekday;
      return w == DateTime.thursday || w == DateTime.friday || w == DateTime.saturday;
    }

    final weekTotal = s.total(week);
    final weekendFils = s.total(week, weekend);
    if (weekendFils >= kWeekendMinFils && weekendFils * 2 >= weekTotal) {
      metrics.add(_money('weekend_week_fils', weekendFils, ar));
      final m = formatMoney(weekendFils, arabic: ar);
      found.add((weekendFils, ar
          ? 'الويكند (الخميس للسبت) أخذ $m، أكثر من نص الأسبوع. قرر مبلغ الطلعة قبل لا تطلع، وإذا خلص خلاص.'
          : 'The weekend (Thursday to Saturday) took $m, over half the week. Decide what the outing costs before you go, and stop there.'));
    }

    found.sort((a, b) => b.$1.compareTo(a.$1));
    return [for (final f in found.take(2)) f.$2];
  }

  /// A shop name written one way: Arabic letter forms unified, lower
  /// case, no spaces or marks ("مرفأ الأطفال" and "مرفأالاطفال" match).
  static String _key(String s) =>
      normalizeText(s).replaceAll(RegExp(r'[^a-z0-9ء-ي]'), '');

  /// The shop the question names, if it names one: the words left after
  /// the question's own words, matched against the shop names of the last
  /// 90 days. [match] is null when a name was given ("دفعت لـ…", "at …")
  /// but no purchase has it.
  ({String asked, String? match, String display})? _namedShop(
      SpendingSummaryBuilder s, List<String> words) {
    var pointed = false;
    final rest = <String>[];
    for (var i = 0; i < words.length; i++) {
      var w = words[i];
      if (w == kBreak || isNumberToken(w)) continue;
      if (const {'في', 'عند', 'at', 'from'}.contains(w)) {
        pointed = true;
        continue;
      }
      if (isQuestionWord(w)) continue;
      // "دفعت لمرفأ…": a joined ل points at a name. A joined ب is often
      // part of the word, so it is dropped for matching only.
      for (final p in const ['لل', 'ل', 'ب']) {
        if (w.startsWith(p) && w.length - p.length >= 3) {
          final cut = w.substring(p.length);
          if (!isQuestionWord(cut)) {
            w = cut;
            if (p != 'ب') pointed = true;
          }
          break;
        }
      }
      if (_key(w).length >= 3) rest.add(w);
    }
    if (rest.isEmpty) return null;
    final names = <String, int>{};
    for (final r in s.items(Period(PeriodKind.month, s.today.addDays(-90), s.today))) {
      final n = _shopOf(r);
      if (n.isNotEmpty) names[n] = (names[n] ?? 0) + 1;
    }
    for (final candidate in [rest.join(), ...rest]) {
      final k = _key(candidate);
      final hits = names.keys.where((n) => _key(n).contains(k)).toList()
        ..sort((a, b) => names[b]!.compareTo(names[a]!));
      if (hits.isNotEmpty) return (asked: candidate, match: k, display: hits.first);
    }
    return pointed ? (asked: rest.join(' '), match: null, display: '') : null;
  }

  static String _shopOf(ExtractionResult r) =>
      (r.merchantNorm ?? r.merchantRaw ?? '').trim();

  AssistantResponse _reply(String text, List<Metric> metrics) =>
      AssistantResponse(
        intent: AssistantIntent.spendingQuery,
        replyText: text.replaceAll(RegExp(r' {2,}'), ' '),
        referencedMetrics: metrics,
      );

  /// The single largest purchase in the period.
  AssistantResponse _biggest(SpendingSummaryBuilder s, ParsedRequest req) {
    final ar = req.arabic;
    final p = Period.of(req.period, s.today, weekday: req.weekday);
    final when = _periodText(p, s.today, arabic: ar);
    final items = s.items(p);
    if (items.isEmpty) {
      return _reply(ar ? 'ما صرفت شي $when.' : 'Nothing spent $when.', []);
    }
    final top = items.reduce((a, b) => b.amountFils! > a.amountFils! ? b : a);
    final shop = _shopOf(top);
    final at = shop.isEmpty ? '' : (ar ? ' في $shop' : ' at $shop');
    final day = Day.of(top.timestamp!);
    final dayText = ar
        ? 'يوم ${_dayAr[dayOfWeek(day) - 1]}'
        : 'on ${_dayEn[dayOfWeek(day) - 1]}';
    return _reply(
        ar
            ? 'أكبر مصروف $when: ${formatMoney(top.amountFils!, arabic: true)}$at، $dayText.'
            : 'Your biggest purchase $when: ${formatMoney(top.amountFils!, arabic: false)}$at, $dayText.',
        [_money('biggest_fils', top.amountFils!, ar)]);
  }

  /// The shop with the most money spent (and how many visits).
  AssistantResponse _topShop(SpendingSummaryBuilder s, ParsedRequest req) {
    final ar = req.arabic;
    final p = Period.of(req.period, s.today, weekday: req.weekday);
    final when = _periodText(p, s.today, arabic: ar);
    final totals = <String, int>{};
    final counts = <String, int>{};
    final names = <String, String>{};
    for (final r in s.items(p)) {
      final name = _shopOf(r);
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      names.putIfAbsent(key, () => name);
      totals[key] = (totals[key] ?? 0) + r.amountFils!;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    if (totals.isEmpty) {
      return _reply(
          ar ? 'ما في مشتريات من محلات $when.' : 'No shop purchases $when.', []);
    }
    final key = totals.keys.reduce((a, b) => totals[b]! > totals[a]! ? b : a);
    final n = counts[key]!;
    final times = ar ? (n == 1 ? 'مرة وحدة' : '$n مرات') : (n == 1 ? 'once' : '$n times');
    return _reply(
        ar
            ? 'أكثر محل صرفت فيه $when: ${names[key]}، ${formatMoney(totals[key]!, arabic: true)} ($times).'
            : 'The shop you spent most at $when: ${names[key]}, ${formatMoney(totals[key]!, arabic: false)} ($times).',
        [
          _money('shop_fils', totals[key]!, ar),
          Metric('shop_count', n, MetricUnit.count, display: '$n'),
        ]);
  }

  /// The last 7 days against the 7 before.
  AssistantResponse _compare(SpendingSummaryBuilder s, bool ar) {
    final now = s.total(Period.of(PeriodKind.week, s.today));
    final before = s.total(Period.of(PeriodKind.lastWeek, s.today));
    final metrics = [
      _money('week_fils', now, ar),
      _money('week_before_fils', before, ar),
    ];
    String m(int f) => formatMoney(f, arabic: ar);
    if (before == 0) {
      return _reply(
          ar
              ? 'آخر 7 أيام صرفت ${m(now)}، والأسبوع اللي قبله ما في صرف مسجّل علشان أقارن.'
              : 'You spent ${m(now)} in the last 7 days; nothing is recorded for the week before, so there is nothing to compare.',
          metrics);
    }
    final diff = (now - before).abs();
    final pct = percentOf(diff, before);
    metrics
      ..add(_money('diff_fils', diff, ar))
      ..add(Metric('diff_percent', pct, MetricUnit.percent, display: '$pct'));
    final String text;
    if (now == before) {
      text = ar
          ? 'نفس الشي: ${m(now)} آخر 7 أيام والأسبوع اللي قبله.'
          : 'The same: ${m(now)} in the last 7 days and in the week before.';
    } else if (now > before) {
      text = ar
          ? 'آخر 7 أيام صرفت ${m(now)}، أكثر من الأسبوع اللي قبله (${m(before)}) بـ ${m(diff)}، يعني $pct٪. شوف وين زاد من «وين راحت فلوسي؟».'
          : 'You spent ${m(now)} in the last 7 days, ${m(diff)} ($pct%) more than the week before (${m(before)}). Ask "Where did my money go?" to see what grew.';
    } else {
      text = ar
          ? 'آخر 7 أيام صرفت ${m(now)}، أقل من الأسبوع اللي قبله (${m(before)}) بـ ${m(diff)}، يعني $pct٪. كمّل جذي.'
          : 'You spent ${m(now)} in the last 7 days, ${m(diff)} ($pct%) less than the week before (${m(before)}). Keep it up.';
    }
    return _reply(text, metrics);
  }

  /// Average a day over the period, against the daily limit.
  AssistantResponse _average(SpendingSummaryBuilder s, ParsedRequest req) {
    final ar = req.arabic;
    final kind = req.period == PeriodKind.today || req.period == PeriodKind.weekday
        ? PeriodKind.week
        : req.period;
    final p = Period.of(kind, s.today);
    final total = s.total(p);
    final days = p.days;
    final avg = total ~/ days;
    String m(int f) => formatMoney(f, arabic: ar);
    final when = _periodText(p, s.today, arabic: ar);
    final metrics = [
      _money('average_fils', avg, ar),
      _money('total_fils', total, ar),
      Metric('days', days, MetricUnit.days, display: '$days'),
    ];
    var text = ar
        ? 'معدل صرفك $when: ${m(avg)} باليوم (${m(total)} على $days أيام).'
        : 'Your average $when: ${m(avg)} a day (${m(total)} over $days days).';
    final limit = s.settings.dailyLimitFils;
    if (limit > 0) {
      metrics.add(_money('limit_fils', limit, ar));
      text += avg > limit
          ? (ar ? ' هذا فوق حدك (${m(limit)})، فلازم تخفف شوي.' : ' That is above your limit (${m(limit)}), so ease off a little.')
          : (ar ? ' وهذا ضمن حدك (${m(limit)}).' : ' That is within your limit (${m(limit)}).');
    }
    return _reply(text, metrics);
  }

  /// This month so far, and where it ends at the same pace.
  AssistantResponse _projection(SpendingSummaryBuilder s, bool ar) {
    final p = Period.of(PeriodKind.month, s.today);
    final total = s.total(p);
    final soFar = s.today.day;
    final inMonth = Day(s.today.year, s.today.month + 1, 1).addDays(-1).day;
    final end = total * inMonth ~/ soFar;
    String m(int f) => formatMoney(f, arabic: ar);
    return _reply(
        ar
            ? 'لين اليوم صرفت ${m(total)} هالشهر في $soFar يوم. إذا كملت بنفس المعدل، بتوصل تقريباً ${m(end)} آخر الشهر.'
            : 'So far this month you have spent ${m(total)} in $soFar days. At the same pace you would reach about ${m(end)} by the end of the month.',
        [
          _money('month_fils', total, ar),
          _money('month_end_fils', end, ar),
          Metric('days_so_far', soFar, MetricUnit.days, display: '$soFar'),
        ]);
  }

  /// How many days passed the daily limit.
  AssistantResponse _overLimit(SpendingSummaryBuilder s, ParsedRequest req) {
    final ar = req.arabic;
    if (s.settings.dailyLimitFils <= 0) {
      return _reply(
          ar
              ? 'ما عندك حد يومي، فما في أيام تعديته. حط حدك من الشاشة الرئيسية.'
              : 'You have no daily limit, so no days over it. Set one on the home screen.',
          []);
    }
    final kind = req.period == PeriodKind.month || req.period == PeriodKind.lastMonth
        ? req.period
        : PeriodKind.week;
    final p = Period.of(kind, s.today);
    final n = s.daysOver(p);
    final days = p.days;
    final when = _periodText(p, s.today, arabic: ar);
    return _reply(
        n == 0
            ? (ar ? 'ما تعديت حدك ولا يوم $when. عاش!' : 'You stayed within your limit every day $when. Well done.')
            : (ar
                ? 'تعديت حدك $n من $days أيام $when.'
                : 'You went over your limit on $n of $days days $when.'),
        [
          Metric('days_over', n, MetricUnit.days, display: '$n'),
          Metric('days', days, MetricUnit.days, display: '$days'),
        ]);
  }

  /// Straight talk about a price, the way a Bahraini who helps students
  /// with money would put it: what it does to the daily limit, and what to
  /// do if it does not fit. Every number is worked out here in fils.
  AssistantResponse _canIBuy(SpendingSummaryBuilder s, int price,
      AffordFacts? afford, bool ar) {
    String m(int f) => formatMoney(f, arabic: ar);
    final d = s.todaySummary();
    final metrics = <Metric>[_money('price_fils', price, ar)];
    String text;
    final monthLeft = afford?.monthLeftFils;
    final now = afford?.limitFromTomorrowFils;
    final after = afford?.limitIfBoughtFils;
    if (monthLeft != null && price > monthLeft) {
      metrics.add(_money('month_left_fils', monthLeft, ar));
      text = ar
          ? '${m(price)} أكثر من كل اللي باقي لك هالشهر (${m(monthLeft)}). لا تاخذه الحين. إذا تبيه، حطه هدف توفير في بيزة وجمّع له من الشهر الجاي.'
          : '${m(price)} is more than everything left for this month (${m(monthLeft)}). Don\'t buy it now. If you want it, make it a saving goal in Beaza and put money towards it from next month.';
    } else if (d.limitFils > 0 && price <= d.remainingFils) {
      metrics.add(_money('left_after_fils', d.remainingFils - price, ar));
      text = ar
          ? 'يمديك. لو صرفت ${m(price)} اليوم، بيظل لك ${m(d.remainingFils - price)} من حدك.'
          : 'Yes. If you spend ${m(price)} today, ${m(d.remainingFils - price)} of your limit is left.';
    } else if (now != null && after != null) {
      metrics
        ..add(_money('limit_now_fils', now, ar))
        ..add(_money('limit_after_fils', after, ar));
      final over = d.limitFils > 0
          ? (ar
              ? 'هذا أكثر من الباقي من حدك اليوم (${m(d.remainingFils < 0 ? 0 : d.remainingFils)}). '
              : 'That is more than what is left of today\'s limit (${m(d.remainingFils < 0 ? 0 : d.remainingFils)}). ')
          : '';
      text = over + (ar
          ? 'يمديك، بس لازم تقلل مصاريفك: حدك اليومي من باجر بينزل من ${m(now)} إلى ${m(after)} لين آخر الشهر.'
          : 'You can, but you will have to cut back: from tomorrow your daily limit drops from ${m(now)} to ${m(after)} until the end of the month.');
      if (after * 2 < now) {
        text += ar
            ? ' هذا أقل من نص حدك، فإذا مو مستعجل عليه أجّله للشهر الجاي أو جمّع له.'
            : ' That is less than half your limit, so if it can wait, leave it to next month or save up for it.';
      }
    } else if (monthLeft != null) {
      metrics.add(_money('month_left_fils', monthLeft, ar));
      text = ar
          ? 'يمديك من الباقي لهالشهر (${m(monthLeft)})، وباجر يبدأ شهر جديد.'
          : 'It fits in what is left this month (${m(monthLeft)}), and a new month starts tomorrow.';
    } else if (d.limitFils <= 0) {
      text = ar
          ? 'ما عندك حد يومي، فما أقدر أقول إذا يمديك. حط حدك أو خله ينحسب من دخلك من الشاشة الرئيسية، وارجع اسألني.'
          : 'You have no daily limit yet, so I can\'t say. Set one, or work it out from your income on the home screen, and ask me again.';
    } else if (price <= d.remainingFils) {
      metrics.add(_money('left_after_fils', d.remainingFils - price, ar));
      text = ar
          ? 'يدخل في حدك اليوم، وبيظل لك ${m(d.remainingFils - price)}.'
          : 'It fits in today\'s limit, with ${m(d.remainingFils - price)} left after it.';
    } else {
      final limit = d.limitFils;
      final days = (price + limit - 1) ~/ limit;
      final half = limit ~/ 2;
      metrics
        ..add(_money('limit_fils', limit, ar))
        ..add(Metric('days_of_limit', days, MetricUnit.days, display: '$days'));
      text = ar
          ? '${m(price)} تساوي $days يوم من حدك اليومي (${m(limit)}). يعني لازم تقلل مصاريفك علشانه.'
          : '${m(price)} is $days days of your daily limit (${m(limit)}), so you would have to cut back for it.';
      if (half > 0) {
        final saveDays = (price + half - 1) ~/ half;
        metrics
          ..add(_money('half_limit_fils', half, ar))
          ..add(Metric('save_days', saveDays, MetricUnit.days, display: '$saveDays'));
        text += ar
            ? ' لو توفر نص حدك كل يوم (${m(half)})، بتجمعه في $saveDays يوم. حطه هدف توفير في بيزة وتابع.'
            : ' Put aside half your limit each day (${m(half)}) and you will have it in $saveDays days. Make it a saving goal in Beaza.';
      }
    }
    return AssistantResponse(
      intent: AssistantIntent.canIBuy,
      replyText: text,
      referencedMetrics: metrics,
    );
  }

  AssistantResponse _unknown(bool ar) => AssistantResponse(
        intent: AssistantIntent.unknown,
        replyText: ar
            ? 'ما فهمت عليك. جرّب: «كم صرفت هالأسبوع؟» أو «وين راحت فلوسي؟» أو «شريت كرك بربيتين».'
            : 'Sorry, I did not get that. Try "How much did I spend this week?" or "coffee 0.800 BD".',
      );
}
