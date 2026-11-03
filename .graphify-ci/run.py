"""Runs the graphify pipeline on this repository in CI.

Follows the graphify skill steps 2-6 and 9. Code is extracted structurally
(AST). Semantic nodes for docs and images come from .graphify-ci/semantic.json
when present (written by the host agent); community names from
.graphify-ci/labels.json when present.
"""
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

from graphify.analyze import god_nodes, suggest_questions, surprising_connections
from graphify.build import build_from_json
from graphify.cluster import cluster, score_all
from graphify.detect import detect
from graphify.diagnostics import diagnose_extraction, format_diagnostic_report
from graphify.export import to_json
from graphify.extract import collect_files, extract
from graphify.report import generate

ROOT = Path('.').resolve()
OUT = Path('graphify-out')
CI = Path('.graphify-ci')
OUT.mkdir(exist_ok=True)

# Step 2: detect
result = detect(ROOT, extra_excludes=['.graphify-ci/**', '.graphify-ci', '.github/workflows/graphify.yml'])
(OUT / '.graphify_detect.json').write_text(json.dumps(result, ensure_ascii=False), encoding='utf-8')
files = result.get('files', {})
print(f"Corpus: {result['total_files']} files, ~{result.get('total_words', 0)} words")
for cat, fl in files.items():
    if fl:
        exts = sorted({Path(f).suffix for f in fl})
        print(f'  {cat}: {len(fl)} files ({" ".join(exts)})')
        for f in fl:
            print(f'    - {Path(f).resolve().relative_to(ROOT) if Path(f).is_absolute() else f}')
if result.get('skipped_sensitive'):
    print('Skipped as sensitive:', result['skipped_sensitive'])
if result.get('total_words', 0) > 2_000_000 or result['total_files'] > 500:
    print('WARNING: large corpus')

# Step 3 Part A: AST
code_files = []
for f in files.get('code', []):
    code_files.extend(collect_files(Path(f)) if Path(f).is_dir() else [Path(f)])
ast = extract(code_files, cache_root=ROOT, root=ROOT) if code_files else {
    'nodes': [], 'edges': [], 'input_tokens': 0, 'output_tokens': 0}
(OUT / '.graphify_ast.json').write_text(json.dumps(ast, indent=2, ensure_ascii=False), encoding='utf-8')
print(f"AST: {len(ast['nodes'])} nodes, {len(ast['edges'])} edges")
with (OUT / 'ast_ids.tsv').open('w', encoding='utf-8') as fh:
    for n in ast['nodes']:
        fh.write(f"{n['id']}\t{n.get('label', '')}\t{n.get('source_file', '')}\n")

# Step 3 Part B: semantic (from the host agent, if provided)
sem_path = CI / 'semantic.json'
sem = json.loads(sem_path.read_text(encoding='utf-8')) if sem_path.exists() else {
    'nodes': [], 'edges': [], 'hyperedges': [], 'input_tokens': 0, 'output_tokens': 0}
print(f"Semantic: {len(sem['nodes'])} nodes, {len(sem['edges'])} edges, "
      f"{len(sem.get('hyperedges', []))} hyperedges")

# Step 3 Part C: merge
for n in sem['nodes']:
    n.setdefault('_origin', 'semantic')
for e in sem['edges']:
    e.setdefault('_origin', 'semantic')
seen = {n['id'] for n in ast['nodes']}
merged_nodes = list(ast['nodes'])
for n in sem['nodes']:
    if n['id'] not in seen:
        merged_nodes.append(n)
        seen.add(n['id'])
extraction = {
    'nodes': merged_nodes,
    'edges': ast['edges'] + sem['edges'],
    'hyperedges': sem.get('hyperedges', []),
    'input_tokens': sem.get('input_tokens', 0),
    'output_tokens': sem.get('output_tokens', 0),
}
(OUT / '.graphify_extract.json').write_text(json.dumps(extraction, indent=2, ensure_ascii=False), encoding='utf-8')
print(f"Merged: {len(merged_nodes)} nodes, {len(extraction['edges'])} edges")

# Step 4: build, cluster, analyze
G = build_from_json(extraction, root=str(ROOT), directed=False)
if G.number_of_nodes() == 0:
    print('ERROR: Graph is empty')
    sys.exit(1)
communities = cluster(G)
cohesion = score_all(G, communities)
tokens = {'input': extraction['input_tokens'], 'output': extraction['output_tokens']}
gods = god_nodes(G)
surprises = surprising_connections(G, communities)

labels_path = CI / 'labels.json'
if labels_path.exists():
    raw = json.loads(labels_path.read_text(encoding='utf-8'))
    labels = {cid: raw.get(str(cid), f'Community {cid}') for cid in communities}
else:
    labels = {cid: f'Community {cid}' for cid in communities}
questions = suggest_questions(G, communities, labels)

if not to_json(G, communities, str(OUT / 'graph.json'), force=True, community_labels=labels):
    print('ERROR: graph.json not written')
    sys.exit(1)
report = generate(G, communities, cohesion, labels, gods, surprises, result, tokens, str(ROOT),
                  suggested_questions=questions)
(OUT / 'GRAPH_REPORT.md').write_text(report, encoding='utf-8')
analysis = {
    'communities': {str(k): v for k, v in communities.items()},
    'cohesion': {str(k): v for k, v in cohesion.items()},
    'gods': gods,
    'surprises': surprises,
    'questions': questions,
}
(OUT / 'analysis.json').write_text(json.dumps(analysis, indent=2, ensure_ascii=False, default=str), encoding='utf-8')
(OUT / '.graphify_labels.json').write_text(json.dumps({str(k): v for k, v in labels.items()}, ensure_ascii=False), encoding='utf-8')
print(f'Graph: {G.number_of_nodes()} nodes, {G.number_of_edges()} edges, {len(communities)} communities')

# Step 4.5: health check
summary = diagnose_extraction(extraction, directed=False, root=str(ROOT))
print(format_diagnostic_report(summary))
flags = [f'{summary[k]} {label}' for k, label in (
    ('dangling_endpoint_edges', 'dangling-endpoint edges'),
    ('missing_endpoint_edges', 'missing-endpoint edges'),
    ('self_loop_edges', 'self-loop edges'),
    ('directed_same_endpoint_collapsed_edges', 'collapsed (directed) edges'),
    ('undirected_same_endpoint_collapsed_edges', 'collapsed (undirected) edges'),
) if summary.get(k, 0)]
health = ('GRAPH HEALTH WARNING: ' + '; '.join(flags) if flags
          else 'Graph health: OK (no dangling/missing/collapsed edges).')
print(health)
(OUT / 'health.txt').write_text(format_diagnostic_report(summary) + '\n' + health + '\n', encoding='utf-8')

# Step 6: HTML
subprocess.run(['graphify', 'export', 'html'], check=False)

# Step 9: manifest and cost
try:
    from graphify.cli import _stamped_manifest_files
    from graphify.detect import save_manifest
    corpus = result.get('all_files') or result['files']
    manifest_files = _stamped_manifest_files(corpus, extraction, ROOT, partial_source_files=set())
    scan = {f for fl in corpus.values() for f in fl}
    save_manifest(manifest_files, root=str(ROOT), scan_corpus=scan, clear_semantic=None)
except Exception as e:  # noqa: BLE001
    print('manifest skipped:', e)
cost_path = OUT / 'cost.json'
cost = json.loads(cost_path.read_text(encoding='utf-8')) if cost_path.exists() else {
    'runs': [], 'total_input_tokens': 0, 'total_output_tokens': 0}
cost['runs'].append({'date': datetime.now(timezone.utc).isoformat(),
                     'input_tokens': tokens['input'], 'output_tokens': tokens['output'],
                     'files': result.get('total_files', 0)})
cost['total_input_tokens'] += tokens['input']
cost['total_output_tokens'] += tokens['output']
cost_path.write_text(json.dumps(cost, indent=2), encoding='utf-8')
print(f"This run: {tokens['input']:,} input tokens, {tokens['output']:,} output tokens")

for name in ('.graphify_detect.json', '.graphify_extract.json', '.graphify_ast.json'):
    (OUT / name).unlink(missing_ok=True)
