/// Markdown report for an evaluation run (NFR-10: everything needed to
/// reproduce the run is written at the top).
library;

import 'metrics.dart';

class RunInfo {
  const RunInfo({
    required this.dataName,
    required this.dataFingerprint,
    required this.split,
    required this.devCount,
    required this.testCount,
    required this.templateVersion,
    required this.command,
  });

  final String dataName;
  final String dataFingerprint;
  final String split;
  final int devCount;
  final int testCount;
  final String templateVersion;
  final String command;

  Map<String, dynamic> toJson() => {
        'data': dataName,
        'data_fnv1a': dataFingerprint,
        'split': split,
        'dev_messages': devCount,
        'test_messages': testCount,
        'template_set': templateVersion,
        'command': command,
      };
}

String _pct(double v) => v.isNaN ? '-' : '${(v * 100).toStringAsFixed(1)}%';
String _dec(double v) => v.isNaN ? '-' : v.toStringAsFixed(3);

String markdownReport(
  RunInfo info,
  List<(String, String, Evaluation)> runs, {
  List<String> notes = const [],
  int maxErrors = 200,
}) {
  final b = StringBuffer()
    ..writeln('# Beaza extraction evaluation')
    ..writeln()
    ..writeln('| Setting | Value |')
    ..writeln('|---|---|')
    ..writeln('| Data | `${info.dataName}` (FNV-1a `${info.dataFingerprint}`) |')
    ..writeln('| Split | ${info.split} |')
    ..writeln('| Messages scored (test part) | ${info.testCount} |')
    ..writeln('| Messages in dev part | ${info.devCount} |')
    ..writeln('| Template set | ${info.templateVersion} |')
    ..writeln('| Command | `${info.command}` |')
    ..writeln();
  for (final n in notes) {
    b.writeln('> $n');
    b.writeln();
  }

  b
    ..writeln('## Summary')
    ..writeln()
    ..writeln('| System | Transaction F1 | Amount exact | Field micro F1 | '
        'Message exact | Accepted without review |')
    ..writeln('|---|---|---|---|---|---|');
  for (final (id, desc, ev) in runs) {
    final o = ev.overall;
    b.writeln('| $id: $desc | ${_dec(o.detection.f1)} | '
        '${_pct(o.amountExactRate)} | ${_dec(o.micro.f1)} | '
        '${_pct(o.exactMatchRate)} | ${_pct(o.acceptedRate)} |');
  }
  b
    ..writeln()
    ..writeln('NFR-5 targets: transaction F1 >= 0.95, amount exact match >= 98%, '
        'merchant normalization accuracy >= 85% (normalizer not built yet).')
    ..writeln();

  for (final (id, _, ev) in runs) {
    final o = ev.overall;
    b
      ..writeln('## $id')
      ..writeln()
      ..writeln('Messages: ${o.messages}. Gold transactions: '
          '${o.goldTransactions}.')
      ..writeln()
      ..writeln('### Transaction or not')
      ..writeln()
      ..writeln('| TP | FP | FN | Precision | Recall | F1 |')
      ..writeln('|---|---|---|---|---|---|')
      ..writeln('| ${o.detection.tp} | ${o.detection.fp} | ${o.detection.fn} | '
          '${_dec(o.detection.precision)} | ${_dec(o.detection.recall)} | '
          '${_dec(o.detection.f1)} |')
      ..writeln()
      ..writeln('### Fields')
      ..writeln()
      ..writeln('| Field | Support | TP | FP | FN | Precision | Recall | F1 |')
      ..writeln('|---|---|---|---|---|---|---|---|');
    for (final e in o.fields.entries) {
      final c = e.value;
      b.writeln('| ${e.key} | ${c.support} | ${c.tp} | ${c.fp} | ${c.fn} | '
          '${_dec(c.precision)} | ${_dec(c.recall)} | ${_dec(c.f1)} |');
    }
    final m = o.micro;
    b
      ..writeln('| **micro** | ${m.support} | ${m.tp} | ${m.fp} | ${m.fn} | '
          '${_dec(m.precision)} | ${_dec(m.recall)} | ${_dec(m.f1)} |')
      ..writeln();

    void group(String title, Map<String, Scores> g) {
      b
        ..writeln('### $title')
        ..writeln()
        ..writeln('| Group | Messages | Gold tx | Transaction F1 | '
            'Amount exact | Field micro F1 | Message exact |')
        ..writeln('|---|---|---|---|---|---|---|');
      final keys = g.keys.toList()..sort();
      for (final k in keys) {
        final s = g[k]!;
        b.writeln('| $k | ${s.messages} | ${s.goldTransactions} | '
            '${_dec(s.detection.f1)} | ${_pct(s.amountExactRate)} | '
            '${_dec(s.micro.f1)} | ${_pct(s.exactMatchRate)} |');
      }
      b.writeln();
    }

    group('By sender family', ev.bySender);
    group('By language', ev.byLanguage);

    b
      ..writeln('### Errors')
      ..writeln()
      ..writeln('Message ids only; open the data file to see the text.')
      ..writeln();
    if (ev.errors.isEmpty) {
      b.writeln('None.');
    } else {
      b
        ..writeln('| Id | Field | Gold | Predicted |')
        ..writeln('|---|---|---|---|');
      for (final e in ev.errors.take(maxErrors)) {
        b.writeln('| ${e.id} | ${e.field} | ${_cell(e.gold)} | '
            '${_cell(e.predicted)} |');
      }
      if (ev.errors.length > maxErrors) {
        b.writeln('\n${ev.errors.length - maxErrors} more in the JSON file.');
      }
    }
    b.writeln();
  }
  return b.toString();
}

String agreementReport(String nameA, String nameB, Agreement a) {
  final b = StringBuffer()
    ..writeln('# Annotator agreement')
    ..writeln()
    ..writeln('A: `$nameA`, B: `$nameB`.')
    ..writeln()
    ..writeln('| Measure | Value |')
    ..writeln('|---|---|')
    ..writeln('| Messages labelled by both | ${a.shared} |')
    ..writeln('| Only in A / only in B | ${a.onlyA} / ${a.onlyB} |')
    ..writeln('| Transaction or not: observed agreement | ${_pct(a.observed)} |')
    ..writeln("| Transaction or not: Cohen's kappa | ${_dec(a.kappa)} |");
  for (final e in a.fieldAgreement.entries) {
    b.writeln('| ${e.key} agreement (both say transaction) | ${_pct(e.value)} |');
  }
  b
    ..writeln()
    ..writeln('## Disagreements')
    ..writeln();
  if (a.disagreements.isEmpty) {
    b.writeln('None.');
  } else {
    b
      ..writeln('| Id | Field | A | B |')
      ..writeln('|---|---|---|---|');
    for (final d in a.disagreements) {
      b.writeln('| ${d.id} | ${d.field} | ${_cell(d.gold)} | '
          '${_cell(d.predicted)} |');
    }
  }
  return b.toString();
}

String _cell(String? v) =>
    v == null ? '-' : v.replaceAll('|', r'\|').replaceAll('\n', ' ');
