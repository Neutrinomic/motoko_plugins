#!/usr/bin/env python3
"""Render the complete public API benchmark table from successful measured trials only."""
import argparse, hashlib, importlib.util, json, statistics
from pathlib import Path
HERE=Path(__file__).resolve().parent
BENCH=HERE.parent
ROOT=BENCH.parents[1]
spec=importlib.util.spec_from_file_location('paired_compare',HERE/'compare.py')
paired=importlib.util.module_from_spec(spec);spec.loader.exec_module(paired)
p=argparse.ArgumentParser(description=__doc__)
p.add_argument('--selection',type=Path,default=HERE/'api-selection.json')
p.add_argument('--out',type=Path,default=ROOT/'benchmark_crypto.md')
a=p.parse_args()
inventory=json.loads((HERE/'api-inventory.json').read_text())
selection=json.loads(a.selection.read_text())
assert selection.get('plugin_stages'), 'Explicit final plugin cohorts required'
final_pins=json.loads((HERE/'api-final-fingerprint.json').read_text())
lookup={};stages={};toolchain=None;environment=None
for stage in selection['stages']:
    directory,result,build,identity,cases=paired.read_stage(stage)
    if toolchain is None:
        toolchain=identity
        environment={'compiler':build['compiler_version'],'pocket_ic':result['pocket_ic_version'],'release_rts_sha256':identity['MOC_RELEASE_RTS']}
    assert toolchain==identity, 'API table toolchains differ'
    assert result['trials']==3, 'Report requires exactly three trials'
    if stage in selection['plugin_stages']:
        assert stage in final_pins['stages'], 'Plugin cohort missing final fingerprint'
        assert paired.sha(directory/'build.json')==final_pins['stages'][stage]['build_sha256']
        for relative,digest in final_pins['source_and_artifact_sha256'].items():
            assert paired.sha(directory/'inputs'/relative)==digest, 'Final module/plugin artifact mismatch: '+relative
    stages[stage]={'build_sha256':paired.sha(directory/'build.json'),'results_sha256':paired.sha(directory/'results.json')}
    for key,case in cases.items():
        if case['plugins'] and stage not in selection['plugin_stages']:continue
        lookup[(*key,case['source_sha256'])]=(stage,case)
allrows=[]
for row in inventory['api_rows']:
    record={**row,'measurements':{}}
    for field,label in [('plugin_case','plugin'),('native_case','native')]:
        ref=row.get(field)
        if not ref:continue
        key=(ref['name'],ref['implementation'],ref['source_sha256'])
        assert key in lookup, 'Unmeasured API workload: '+row['id']+' '+label
        stage,case=lookup[key]
        assert bool(case['plugins'])==(label=='plugin')
        measurements=case['measurements']
        divisor=case.get('operations_per_sample',1)
        assert isinstance(divisor,int) and divisor>0
        record['measurements'][label]={'stage':stage,'name':case['name'],'implementation':case['implementation'],'instructions_per_op':statistics.median(m['instructions'] for m in measurements)/divisor,'allocated_bytes_per_op':statistics.median(m['allocated_bytes'] for m in measurements)/divisor,'wasm_bytes':case['wasm_bytes'],'source_sha256':case['source_sha256'],'expected_hex':case['expected_hex'],'operations_per_sample':divisor,'trials':len(measurements)}
    if 'native' in record['measurements']:
        assert record['measurements']['native']['expected_hex']==record['measurements']['plugin']['expected_hex']
        record['native_plugin_ratio']=record['measurements']['native']['instructions_per_op']/record['measurements']['plugin']['instructions_per_op']
    allrows.append(record)
# Keep one representative row per callable in the concise table; all sizes remain in machine data.
groups={}
for row in allrows:groups.setdefault((row['module'],row['function']),[]).append(row)
def priority(row):
    size=row['size']
    return (bool(row.get('representative')),size==1024,size==32,size==64,size!=0,str(size))
selected=[max(rows,key=priority) for rows in groups.values()]
assert len(selected)==inventory['callable_count']
modules=['SHA256','BLAKE3','SHA512','RIPEMD160','HMAC','Base58','Base58Check','Bech32','Segwit','Secp256k1','P256','BLS12381','Bitcoin/Hash','Bitcoin/Address','Bitcoin/Bip32','Bitcoin/Script','Bitcoin/Transaction']
assert set(row['module'] for row in selected)<=set(modules), 'Unrecognized module'
fmt=lambda value:f'{value:,.0f}' if int(value)==value else f'{value:,.2f}'
escape=lambda value:str(value).replace('|','\\|').replace('\n',' ')
markers={'G2-uncompressed':'U','G2-predecoded':'P','ECDSA-prepared-nonce':'N','RIPEMD-mutable':'M','Bech-private':'E','BLAKE-composed':'B','Bitcoin-secret-composed':'S','Bitcoin-uncached':'C'}
lines=['# Crypto public API benchmarks','',f'{len(selected)} public callables. **Native** means pure Motoko from pinned Mops packages; **Plugin** means the optimized `mo:fast` implementation. `Native/plugin` is the measured instruction ratio (larger favors the plugin). Empty native cells mean no correct counterpart for the listed operation in the pinned packages. Marked rows use the closest available code with the contract differences explained below.','',
'Each value is the median of three fresh-canister trials. Inputs and reusable setup are prepared before measurement; only the named operation and result assignment are timed. Exact independent output checks run afterward. Instructions are IC instructions/op, including measured call overhead; allocated bytes are cumulative allocation/op, not live heap. Whole-canister Wasm sizes, all workload sizes, hashes and individual trials are retained in the [machine-readable evidence](benchmarks/crypto/round2/api-measurements.json).','',
f'Measured with {environment["compiler"]}, {environment["pocket_ic"]}, and release RTS SHA256 `{environment["release_rts_sha256"][:16]}…` (full hash in evidence).','',
'Pinned packages: `sha2@0.1.14`, `blake3@0.1.2`, `ecdsa@8.0.1`, `bitcoin@0.2.1`, `bls12-381@0.2.0`. Byte-oriented curve adapters include parsing, validation and serialization except where marked; reusable curve construction is outside timing. Prepared and streaming rows exclude construction unless construction is the named operation. Every counterpart and any contract differences are recorded per row in the evidence file.','']
for module in modules:
    rows=[row for row in selected if row['module']==module]
    if not rows:continue
    lines += ['## '+module,'','| Public function | Workload | Size | Native instructions/op | Plugin instructions/op | Native allocated B/op | Plugin allocated B/op | Native/plugin |','|---|---|---|---:|---:|---:|---:|---:|']
    for row in sorted(rows,key=lambda row:row['function']):
        plugin=row['measurements']['plugin'];native=row['measurements'].get('native')
        footnote=row.get('visible_footnote')
        assert not footnote or footnote in markers, 'Unknown visible contract footnote: '+str(footnote)
        marker=' ['+markers[footnote]+']' if footnote else ''
        cells=[f'`{row["function"]}`'+marker,row['workload'],f'{row["size"]} B' if isinstance(row['size'],int) else row['size'],fmt(native['instructions_per_op']) if native else '',fmt(plugin['instructions_per_op']),fmt(native['allocated_bytes_per_op']) if native else '',fmt(plugin['allocated_bytes_per_op']),f'{row["native_plugin_ratio"]:.2f}×' if native else '']
        lines.append('| '+' | '.join(escape(cell) for cell in cells)+' |')
    lines.append('')
    if module=='BLAKE3':
        lines += ['[B] Native composes published state/flag operations for correct domain-separated derivation. Extra long-XOF workloads compose output-block calls. These bounded cases match official vectors; the package’s high-level derive function ignores context, and its multi-chunk hashing remains incorrect.','']
    if module=='RIPEMD160':
        lines += ['[M] Native constructs or mutates an object and consumes it on finalization. Plugin state is an immutable serialized snapshot, and finalization preserves it. Ratios include these different state contracts.','']
    if module=='Bech32':
        lines += ['[E] Native uses the exact attributed private `bitcoin/Segwit.convertBits` function, extracted into the benchmark. It assumes valid bit widths; the plugin validates widths and enforces size limits. Both perform the same valid conversion.','']
    if module in ['Secp256k1','P256']:
        lines += ['[N] Native signs with an independently prepared RFC6979 nonce; plugin derives that nonce inside the measured call. Native secret arithmetic is variable-time. This is a closest-operation comparison, not equal API or side-channel guarantees.','']
    if module=='BLS12381':
        lines += ['[U] Native decodes and subgroup-validates 256-byte EIP-2537 uncompressed points; plugin accepts 96-byte compressed points and also recovers coordinates. Both encode compressed outputs. [P] Native starts from trusted predecoded points/scalars; arithmetic result encoding is outside timing. Plugin includes byte decoding, validation and encoding. Pairing returns a Boolean. These rows compare the same mathematical inputs and outputs with different API work, so their ratios are not equivalent-contract speedups.','']
    if module=='Bitcoin/Address':
        lines += ['[S] Native composes published curve/scalar arithmetic and tagged hashing for the same BIP341 secret tweak. Its secret arithmetic is variable-time.','']
    if module=='Bitcoin/Transaction':
        lines += ['[C] Native computes an uncached one-shot Taproot hash; plugin measures the first cold call on a prepared hasher. Preparation is excluded, lazy common hashes are included. Native returns an array with oracle conversion outside timing; plugin returns a Blob.','']
lines += ['Pure Motoko secret-key arithmetic can be variable-time; ratios compare mathematical outputs, not side-channel guarantees. The pinned packages lack BIP340, complete RFC 9380/BLS signature profiles, BIP143, and retained Taproot-hasher construction counterparts; those cells remain empty. Per-row explanations and all adapter sources are in the evidence file.','',
'See [optimization results](benchmarks/crypto/round2/RESULTS.md) for before/after changes, regressions and Wasm-size tradeoffs; the [original Mops comparison report](benchmarks/crypto/RESULTS.md) remains unchanged.','']
a.out.write_text('\n'.join(lines))
(HERE/'api-measurements.json').write_text(json.dumps({'callable_count':len(selected),'workload_row_count':len(allrows),'selection_sha256':paired.sha(a.selection),'inventory_sha256':paired.sha(HERE/'api-inventory.json'),'toolchain':toolchain,'environment':environment,'stages':stages,'displayed_api_rows':[row['id'] for row in selected],'rows':allrows},indent=2)+'\n')
print(a.out,len(selected),'callables;',len(allrows),'measured workload rows')
