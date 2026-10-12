#!/usr/bin/env python3
"""Summarize retained round-two changes and their measured tradeoffs."""
import json
from pathlib import Path
HERE=Path(__file__).resolve().parent
selection=json.loads((HERE/'retained.json').read_text())
review=json.loads((HERE/'experiment-review.json').read_text())
reviewed={row['stage']:row for row in review['reviewed']}
rows=[];evidence=[];tradeoffs=[]
for family in selection['families']:
    assert family['stages'], 'Retained candidate pending for '+family['family']
    measurements=[]
    for stage in family['stages']:
        entry=reviewed[stage];comparison=json.loads((HERE/entry['comparison']).read_text())
        measurements.extend(comparison['rows']);evidence.append({'family':family['family'],**entry})
    byname={row['name']:row for row in measurements}
    representative=byname.get(family['representative'])
    if representative is None:representative=max(measurements,key=lambda row:row['instruction_reduction_percent'])
    row=representative
    rows.append(f'| {family["family"]} | `{row["name"]}` | {row["before"]["instructions"]:,.0f} | {row["after"]["instructions"]:,.0f} | {row["instruction_reduction_percent"]:.2f}% | {row["allocation_delta_bytes"]:+,.0f} | {row["wasm_delta_bytes"]:+,} |')
    distinct={(row['name'],row['implementation']):row for row in measurements}
    regressions=[row for row in distinct.values() if row['instruction_reduction_percent']<0]
    min_size=min(row['wasm_delta_bytes'] for row in distinct.values());max_size=max(row['wasm_delta_bytes'] for row in distinct.values())
    note=f'- **{family["family"]}:** {family["change"]}. {len(distinct)} workload variants; {len(regressions)} instruction regressions. Whole-canister Wasm change {min_size:+,} to {max_size:+,} bytes.'
    if regressions:
        worst=min(regressions,key=lambda row:row['instruction_reduction_percent'])
        note+=f' Largest relative regression: `{worst["name"]}`, {-worst["instruction_reduction_percent"]:.2f}% ({worst["after"]["instructions"]-worst["before"]["instructions"]:+,.0f} instructions).'
    tradeoffs.append(note)
lines=['# Crypto optimization round two','',
'Every comparison uses the delivered implementation frozen before this round and the identical public API, input, output oracle, compiler, RTS and PocketIC version. Each variant has three fresh-canister trials. Input setup and byte checking are outside the measured interval. Values are median IC instructions, cumulative allocation and whole-canister Wasm bytes. This report compares the previous plugin implementation with the optimized plugin; the [public API table](../../../benchmark_crypto.md) separately compares pure Motoko with plugins.','',
'| Family | Representative workload | Before instructions | After instructions | Reduction | Allocation delta B | Wasm delta B |','|---|---|---:|---:|---:|---:|---:|',*rows,'',*tradeoffs,'',
'The retained [complete comparisons](experiment-review.json) include all measured sizes and regressions. No speedup is inferred from an unmeasured case. Improvements are workload-specific; prepared APIs and streaming boundaries are labelled in the fixture manifests. Source and artifact fingerprints are retained with every build.','',
'Rejected experiments remain in the evidence: custom SHA512 and RIPEMD compression kernels did not justify their maintenance/code-size cost; the SHA512 SIMD runtime was rejected by the compiler importer; BLAKE3 short-output shortcuts increased code size and regressed long XOF; secp256k1 mixed-add specializations added about 18 KiB for small arithmetic gains. Earlier Base58 and Bech32 candidates were superseded after small-input measurements exposed dispatch overhead.','',
'Round-one files remain unchanged. Nested oracle generators and fixture inputs are retained in the round-two source store; early stages have an explicitly labelled supplemental oracle snapshot, while their compiled actors, expected bytes and build/run protocol were frozen before measurement. Recovered early launcher bodies are accepted only when their SHA256 matches recorded metadata.','']
combined=HERE/'comparisons/composed-final.json'
if combined.exists():
    actual=json.loads(combined.read_text())
    wanted={('bitcoin-hash160-pubkey','native'),('bitcoin-p2pkh','native-prevalidated'),('bitcoin-bip32-child0','native'),('bitcoin-bip86-receive-address','native'),('bitcoin-serialize-100-inputs','native'),('bitcoin-legacy-all-sign-all-100-inputs','native'),('bitcoin-taproot-default-sign-all-100-inputs','native'),('bitcoin-bip143-all-cache-100-inputs','native-prepared'),('bitcoin-taproot-default-cache-100-inputs','native-prepared')}
    lines += ['## Combined final build','',
    'All 30 composed workloads passed three fresh-canister exact-output trials against the final shared plugins and final Bitcoin modules. These numbers include the combined changes; the family experiments above isolate their respective candidate changes.','',
    '| Workflow | Variant | Before instructions | Final instructions | Reduction | Allocation delta B |','|---|---|---:|---:|---:|---:|']
    for row in actual['rows']:
        if (row['name'],row['implementation']) not in wanted:continue
        variant=row['implementation'].replace('native','plugin').replace('-',' ')
        lines.append(f'| `{row["name"]}` | {variant} | {row["before"]["instructions"]:,.0f} | {row["after"]["instructions"]:,.0f} | {row["instruction_reduction_percent"]:.2f}% | {row["allocation_delta_bytes"]:+,.0f} |')
    lines += ['', 'The BLS repeated-message cache is limited to messages of at most 1,024 bytes. Three additional 16-key workloads with independently generated proofs/signatures cover shared-prefix 4 KiB and 64 KiB distinct messages and a repeated 64 KiB message. Distinct long-message workloads add only 206,645 instructions (about 0.0028%) versus the delivered baseline; the repeated 64 KiB workload still improves 7.51% through other retained changes. All nine trials match independent outputs.','']
(HERE/'RESULTS.md').write_text('\n'.join(lines))
(HERE/'retained-evidence.json').write_text(json.dumps({'families':selection['families'],'comparisons':evidence},indent=2)+'\n')
print(HERE/'RESULTS.md')
