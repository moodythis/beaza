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

const String kSystemPrompt = '''
You are the assistant inside Beaza, a daily spending app for young people in Bahrain.
Rewrite "draft_reply" in a friendly, short way (at most two sentences).
If "language" is "ar-gulf", write in plain Gulf Arabic; otherwise in English.
Use only the numbers that appear in "draft_reply" or in "metrics" (use their "display" text exactly).
Never add, subtract, multiply or compute percentages yourself, and never invent a number.
Do not recommend banks, loans, investments or any financial product.''';

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

String _periodText(PeriodKind p, {required bool arabic}) => switch (p) {
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

  Future<AssistantResponse> ask(
      String text, Iterable<LedgerEntry> entries) async {
    final local = answerLocally(text, entries);
    final client = llm;
    // Drafts are shown as they are; an unknown request has nothing computed.
    if (client == null ||
        !llmAllowed ||
        local.intent == AssistantIntent.logExpense ||
        local.intent == AssistantIntent.unknown) {
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
  AssistantResponse answerLocally(String text, Iterable<LedgerEntry> entries) {
    final req = detector.detect(text);
    final now = _clock();
    final s = SpendingSummaryBuilder(entries,
        settings: settings, today: Day.of(now));
    switch (req.intent) {
      case AssistantIntent.logExpense:
        final drafts = expenses.parse(text, now);
        if (drafts.isEmpty) return _unknown(req.arabic);
        return _log(drafts, req.arabic);
      case AssistantIntent.spendingQuery:
        if (req.wantsRemaining) return _remaining(s, req.arabic);
        if (req.wantsBreakdown) return _breakdown(s, req);
        return _total(s, req);
      case AssistantIntent.guardrailAdvice:
        return _advice(s, req.arabic);
      case AssistantIntent.unknown:
        return _unknown(req.arabic);
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
    final p = Period.of(req.period, s.today);
    final topic = req.topic;
    final category = req.category;
    bool where(ExtractionResult r) => topic != null
        ? matchesTopic(topic, r)
        : category != null
            ? r.category == category
            : true;
    final total = s.total(p, where);
    final count = s.count(p, where);
    final label = topic == Topic.coffee
        ? (ar ? 'على القهوة والكافيهات' : 'on coffee')
        : topic == Topic.delivery
            ? (ar ? 'على تطبيقات التوصيل' : 'on delivery apps')
            : category != null
                ? (ar
                    ? 'على ${bucketName(category, arabic: true)}'
                    : 'on ${bucketName(category, arabic: false)}')
                : '';
    final when = _periodText(req.period, arabic: ar);
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
    final p = Period.of(req.period, s.today);
    final buckets = s.byBucket(p);
    final when = _periodText(req.period, arabic: ar);
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

  AssistantResponse _unknown(bool ar) => AssistantResponse(
        intent: AssistantIntent.unknown,
        replyText: ar
            ? 'ما فهمت عليك. جرّب: «كم صرفت هالأسبوع؟» أو «وين راحت فلوسي؟» أو «شريت كرك بربيتين».'
            : 'Sorry, I did not get that. Try "How much did I spend this week?" or "coffee 0.800 BD".',
      );
}
