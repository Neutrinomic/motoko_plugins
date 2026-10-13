#!/usr/bin/env python3
"""Independently check checked-in ACVP answers against the pinned NIST sources.

This does not import or execute the author's extraction script. It verifies raw
source hashes, exact filtered case identities/bytes and public format sizes.
"""
import hashlib
import json
from pathlib import Path
import urllib.request

ROOT = Path(__file__).resolve().parents[4]
DATA = ROOT / 'plugins/ml-dsa/tests/vectors/acvp-ml-dsa-44.json'
REPORT = Path(__file__).with_name('acvp-provenance.json')


def run():
    selected = json.loads(DATA.read_text())
    commit = selected['sourceCommit']
    assert commit == '975de31eb83d87039ec88934fdc47d8c312b892d'
    counts = {'keyGen': 25, 'sigGen': 30, 'sigVer': 15}
    rows = []
    for operation, source in selected['sources'].items():
        url = source['url']
        assert url.startswith(f'https://raw.githubusercontent.com/usnistgov/ACVP-Server/{commit}/')
        raw = urllib.request.urlopen(url, timeout=60).read()
        sha = hashlib.sha256(raw).hexdigest()
        assert sha == source['sha256']
        upstream = json.loads(raw)
        wanted = {}
        for group in upstream['testGroups']:
            if group['parameterSet'] != 'ML-DSA-44': continue
            if operation != 'keyGen' and (group['signatureInterface'], group['preHash']) != ('external', 'pure'): continue
            if operation == 'sigGen' and group['keyFormat'] != 'seed': continue
            for case in group['tests']:
                identity = (group['tgId'], case['tcId'])
                assert identity not in wanted
                wanted[identity] = (case, group)
        assert len(wanted) == counts[operation] == len(selected[operation])
        actual_ids = set()
        for row in selected[operation]:
            identity = (row['tgId'], row['tcId'])
            assert identity not in actual_ids
            actual_ids.add(identity)
            case, group = wanted[identity]
            for field, value in row.items():
                if field in ('tgId', 'tcId'): continue
                if field == 'deterministic': assert value == group[field]
                elif field == 'rnd' and group['deterministic']:
                    assert value == '00' * 32
                else: assert value == case[field], (operation, identity, field)
            assert len(bytes.fromhex(row['pk'])) == 1312
            if operation in ('keyGen', 'sigGen'):
                assert len(bytes.fromhex(row['seed'])) == 32
            if operation in ('sigGen', 'sigVer'):
                assert len(bytes.fromhex(row['signature'])) == 2420
                assert len(bytes.fromhex(row['context'])) <= 255
        assert actual_ids == set(wanted)
        rows.append({'operation': operation, 'cases': len(wanted), 'url': url, 'sha256': sha})
    report = {'passed': True, 'sourceCommit': commit,
              'selectedFile': str(DATA.relative_to(ROOT)),
              'selectedSha256': hashlib.sha256(DATA.read_bytes()).hexdigest(), 'sources': rows,
              'note': 'External pure ML-DSA interface; seed-format sigGen only. Internal-interface and HashML-DSA cases deliberately excluded.'}
    REPORT.write_text(json.dumps(report, indent=2) + '\n')
    print(json.dumps(report, indent=2))


if __name__ == '__main__': run()
