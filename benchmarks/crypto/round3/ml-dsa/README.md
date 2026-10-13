# ML-DSA-44 public API measurements

PocketIC 10.0.0, normal production application-subnet instruction limits,
three fresh-canister trials per case. Every measured result matched the pinned
NIST ACVP external-interface answer; all 33 trials passed and each case had
identical counters across its three trials. These are algorithm examples, not
statistical latency measurements or cross-algorithm security equivalence claims.

| Operation / official case | Message bytes | Context bytes | Instructions | Allocated bytes |
|---|---:|---:|---:|---:|
| Seed → public key, case 4 | — | — | 5,109,077 | 1,368 |
| Deterministic sign, case 4 | 1 | 59 | 14,753,165 | 2,480 |
| Verify, case 4 | 1 | 59 | 3,806,359 | 32 |
| Deterministic sign, case 6 | 1,188 | 0 | 27,591,733 | 2,480 |
| Verify, case 6 | 1,188 | 0 | 3,901,500 | 32 |
| Deterministic sign, case 11 | 8,192 | 255 | 10,296,367 | 2,480 |
| Verify, case 11 | 8,192 | 255 | 4,466,575 | 32 |
| Hedged sign, case 362 | 871 | 0 | 19,923,901 | 2,480 |
| Verify, case 362 | 871 | 0 | 3,869,744 | 32 |
| Hedged sign, case 373 | 1 | 227 | 24,987,237 | 2,480 |
| Verify, case 373 | 1 | 227 | 3,826,997 | 32 |

Signing includes full expansion of the 32-byte secret seed on every call. Its
rejection sampling explains why an 8 KiB message can sign faster than a shorter
message with another key/context. The first row measures the separate public
key-generation operation, including public-key serialization; it is not a
subtraction-based estimate of the internal expansion inside signing.

The fixed output sizes are 1312-byte public keys and 2420-byte signatures.
Inputs exist before measurement; decoding and all arithmetic execute inside
it. `#ok` unwrapping and result assignment are included; result serialization
and exact oracle comparison run afterward. Allocation measures cumulative
Motoko heap allocation, including temporary objects; every measured operation
reported zero synchronous reclamation. These initial actors do not report
occupied heap or page peaks. The final combined round-three harness measures
those separately; allocation must not be read as retained/live memory.

The runtime uses no allocator. A conservative analysis of its acyclic Wasm
call graph bounds runtime stack frames at 134,016 bytes for key generation,
129,776 bytes for signing and 93,696 bytes for verification, excluding the
Motoko caller. [Stack checker](check-stack.py) and [exact runtime hash/results](validation/stack.json).

## Evidence and reproduction

- [Build manifest](../../results/round3-mldsa-initial/build.json), [raw trials](../../results/round3-mldsa-initial/results.json), and [counter log](validation/benchmark-run.txt).
- [Exact frozen source archive](initial-sources.tar.gz), including plugin input hashes, Cargo lock, module and dependency sources; compiler/RTS executable hashes are in the build manifest. No generated binary is committed.
- [Validation hashes](validation/sha256.json), [native tests/build](validation/plugin-build.txt), [17 public Ash tests](validation/ash-tests.txt), and [independent audit](../../../../tests/crypto-audit/round3/ml-dsa/README.md).
- [Pinned NIST vector corpus and provenance](../../../../plugins/ml-dsa/tests/vectors/README.md).

From the plugins repository root, build the plugin with the matching Motoko
compiler, then generate and run the examples with a new, unused stage name:

```sh
python3 benchmarks/crypto/round3/ml-dsa/generate.py
python3 benchmarks/crypto/build.py --manifest benchmarks/crypto/round3/ml-dsa/cases.json --stage mldsa-reproduction
node benchmarks/crypto/run.mjs --build benchmarks/crypto/results/mldsa-reproduction/build.json --out benchmarks/crypto/results/mldsa-reproduction/results.json --trials 3
```

The existing crypto harness pins Mops sources even though these cases load
only `mo:fast/MLDSA`. See [the harness requirements](../../README.md).
The recorded source archive is the exact initial build; a subsequent test-only
Rust formatting edit changed its source metadata but not the runtime bytes.
Both artifacts have the same `565cd012…bbd35e` runtime SHA-256.
