#!/usr/bin/env python3
"""Generate identical SHA-only actors and Python hashlib oracles for this round."""
import hashlib
import json
from pathlib import Path

out = Path(__file__).resolve().parent
sizes = [0, 1, 31, 32, 33, 55, 56, 63, 64, 65, 119, 120, 127, 128, 129, 1024, 65536, 1048576]
source = '''import Prim "mo:⛔";
import SHA256 "mo:sha2/Sha256";
actor {
  type Measurement = { instructions : Nat64; allocated : Nat; reclaimed : Nat; outputSize : Nat };
  transient var bytes : Blob = "";
  transient var output : Blob = "";
  public func configure(index : Nat) : async () {
    let sizes : [Nat] = [SIZES];
    var state : Nat32 = 0x9e37_79b9;
    bytes := Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(sizes[index], func(_) {
      state := state ^ (state << 13);
      state := state ^ (state >> 17);
      state := state ^ (state << 5);
      Prim.natToNat8(Prim.nat32ToNat(state & 255))
    }));
  };
  public func clear() : async () { output := "" };
  public query func bytesResult() : async Blob { output };
METHODS
}
'''.replace('SIZES', ', '.join(map(str, sizes)))
methods = []
for name, expr in [('plugin', 'Prim.sha256(bytes)'), ('native', 'SHA256.fromBlob(#sha256, bytes)')]:
    methods.append('''  public func NAME() : async Measurement {
    let allocatedBefore = Prim.rts_total_allocation();
    let reclaimedBefore = Prim.rts_reclaimed();
    let started = Prim.performanceCounter(0);
    output := EXPR;
    let ended = Prim.performanceCounter(0);
    let allocatedAfter = Prim.rts_total_allocation();
    let reclaimedAfter = Prim.rts_reclaimed();
    { instructions = ended - started; allocated = allocatedAfter - allocatedBefore;
      reclaimed = reclaimedAfter - reclaimedBefore; outputSize = output.size() }
  };'''.replace('NAME', name).replace('EXPR', expr))
(out / 'main.mo').write_text(source.replace('METHODS', '\n'.join(methods)))
cases = []
for index, size in enumerate(sizes):
    state = 0x9e3779b9
    payload = bytearray()
    for _ in range(size):
        state = (state ^ (state << 13)) & 0xffffffff
        state ^= state >> 17
        state = (state ^ (state << 5)) & 0xffffffff
        payload.append(state & 255)
    cases.append({'index': index, 'name': f'sha256-{size}', 'family': 'sha256',
                  'input_bytes': size, 'expected_sha256_hex': hashlib.sha256(payload).hexdigest(),
                  'phases': [{'label': name, 'method': name, 'kind': 'sha256', 'require_no_gc': name == 'plugin'}
                             for name in ['native', 'plugin']]})
(out / 'cases.json').write_text(json.dumps({'suite': 'optimization-round-sha256',
    'sha256_inputs': {'generator': 'xorshift32, low byte after each step', 'seed': '0x9e3779b9', 'shifts': [13, -17, 5]},
    'implementations': {'native': 'Mops sha2 0.2.5, Sha256.fromBlob(#sha256, bytes)', 'plugin': 'ABI 1 Prim.sha256'},
    'cases': cases}, indent=2) + '\n')
