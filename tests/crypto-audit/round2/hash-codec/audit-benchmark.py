#!/usr/bin/env python3
"""Independently check the final crypto API table, measured medians and artifact pins."""
from pathlib import Path
import argparse,hashlib,importlib.util,json,statistics,re
ap=argparse.ArgumentParser(description=__doc__)
ap.add_argument('--root',type=Path,default=Path(__file__).resolve().parents[4])
ap.add_argument('--out',type=Path,required=True)
a=ap.parse_args();root=a.root.resolve();bench=root/'benchmarks/crypto';rnd=bench/'round2'
sha=lambda p:hashlib.sha256(p.read_bytes()).hexdigest()
load=lambda p:json.loads(p.read_text())
# Independently inventoried public callable paths; private classes and constants excluded.
expected={
'SHA256':'digest',
'BLAKE3':'digest keyedHash deriveKey xof new newKeyed newDeriveKey update finalize finalizeXof',
'SHA512':'digest digest384 Digest Digest.write Digest.sum Digest.reset Digest384 Digest384.write Digest384.sum Digest384.reset',
'RIPEMD160':'digest init update finalize Digest Digest.write Digest.sum Digest.reset',
'HMAC':'sha256 sha512 SHA256 SHA256.write SHA256.sum SHA256.reset SHA512 SHA512.write SHA512.sum SHA512.reset prepareSha256 prepareSha256.digest prepareSha256.stream prepareSha256.stream.write prepareSha256.stream.sum prepareSha256.stream.reset prepareSha512 prepareSha512.digest prepareSha512.stream prepareSha512.stream.write prepareSha512.stream.sum prepareSha512.stream.reset',
'Base58':'encode decode','Base58Check':'encode decode','Bech32':'encode decode convertBits','Segwit':'encode decode',
'Secp256k1':'derivePublicKey compressPublicKey decompressPublicKey convertPublicKey publicKey pointAdd pointMultiply baseMultiply tweakPublicKey signPrehash verifyPrehash signatureToDer signatureFromDer normalizeSignature xOnlyPublicKey schnorrSign schnorrVerify tweakXOnlyPublicKey tweakXOnlySecretKey',
'P256':'publicKey derivePublicKey convertPublicKey signPrehash verifyPrehash signatureToDer signatureFromDer normalizeSignature',
'BLS12381':'validateG1 validateG2 g1Add g2Add g1Mul g2Mul g1Msm g2Msm mapToG1 mapToG2 hashToG1 hashToG2 pairingCheck verifyIC verifyEthereum verifyEthereumProof g1Aggregate g2Aggregate aggregateVerifyIC aggregateVerifyEthereum fastAggregateVerifyEthereum',
'Bitcoin/Hash':'hash160 sha256d digest256 taggedHash taggedHasher taggedHasher.call',
'Bitcoin/Address':'hrp encode decode p2pkh p2sh p2wpkh p2wsh taprootOutputKey taprootSecretKey signTaprootKeyPath p2trOutput p2tr scriptPubKey',
'Bitcoin/Bip32':'fromPublicKey fingerprint parse serialize deriveChild derivePath parsePath deriveTextPath',
'Bitcoin/Script':'pushData p2pkh p2sh witnessProgram p2wpkh p2wsh p2tr tapLeafHash tapBranchHash',
'Bitcoin/Transaction':'serialize parse txid wtxid signatureHashLegacy signatureHashSegwitV0 prepareSegwitV0 SegwitV0Hasher.signatureHash signatureHashTaproot prepareTaproot TaprootHasher.signatureHash'}
expected={(m,f)for m,s in expected.items()for f in s.split()};assert len(expected)==155
inventory=load(rnd/'api-inventory.json');measure=load(rnd/'api-measurements.json');selection=load(rnd/'api-selection.json');pins=load(rnd/'api-final-fingerprint.json')
assert measure['inventory_sha256']==sha(rnd/'api-inventory.json')
assert measure['selection_sha256']==sha(rnd/'api-selection.json')
assert {(r['module'],r['function'])for r in inventory['api_rows']}==expected
assert measure['callable_count']==inventory['callable_count']==155
rows={r['id']:r for r in measure['rows']};assert len(rows)==len(measure['rows'])==measure['workload_row_count']
display=[rows[i]for i in measure['displayed_api_rows']];assert len(display)==155
assert {(r['module'],r['function'])for r in display}==expected
for key,digest in pins['source_and_artifact_sha256'].items():assert sha(root/key)==digest,key
for plugin in ['sha256','blake3','sha512','ripemd160','hmac-sha2','base58','bech32','secp256k1','p256','bls12-381']:
 for name in ['build.json','plugin.cmxs','runtime.wasm']:assert f'dist/{plugin}/{name}'in pins['source_and_artifact_sha256']
for module in {m for m,f in expected}:assert f'packages/fast/src/{module}.mo'in pins['source_and_artifact_sha256']
spec=importlib.util.spec_from_file_location('crypto_round2_compare',rnd/'compare.py');paired=importlib.util.module_from_spec(spec);spec.loader.exec_module(paired)
stages={}
for stage in selection['stages']:
 directory,result,build,identity,cases=paired.read_stage(stage);assert result['trials']==3
 assert measure['stages'][stage]['build_sha256']==sha(directory/'build.json')
 assert measure['stages'][stage]['results_sha256']==sha(directory/'results.json')
 assert identity==measure['toolchain'];stages[stage]=(directory,cases)
 frozen_deps=directory/'inputs/benchmarks/crypto/dependencies'
 assert sha(frozen_deps/'mops.lock')==sha(bench/'dependencies/mops.lock')
 lock=load(frozen_deps/'mops.lock')
 assert build['dependency_aliases']=={alias:f'{alias.split("@")[0]}@{version}'for alias,version in lock['deps'].items()}
 for package,files in lock['hashes'].items():
  for relative,digest in files.items():assert sha(frozen_deps/'.mops'/relative)==digest
  for source in (frozen_deps/'.mops'/package/'src').rglob('*.mo'):assert str(source.relative_to(frozen_deps/'.mops'))in files
 if stage in selection['plugin_stages']:
  assert pins['stages'][stage]['build_sha256']==sha(directory/'build.json')
  for key,digest in pins['source_and_artifact_sha256'].items():assert sha(directory/'inputs'/key)==digest
  for name in ['sha256','blake3','sha512','ripemd160','hmac-sha2','base58','bech32','secp256k1','p256','bls12-381']:
   metadata=load(directory/'inputs/dist'/name/'build.json')
   for relative,digest in metadata['source_sha256'].items():assert sha(directory/'inputs/plugin-build-inputs'/name/relative)==digest
   for relative,digest in metadata['sha256'].items():assert sha(directory/'inputs/dist'/name/relative)==digest
for row in rows.values():
 for label,entry in row['measurements'].items():
  directory,cases=stages[entry['stage']];case=cases[entry['name'],entry['implementation']]
  assert entry['source_sha256']==case['source_sha256']
  assert entry['expected_hex']==case['expected_hex']
  if label=='plugin':assert entry['stage']in selection['plugin_stages']and case['plugins']
  else:assert not case['plugins']
  divisor=case.get('operations_per_sample',1)
  assert entry['instructions_per_op']==statistics.median(x['instructions']for x in case['measurements'])/divisor
  assert entry['allocated_bytes_per_op']==statistics.median(x['allocated_bytes']for x in case['measurements'])/divisor
 if'native'in row['measurements']:
  p=row['measurements']['plugin'];n=row['measurements']['native'];assert p['expected_hex']==n['expected_hex'];assert row['native_plugin_ratio']==n['instructions_per_op']/p['instructions_per_op']
 else:assert row.get('notes'),('Unexplained empty native cell',row['id'])
module=None;seen={}
for line in (root/'benchmark_crypto.md').read_text().splitlines():
 if line.startswith('## '):module=line[3:]
 if line.startswith('| `'):
  cells=[s.strip()for s in line.split('|')[1:-1]];assert len(cells)==8,line
  match=re.fullmatch(r'`([^`]+)`(?: \[[A-Z]\])*',cells[0]);assert match,cells[0]
  key=(module,match.group(1));assert key not in seen;seen[key]=cells
assert set(seen)==expected
fmt=lambda v:f'{v:,.0f}'if int(v)==v else f'{v:,.2f}'
for row in display:
 p=row['measurements']['plugin'];n=row['measurements'].get('native');cells=seen[row['module'],row['function']]
 assert cells[1]==row['workload'];assert cells[2]==(f'{row["size"]} B'if isinstance(row['size'],int)else row['size'])
 expectedcells=[fmt(n['instructions_per_op'])if n else'',fmt(p['instructions_per_op']),fmt(n['allocated_bytes_per_op'])if n else'',fmt(p['allocated_bytes_per_op']),f'{row["native_plugin_ratio"]:.2f}×'if n else'']
 assert cells[3:]==expectedcells,(row['id'],cells,expectedcells)
 assert cells[1]and cells[2]and'representative'not in cells[2],row['id']
report={'status':'passed','findings':[],'callable_count':155,'displayed_paired_rows':sum('native'in r['measurements']for r in display),'displayed_unpaired_rows':[r['id']for r in display if'native'not in r['measurements']],'workload_row_count':len(rows),'artifact_pin_count':len(pins['source_and_artifact_sha256']),'verified_stages':list(stages),'files_sha256':{str(p.relative_to(root)):sha(p)for p in [root/'benchmark_crypto.md',rnd/'api-inventory.json',rnd/'api-measurements.json',rnd/'api-selection.json',rnd/'api-final-fingerprint.json',Path(__file__).resolve()]},'checks':['Independent155callableinventory including constructors,returnedmethods andaliases; types/constants/privateclasses excluded.','All displayed values recomputed fromexact3successfultrials withsameoutputoracle; nativecells emptyexactlywhenunpaired.','Sourcefixture,canisterbinary,compiler/RTS/PocketIC/runnerprovenance checked by strict reader; finalplugin/modulefingerprints compared tocurrentproduction andfrozencohorts.','Everyblanknativecell has per-rowjustification; everytableworkload hasconcretesize.','AllfrozenMopssources verifiedagainstlockedcontenthashes; allfinalpluginnativesourcebuildpins verified.'],'limitations':['This executablecheck validates coverage,numbersandprovenance; semantic counterpart suitability additionallyrequires manualfixture/adapter review.']}
a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(report,indent=2)+'\n');print(a.out)
