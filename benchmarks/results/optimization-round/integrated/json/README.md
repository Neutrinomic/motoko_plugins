# Integrated JSON measurements

The final JSON package, rebuilt against compiler
`c320bf90d0b63a058b5de2c41a42c96e8b82243f`, preserves the audited JSON gains.
The SDK array builder additionally saves 10,239 instructions when decoding
1,024 records. JSON production sources and runtime Wasm are unchanged from
[the audited JSON round](../../json/README.md).

| Focused workload | Original baseline instructions | Audited JSON instructions | Integrated instructions | Original → integrated allocated bytes |
| --- | ---: | ---: | ---: | ---: |
| Small record encode | 11,270 | 8,803 | 8,803 | 768 → 776 |
| Small record decode | 17,372 | 14,861 | 14,861 | 872 → 880 |
| Empty record array decode | 1,379 | 1,363 | 1,364 | 352 → 328 |
| 1,024 records encode | 7,714,028 | 5,034,822 | 5,034,822 | 193,864 → 193,832 |
| 1,024 records decode | 23,844,170 | 18,303,758 | 18,293,519 | 129,136 → 129,104 |
| Nested records decode | 33,909,381 | 25,772,907 | 25,762,380 | 130,160 → 130,128 |
| Late record error | 23,861,723 | 18,318,563 | 18,308,310 | 129,440 → 129,440 |

Allocation is unchanged from the audited JSON round for every measured phase.
The SDK adds **one instruction** to empty-array decoding versus that round;
it remains below the original baseline. The audited **eight-byte allocation
increase** remains for small record encode/decode and the small error versus
the original baseline. All 15 focused workloads remain below the original
baseline's instruction counts. Blob/scalar costs are effectively unchanged.

The native comparison uses its own actor with matching Bool/Text record wire
semantics. Its typed/tree or Candid conversions remain inside measurement.
All native-library counters are unchanged from the audited run; the plugin's
1,024-record decoder changes from 18,261,968 to **18,251,729 instructions**, with
172,816 allocated bytes. Both `serde` and `serde-core` still overflow the stack
on 64 KiB Text decoding in each of three trials: all six expected failures
remain in the report. No plugin phase fails.

Three trials use the exact original actors, manifests and frozen runner.
All successful outputs match all three versions; counters are deterministic,
and synchronous reclamation is zero. Inputs and four forced GC increments
precede measurement; validation and message-end GC follow it. Allocation is
cumulative requested heap bytes, including scratch, rather than retained heap
size. The decoder reply is the two-byte validation marker, not decoded size.

The final compiler passed all 10 permanent JSON Motoko fixtures, including
limits, error paths and retained values across GC, plus 604 independent scalar
and 161 binary/Unicode cases through source, IR, lowered IR and Wasm. These
integration tests used copies under `_build/opt-json-integrated` to preserve
production fixtures. The unchanged runtime retains the earlier 20 Rust tests
and 9,263 syntax-oracle results; those were not rerun in this integration step.

Evidence:

- [Comparison CSV](comparison.csv): all 39 phases across original baseline,
  audited JSON, and integrated versions, including instructions and allocations.
- [Focused raw trials](plugin/final.json), [native raw trials](native/final.json).
- [Provenance](provenance.json), [package/compiler/source hashes](package.json),
  [independent integration audit](audit.md).
- [Motoko fixture log](validation/motoko-tests.txt),
  [independent value log](validation/audit-values.txt),
  [generated corpus manifest](validation/audit-manifest.json).
- [Archive validator](summarize.py): Python standard library only; verifies
  complete trials, exact input/output hashes, expected failures and counters,
  then regenerates `comparison.csv`. CI runs this in a temporary archive copy.

The actual canonical compiler binary SHA-256 is
`722ba089cc3f6fb7710423363c3adc55d0af9f841eaa5a283e97eb08f3c8335c`.
It has the audited SDK source revision; its build path differs from the SDK
candidate build. Runtime Wasm remains
`90515e9744aed97da77ecaca14d9729c6f7c62b6911391de9920c8ced313545e`.
All actor and package fingerprints are recorded in provenance and raw reports.

To reproduce, enter the compiler's Nix shell from its checkout, then change
to the canonical plugin repository. Use the already-built canonical package;
these commands do not rebuild the compiler or plugins. Set `MOTOKO_ROOT` to
the compiler checkout. The native build helper checks the existing archived
Mops lock against `_build/codec-comparison/deps`, including every package file.
Write new reports to scratch so the archived measurements remain immutable.

```sh
json_archive=benchmarks/results/optimization-round/integrated/json
json_scratch=_build/opt-json-integrated
mkdir -p "$json_scratch/plugin" "$json_scratch/native"
cp "$json_archive/plugin/main.mo" "$json_archive/plugin/cases.json" "$json_scratch/plugin/"
cp "$json_archive/native/main.mo" "$json_archive/native/cases.json" "$json_scratch/native/"
"$MOTOKO_ROOT/bin/moc" --plugin dist/json \
  "$json_scratch/plugin/main.mo" -o "$json_scratch/plugin/main.wasm"
python3 benchmarks/build-codec-comparison.py --motoko "$MOTOKO_ROOT" \
  --deps _build/codec-comparison/deps --codec json --out "$json_scratch/native"
node "$json_archive/run.mjs" --wasm "$json_scratch/plugin/main.wasm" \
  --cases "$json_scratch/plugin/cases.json" --out "$json_scratch/plugin/reproduction.json" \
  --label json-integrated --trials 3 --delete-canisters true \
  --sdk-package /srv/shared/code/candidx/ts/package.json \
  --canonicalizer /srv/shared/code/candidx/ts/dist/index.js
node "$json_archive/run.mjs" --wasm "$json_scratch/native/main.wasm" \
  --cases "$json_scratch/native/cases.json" --out "$json_scratch/native/reproduction.json" \
  --label json-native-integrated --trials 3 --delete-canisters true \
  --sdk-package /srv/shared/code/candidx/ts/package.json \
  --canonicalizer /srv/shared/code/candidx/ts/dist/index.js
python3 "$json_archive/summarize.py"
```

The native runner exits 1 for the six declared stack-overflow measurements;
inspect their exact rows rather than treating that exit as a plugin failure.
The final command validates the archived reports, independently of any new
reproduction results written to scratch.
