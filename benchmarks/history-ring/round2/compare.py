#!/usr/bin/env python3
"""Compare immutable round-two stages by capacity/operation and verify fair inputs."""
import argparse
import csv
import json
from pathlib import Path

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('before')
p.add_argument('after')
p.add_argument('--csv', type=Path)
a = p.parse_args()
here = Path(__file__).resolve().parent
before = json.loads((here / 'results' / a.before / 'results.json').read_text())
after = json.loads((here / 'results' / a.after / 'results.json').read_text())
assert before['build']['command'] == after['build']['command'], 'Compiler flags/paths differ'
for path, digest in before['build']['sha256'].items():
    if '/round2-plugin/' in path or path.endswith('/_out/main.wasm'):
        continue
    assert after['build']['sha256'][path] == digest, f'Non-plugin build input changed: {path}'
for field in ['bun', 'pocket_ic_sha256', 'ash_transport_sha256', 'pic_js_version']:
    assert before['runtime'][field] == after['runtime'][field], field
index = {(row['capacity'], row['operation']): row for row in before['cases']}
rows = []
for row in after['cases']:
    key = row['capacity'], row['operation']
    if key not in index:
        continue
    original = index[key]
    assert row['repetitions'] == original['repetitions']
    assert row['pageLength'] == original['pageLength']
    for sample in row['samples'] + original['samples']:
        for field in ['checksum', 'size', 'first', 'next', 'operations']:
            assert sample['plugin'][field] == sample['core'][field], (key, field)
    for field in ['checksum', 'size', 'first', 'next', 'operations', 'instructions', 'allocated']:
        assert row['core'][field] == original['core'][field], (key, 'core drift', field)
    old = original['plugin']; new = row['plugin']; core = row['core']
    result = {'capacity': key[0], 'operation': key[1], 'count': new['operations'], 'page_length': row['pageLength'], 'core_instructions': core['instructions'], 'original_plugin_instructions': old['instructions'], 'final_plugin_instructions': new['instructions'], 'plugin_instruction_reduction_percent': 100 * (old['instructions'] - new['instructions']) / old['instructions'], 'core_allocated_bytes': core['allocated'], 'original_plugin_allocated_bytes': old['allocated'], 'final_plugin_allocated_bytes': new['allocated'], 'core_heap_after': core['memory_after']['heap'], 'plugin_heap_after': new['memory_after']['heap']}
    rows.append(result)
    if old['instructions'] != new['instructions'] or old['allocated'] != new['allocated']:
        print(f"{key[0]}/{key[1]}: {old['instructions']} -> {new['instructions']} ({result['plugin_instruction_reduction_percent']:+.2f}% fewer); allocated {old['allocated']} -> {new['allocated']} B")
assert rows, 'No overlapping cases'
if a.csv:
    with a.csv.open('w') as out:
        writer = csv.DictWriter(out, fieldnames=list(rows[0]))
        writer.writeheader(); writer.writerows(rows)
print(f'{len(rows)} matched cases, Core checksum/instruction/allocation identical across stages')
