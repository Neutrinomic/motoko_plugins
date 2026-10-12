# Public module tests with Ash

These 26 configurations define **273 test-method executions** (267 distinct
Motoko method declarations) on PocketIC through Ash. They exercise the public
`mo:fast` modules, independent wire and cryptographic vectors, comparisons with
Core containers, Bitcoin composition, error recovery, persistence, and GC.
Counts describe the configured inventory; validation records apply to the
specific source and plugin artifacts used for each run.

Run from the plugins repository root:

```sh
# All suites using an installed Ash CLI.
scripts/test-ash.sh

# Use an Ash source checkout through Bun.
scripts/test-ash.sh --ash-source /path/to/ash

# Run selected suites by their names below.
scripts/test-ash.sh --ash-source /path/to/ash JSON Set PureSet
scripts/test-ash.sh --ash-source /path/to/ash BLAKE3 Secp256k1 BitcoinCryptoAddress
```

The helper installs the `fast` package's Mops dependencies and runs each selected
configuration with verbose output. Mops must be installed; using an Ash checkout
also requires Bun and that checkout's dependencies.

Build the native plugins in `dist/` against the compiler build that **Ash uses**.
Ash selects `moc`, `didc`, and `pocket-ic` from its own toolchain; inspect it with
`ash bin` (or `bun /path/to/ash/src/index.ts bin`). A different `moc` on your shell
PATH does not change Ash's compiler selection. Native plugin packages and the
host compiler must match; rebuild the plugins when changing that compiler.
The helper does not build plugins or replace Ash's toolchain.

Ash must support the canister `mocArgs` configuration field: these suites use it
to pass `--plugin` and, for GC tests, `--force-gc` and `--sanity-checks`. The helper
checks Ash's schema before running. If an installed release lacks this field,
use `--ash-source` with a checkout that supports it.

CI currently runs the native suite and validates archived benchmark evidence;
it **does not run these Ash suites**. The tested Ash checkout has local
`mocArgs` support that is absent from its published revision. A published
revision with that support is needed before pinning Ash in CI.

## Suites and inventories

Each suite name links to its Motoko source. The configuration loads the required
native plugins; individual module suites also verify that importing a module
does not require unrelated plugins.

| Suite | Tests | Main coverage | Configuration / detailed inventory |
| --- | ---: | --- | --- |
| [BLAKE3](BLAKE3.mo) | 3 | Official hash/keyed/context/XOF vectors, streaming partitions, canonical states, seek and output bounds | [Config](BLAKE3.ash.json) · [Inventory](coverage/BLAKE3.md) |
| [BLS12381](BLS12381.mo) | 2 | G1/G2, MSM, pairings, RFC9380 hash-to-curve, IC/Ethereum signatures, aggregation and proof-of-possession validation | [Config](BLS12381.ash.json) · [Inventory](coverage/BLS12381.md) |
| [Base58](Base58.mo) | 6 | Bitcoin Core vectors, strict alphabet, quotas, Base58Check checksums, error precedence and retained outputs | [Config](Base58.ash.json) · [Inventory](coverage/Base58.md) |
| [Bech32](Bech32.mo) | 8 | BIP173/BIP350 encoding, checksums, bit conversion, SegWit versions/program lengths and malformed addresses | [Config](Bech32.ash.json) · [Inventory](coverage/Bech32.md) |
| [BitcoinCryptoAddress](BitcoinCryptoAddress.mo) | 8 | HASH160/tagged hashes, legacy/SegWit/Taproot addresses, BIP86/BIP341 outputs, signed SegWit/Taproot spends and composed public wallets | [Config](BitcoinCryptoAddress.ash.json) · [Inventory](coverage/BitcoinCryptoAddress.md) |
| [BitcoinCryptoBip32](BitcoinCryptoBip32.mo) | 5 | Official extended-key vectors, non-hardened public derivation, fingerprints, paths, networks and metadata rejection | [Config](BitcoinCryptoBip32.ash.json) · [Inventory](coverage/BitcoinCryptoBip32.md) |
| [BitcoinCryptoTransaction](BitcoinCryptoTransaction.mo) | 2 | Bitcoin Core/BIP143/BIP341 sighashes, transaction parsing/serialization, txid/wtxid, scripts and prepared hash caches | [Config](BitcoinCryptoTransaction.ash.json) · [Inventory](#bitcoin-transaction-inventory) |
| [CBOR](CBOR.mo) | 34 | Exact wire vectors, typed decoding, all binary16 patterns, malformed inputs, quotas, retained results | [Config](CBOR.ash.json) · [Inventory](coverage/CBOR.md) |
| [CandidX](CandidX.mo) | 16 | Canonical bytes, variadic arguments, type joins, recursion, references, quotas | [Config](CandidX.ash.json) · [Inventory](coverage/CandidX.md) |
| [Comparators](Comparators.mo) | 16 | Automatic scalar ordering, aliases and implicit calls, callback effects, multi-value results, allocation | [Config](Comparators.ash.json) · [Inventory](coverage/Comparators.md) |
| [Composition](Composition.mo) | 3 | Eight original codec/hash/container plugins together, recovery after failures, retained managed values across messages | [Config](Composition.ash.json) · [Inventory](#composition-inventory) |
| [CoreAPI](CoreAPI.mo) | 12 | Six identical consumer methods run against Core and Fast; implicit comparators/formatters, Core signatures and types | [Config](CoreAPI.ash.json) · [Inventory](coverage/CoreAPI.md) |
| [MapConversions](MapConversions.mo) | 4 | Both Map conversions, independent bindings, shared payloads, comparator-equivalent keys | [Config](MapConversions.ash.json) · [Inventory](coverage/MapConversions.md) |
| [JSON](JSON.mo) | 33 | Independent JSON output, typed decoding, Unicode, numeric limits, duplicates, structured errors | [Config](JSON.ash.json) · [Inventory](coverage/JSON.md) |
| [HMAC](HMAC.mo) | 4 | RFC4231 SHA256/SHA512 vectors, key/padding boundaries, prepared keys, independent streams and reset | [Config](HMAC.ash.json) · [Inventory](coverage/HMAC.md) |
| [Map](Map.mo) | 17 | 58 existing functions, mutable aliases, differential operations, B-tree boundaries, scalar keys | [Config](Map.ash.json) · [Inventory](coverage/Map.md) |
| [P256](P256.mo) | 15 | RFC6979 signatures and digest reduction, SEC1/DER validation, scalar boundaries, normalization and selected Wycheproof cases | [Config](P256.ash.json) · [Inventory](coverage/P256.md) |
| [PureMap](PureMap.mo) | 22 | 100 existing functions, retained versions, ranges, algebra, builders, callback contracts | [Config](PureMap.ash.json) · [Inventory](coverage/PureMap.md) |
| [PureSet](PureSet.mo) | 16 | All 70 functions, persistent AVL operations, rank/split/join, algebra, scalar keys | [Config](PureSet.ash.json) · [Inventory](coverage/PureSet.md) |
| [RIPEMD160](RIPEMD160.mo) | 4 | Independent binary answers, padding/block boundaries, immutable streaming, malformed states and million-byte input | [Config](RIPEMD160.ash.json) · [Inventory](coverage/RIPEMD160.md) |
| [SHA256](SHA256.mo) | 5 | Independent known answers, padding/block boundaries, million-byte input, aliases | [Config](SHA256.ash.json) · [Inventory](coverage/SHA256.md) |
| [SHA512](SHA512.mo) | 5 | SHA512/SHA384 known answers, padding boundaries, streaming partitions, reset and million-byte inputs | [Config](SHA512.ash.json) · [Inventory](coverage/SHA512.md) |
| [Secp256k1](Secp256k1.mo) | 9 | SEC2 point/tweak operations, RFC6979 ECDSA, strict SEC1/DER, all BIP340 vectors, aliases and actor-frame GC retention | [Config](Secp256k1.ash.json) · [Inventory](coverage/Secp256k1.md) |
| [Set](Set.mo) | 15 | All 66 functions, Core semantics, B-tree removal, nested optional elements, scalar keys | [Config](Set.ash.json) · [Inventory](coverage/Set.md) |
| [SetGC](SetGC.mo) | 2 | Shared native helpers, mixed element types, incremental GC and write barriers | [Config](SetGC.ash.json) · [Inventory](coverage/SetGC.md) |
| [Smoke](Smoke.mo) | 7 | Package imports, codec results, hash pipeline, both map modules and Core conversion | [Config](Smoke.ash.json) · [Inventory](#smoke-inventory) |
| **Total** | **273** | | |

`CoreAPI` runs its six source methods twice, once with Core containers and once
with Fast containers. Every other configuration names one canister. The 12 new
crypto and Bitcoin configurations contribute 71 executions to the earlier
14-configuration, 202-execution inventory. A method may contain many vectors;
these totals count methods rather than individual assertions or vector rows.

`Map` now exposes 61 functions and `pure/Map` 101; `MapConversions` and
`CoreAPI` cover their conversions and `toMap` additions. `CoreAPI` changes only
the imported container package, so implicit argument resolution and ordinary
Core call sites must compile and execute unchanged with either implementation.

### Composition inventory

Methods: `test_roundtrip_pipeline_and_map_queries`,
`test_failures_do_not_poison_later_plugin_calls`, and
`test_gc_retains_results_and_shared_payloads`.

### Smoke inventory

Methods: `test_json_typed_result`, `test_cbor_typed_result`,
`test_canonical_hash_pipeline`, `test_sha256_known_answer`,
`test_mutable_map_aliases`, `test_pure_map_versions`, and
`test_core_map_conversion`.

### Bitcoin transaction inventory

`test_bitcoin_core_bip143_bip341_vectors` calls
[BitcoinCryptoTransactionVectors.mo](../lib/BitcoinCryptoTransactionVectors.mo):
500 Bitcoin Core legacy sighashes, published BIP143 cases, BIP341 wallet and
pinned Core annex/tapscript answers, TapLeaf/branch roots, signed transaction
round trips, txid/wtxid, prepared caches, and signature-hash edge cases.

`test_serialization_sighash_and_script_edges` calls
[BitcoinCryptoTransactionCases.mo](../lib/BitcoinCryptoTransactionCases.mo):
truncated/trailing/noncanonical encodings, hostile counts, witness flags and
empty witnesses, CompactSize boundaries, invalid sighash/annex/extension/prevout
inputs, and script data-push/output boundaries. Both Ash methods and the compiler
run fixtures reuse these assertion groups.

### Independent crypto audits and benchmarks

Cryptographic known answers are committed separately from the implementations:
the suite inventories identify BLAKE3 upstream vectors, RFC4231/RFC6979/RFC9380,
Bitcoin Core and BIP vectors, Wycheproof, and independent OpenSSL/Python answers.
Round trips supplement these fixed expectations.

Additional native and Motoko audit drivers live under
[`tests/crypto-audit`](../../../../tests/crypto-audit/), outside Ash's method
counts. They cover hash/codec buffer and streaming-state contracts, malformed
curve encodings and signature boundaries, and BLS subgroup/profile/domain
separation. The [test guide](../../../../tests/README.md#independent-crypto-audits)
links their runners and provenance. Audit output applies to the recorded
source/artifact hashes; the presence of an audit fixture is not an execution
result.

Comparative measurements live under
[`benchmarks/crypto`](../../../../benchmarks/crypto/). Those workloads isolate
operations and retain expected outputs, source/artifact hashes and measurement
conditions. They report IC instructions, allocation and Wasm size separately
from the correctness closures below.

## What the results establish

Known-answer vectors and independently constructed expectations complement
round trips and differential checks. Container suites test public operations
and invariants with deterministic sequences and boundary sizes. The Set GC
regression also calls native primitives directly to exercise helper sharing
between concrete element types.

Comparator tests preserve aliases, custom ordering, callback effects and
argument evaluation across all four container plugins. Membership through
opaque managed keys allocates zero bytes; typed Nat64 locals can independently
require boxing at generic calls, as detailed in the comparator inventory.

This is finite behavioral coverage, not proof for every input, native branch,
or runtime state. Compile-fail cases, expected traps, interpreter agreement,
and upgrade checks remain in the separate compiler/plugin test suites. The
inventories identify additional limits and which assertions cover each API.
The accompanying native suite checks interpreter/Wasm agreement, crypto
composition, and standalone package loading with missing or present runtimes.
Rust kernels have separate unit tests against the pinned toolchain.

Ash's instruction and heap figures measure correctness-test closures, usually
including setup, independent oracles, and assertions. The asynchronous GC tests
measure only their final verification. These figures are **not plugin
performance comparisons**. Allocation assertions in selected container tests
check specific no-allocation or bounded-copy contracts; they do not describe
the memory cost of every workload.
