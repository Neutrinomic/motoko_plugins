#!/usr/bin/env python3
"""Reapply the declared patch to the pinned registry archive, independently."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--archive',type=Path,required=True)
parser.add_argument('--out',type=Path,required=True)
args=parser.parse_args()
vendor=ROOT/'plugins/secp256k1/runtime/vendor/k256'
ledger=json.loads((vendor/'upstream-source.json').read_text())
assert sha(args.archive)==ledger['archive_sha256']
assert sha(vendor/'exact.patch')==ledger['exact_patch_sha256']
assert (vendor/'exact.patch').stat().st_size==ledger['exact_patch_bytes']
with tempfile.TemporaryDirectory(prefix='secp-round4-vendor-') as temporary:
    with tarfile.open(args.archive) as archive:
        archive.extractall(temporary,filter='data')
    original=Path(temporary)/'k256-0.13.4'
    upstream=ledger['upstream_files_sha256']
    assert {str(p.relative_to(original)) for p in original.rglob('*') if p.is_file()}==set(upstream)
    for relative,digest in upstream.items():
        assert sha(original/relative)==digest,relative
        if relative in ledger['changed_upstream_files']:
            item=ledger['changed_upstream_files'][relative]
            assert item['upstream_sha256']==digest
            assert sha(vendor/relative)==item['patched_sha256']
        else: assert sha(vendor/relative)==digest,relative
    patch=subprocess.run(['patch','--batch','--fuzz=0','-p1','-i',str(vendor/'exact.patch')],cwd=original,text=True,capture_output=True)
    assert patch.returncode==0,patch.stdout+patch.stderr
    for relative in upstream.keys()|ledger['added_source_files_sha256'].keys():
        assert (original/relative).read_bytes()==(vendor/relative).read_bytes(),relative
    for relative,digest in ledger['added_source_files_sha256'].items():
        assert sha(vendor/relative)==digest
report={'passed':True,'archive_sha256':sha(args.archive),'ledger_sha256':sha(vendor/'upstream-source.json'),
        'exact_patch_sha256':sha(vendor/'exact.patch'),'original_files':len(upstream),
        'changed_original_files':len(ledger['changed_upstream_files']),
        'added_source_files':len(ledger['added_source_files_sha256']),
        'patch_stdout':patch.stdout,'script_sha256':sha(Path(__file__)),
        'method':'Compared every archive file with the pinned ledger and unchanged/changed vendor source; applied exact.patch without fuzz, then compared every patched or added source byte.'}
args.out.write_text(json.dumps(report,indent=2)+'\n')
print('pinned upstream archive and exact patch: passed')
