#!/usr/bin/env python3
"""Restore an exact stage source snapshot into a new directory."""
import argparse
import importlib.util
from pathlib import Path

HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location('prepared_sources', HERE/'pack-sources.py')
sources = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sources)


def restore(stage, out, here=HERE):
    sources.stage_name(stage)
    _, blobs, maps = sources.load_store(here)
    assert stage in maps, 'Stage absent from packed source store'
    out.mkdir(parents=True, exist_ok=False)
    for name, pin in maps[stage]['files'].items():
        target = out/sources.relative(name)
        target.parent.mkdir(parents=True, exist_ok=True)
        with target.open('xb') as output:
            output.write(blobs[pin['sha256']])
        target.chmod(pin['mode'])
    return out


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence-root', type=Path, default=HERE)
    parser.add_argument('--stage', required=True)
    parser.add_argument('--out', required=True, type=Path)
    args = parser.parse_args()
    print(restore(args.stage, args.out, here=args.evidence_root.resolve()))


if __name__ == '__main__':
    main()
