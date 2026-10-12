#!/usr/bin/env python3
"""Record measured accepted and rejected optimization deltas with artifact links."""
import json,statistics
from pathlib import Path
HERE=Path(__file__).resolve().parent

def sample(stage,name,implementation):
    r=json.loads((HERE/'results'/stage/'results.json').read_text())
    c=next(c for c in r['cases'] if c['name']==name and c['implementation']==implementation)
    assert len(c['measurements'])>=3 and all(m.get('correct') for m in c['measurements'])
    return {'stage':stage,'name':name,'implementation':implementation,'instructions':statistics.median(m['instructions'] for m in c['measurements']),'allocated_bytes':statistics.median(m['allocated_bytes'] for m in c['measurements']),'wasm_bytes':c['wasm_bytes'],'wasm_sha256':c['wasm_sha256']}
experiments=[
 ('BLAKE3 empty constant','accepted','blake3-native-initial','blake3-0','native','final-native','blake3-0','native',''),
 ('SHA512 empty constant','accepted','sha512-empty-original','sha512-0','native','final-native','sha512-0','native',''),
 ('RIPEMD160 HASH160-sized input','accepted','ripemd-short-native-initial','ripemd160-32','native','final-native','ripemd160-32','native','Fixed32-byte specialization; general inputs incur19 extra dispatch instructions.'),
 ('Bech32 decode ASCII table','accepted','bech32-native-initial','bech32-decode-53','native','final-native','bech32-decode-53','native',''),
 ('secp256k1 RFC6979 sign','accepted','curves-native-initial','secp256k1_sign_rfc6979_fast','fast','final-native','secp256k1_sign_rfc6979_fast','fast','Avoid unused cached verifying-key derivation.'),
 ('P256 RFC6979 sign','accepted','curves-p256-fixed-baseline','p256_sign_rfc6979_fast','fast','final-native','p256_sign_rfc6979_fast','fast','Matched nonce-fix baseline; avoid unused cached verifying-key derivation.'),
 ('BLS G1 window MSM128','accepted','curves-bls-expanded-native-initial','bls12_381_g1_msm_distinct_128_fast','fast','final-native','bls12_381_g1_msm_distinct_128_fast','fast','Larger temporary allocation buys fewer scalar-multiplication instructions.'),
 ('BLS G2 window MSM128','accepted','curves-bls-expanded-native-initial','bls12_381_g2_msm_distinct_128_fast','fast','final-native','bls12_381_g2_msm_distinct_128_fast','fast','Larger temporary allocation buys fewer scalar-multiplication instructions.'),
 ('HMAC256 prepared key','api-reuse','final-native','hmac-sha256-64','native','final-native','hmac-sha256-prepared-64','native','Key preparation excluded only in the reusable-key API.'),
 ('HMAC512 prepared key','api-reuse','final-native','hmac-sha512-64','native','final-native','hmac-sha512-prepared-64','native','Key preparation excluded only in the reusable-key API.'),
 ('BIP143 prepared100-input batch','api-reuse','final-native','bitcoin-bip143-all-cache-100-inputs','native','final-native','bitcoin-bip143-all-cache-100-inputs','native-prepared','Both measure whole100-input batch; prepared creation and cold hashing included.'),
 ('Taproot prepared100-input batch','api-reuse','final-native','bitcoin-taproot-default-cache-100-inputs','native','final-native','bitcoin-taproot-default-cache-100-inputs','native-prepared','Both measure whole100-input batch; prepared creation and cold hashing included.'),
 ('SHA512 unrolled1KiB','rejected','hashes-codec-native-initial','sha512-1024','native','sha512-native-candidate','sha512-1024','native','Modest instruction saving rejected for Wasm growth and maintenance cost.'),
 ('HMAC256 unrolled1KiB','rejected','hmac-native-initial','hmac-sha256-1024','native','hmac-unrolled256-candidate','hmac-sha256-1024','native','Modest instruction saving rejected for Wasm growth.'),
 ('HMAC256 forceinline1KiB','rejected','hmac-native-initial','hmac-sha256-1024','native','hmac-unrolled256-inline','hmac-sha256-1024','native','Larger code expansion rejected despite a small instruction saving.'),
]
rows=[]
for label,status,bs,bn,bi,cs,cn,ci,notes in experiments:
    before=sample(bs,bn,bi);after=sample(cs,cn,ci)
    rows.append({'experiment':label,'decision':status,'before':before,'after':after,'instruction_reduction_percent':100*(1-after['instructions']/before['instructions']),'instruction_ratio':before['instructions']/after['instructions'],'canister_wasm_delta_bytes':after['wasm_bytes']-before['wasm_bytes'],'notes':notes})
(HERE/'summary/optimizations.json').write_text(json.dumps(rows,indent=2)+'\n')
print(f'{len(rows)} accepted/rejected/reuse experiment records')
