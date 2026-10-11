#!/usr/bin/env python3
"""Append the allocation probe to a copied JSON runtime; do not edit production."""
import argparse
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--runtime', type=Path, required=True)
parser.add_argument('--out', type=Path, required=True)
args = parser.parse_args()
source = args.runtime.read_text()
assert '#[cfg(test)]\nmod tests {' in source
end = source.rindex('}')
probe = Path(__file__).with_name('large-error-probe.rs').read_text()
(args.out / 'src').mkdir(parents=True, exist_ok=True)
(args.out / 'src/lib.rs').write_text(source[:end] + probe + source[end:])
(args.out / 'Cargo.toml').write_text(
    '[package]\nname="json-large-error-probe"\nversion="0.0.0"\nedition="2024"\n[workspace]\n')
print(args.out / 'Cargo.toml')
