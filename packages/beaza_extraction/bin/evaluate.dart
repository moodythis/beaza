// Evaluation harness command line (SRS FR-6.3, FR-6.4, NFR-10).
//
//   dart run bin/evaluate.dart --data eval/seed.jsonl
//   dart run bin/evaluate.dart --data gold.jsonl --split time --out eval/results
//   dart run bin/evaluate.dart --data gold.jsonl --split template --holdout ila
//   dart run bin/evaluate.dart --agreement a.jsonl b.jsonl
//
// Writes report.md and results.json to --out (default eval/results).
import 'dart:convert';
import 'dart:io';

import 'package:beaza_extraction/beaza_extraction.dart';
import 'package:beaza_extraction/evaluation.dart';

const _usage = '''
Usage:
  dart run bin/evaluate.dart --data FILE [options]
  dart run bin/evaluate.dart --agreement FILE_A FILE_B [--out DIR]

Options:
  --system IDS         Comma-separated systems (default B1). Built: B1.
  --split KIND         all | random | time | template (default all)
  --holdout FAMILIES   Sender families held out for --split template, e.g. ila,bisb
  --test-fraction F    Test share for random and time splits (default 0.3)
  --seed N             Seed for the random split (default 42)
  --out DIR            Output folder (default eval/results)
  --check              Only validate the data file
''';

Never _fail(String msg) {
  stderr.writeln(msg);
  stderr.writeln();
  stderr.writeln(_usage);
  exit(64);
}

void main(List<String> args) {
  final opts = <String, String>{};
  final flags = <String>{};
  final agreementFiles = <String>[];
  for (var i = 0; i < args.length; i++) {
    final a = args[i];
    if (a == '--help' || a == '-h') {
      stdout.write(_usage);
      return;
    } else if (a == '--check') {
      flags.add('check');
    } else if (a == '--agreement') {
      if (i + 2 >= args.length) _fail('--agreement needs two files');
      agreementFiles
        ..add(args[++i])
        ..add(args[++i]);
    } else if (a.startsWith('--')) {
      if (i + 1 >= args.length) _fail('$a needs a value');
      opts[a.substring(2)] = args[++i];
    } else {
      _fail('Unknown argument: $a');
    }
  }
  final out = Directory(opts['out'] ?? 'eval/results');

  if (agreementFiles.isNotEmpty) {
    final a = _load(agreementFiles[0]);
    final b = _load(agreementFiles[1]);
    final ag = agreement(a.$2, b.$2);
    out.createSync(recursive: true);
    final md = agreementReport(agreementFiles[0], agreementFiles[1], ag);
    File('${out.path}/agreement.md').writeAsStringSync(md);
    File('${out.path}/agreement.json').writeAsStringSync(
        const JsonEncoder.withIndent('  ').convert(ag.toJson()));
    stdout.write(md);
    return;
  }

  final dataPath = opts['data'] ?? _fail('--data is required');
  final (content, messages) = _load(dataPath);
  if (flags.contains('check')) {
    final tx = messages.where((m) => m.label.isTransaction).length;
    stdout.writeln('$dataPath: ${messages.length} messages, $tx transactions. OK.');
    return;
  }

  final kind = SplitKind.values.firstWhere(
      (k) => k.name == (opts['split'] ?? 'all'),
      orElse: () => _fail('Unknown split: ${opts['split']}'));
  final holdout = <SenderFamily>{};
  for (final name in (opts['holdout'] ?? '').split(',')) {
    if (name.trim().isEmpty) continue;
    holdout.add(SenderFamily.values.firstWhere(
        (f) => f.name.toLowerCase() == name.trim().toLowerCase(),
        orElse: () => _fail('Unknown sender family: $name. Use one of '
            '${SenderFamily.values.map((f) => f.name).join(', ')}')));
  }
  final fraction = double.tryParse(opts['test-fraction'] ?? '0.3') ??
      _fail('--test-fraction must be a number');
  final seed = int.tryParse(opts['seed'] ?? '42') ?? _fail('--seed must be an integer');

  final Split split;
  try {
    split = splitMessages(messages,
        kind: kind, testFraction: fraction, seed: seed, holdout: holdout);
  } on ArgumentError catch (e) {
    _fail('${e.message}');
  }

  final runs = <(String, String, Evaluation)>[];
  final notes = <String>[];
  for (final id in (opts['system'] ?? 'B1').split(',')) {
    final sys = systemById(id.trim());
    if (sys == null) {
      final planned = plannedSystems[id.trim().toUpperCase()];
      if (planned == null) _fail('Unknown system: $id');
      notes.add('${id.trim().toUpperCase()} skipped: $planned.');
      continue;
    }
    runs.add((sys.id, sys.description, evaluate(sys, split.test)));
  }
  if (runs.isEmpty) _fail('No system could run.');

  final info = RunInfo(
    dataName: dataPath,
    dataFingerprint: fnv1a(content),
    split: split.describe,
    devCount: split.dev.length,
    testCount: split.test.length,
    templateVersion: kTemplateSetVersion,
    command: 'dart run bin/evaluate.dart ${args.join(' ')}',
  );
  final md = markdownReport(info, runs, notes: notes);
  out.createSync(recursive: true);
  File('${out.path}/report.md').writeAsStringSync(md);
  File('${out.path}/results.json').writeAsStringSync(
      const JsonEncoder.withIndent('  ').convert({
    'run': info.toJson(),
    'notes': notes,
    'systems': [for (final r in runs) r.$3.toJson()],
  }));
  stdout.write(md);
}

(String, List<GoldMessage>) _load(String path) {
  final f = File(path);
  if (!f.existsSync()) _fail('File not found: $path');
  final content = f.readAsStringSync();
  try {
    return (content, parseGold(content, name: path));
  } on FormatException catch (e) {
    stderr.writeln('Data error: ${e.message}');
    exit(65);
  }
}
