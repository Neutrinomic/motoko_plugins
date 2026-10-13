# Prepared BLS verification

All **72 PocketIC trials passed**: 24 cases, three fresh canisters each. Production is `347d1c3`; independent correctness audit is `f40948c`. [Complete measurements and models](measurements.md), [machine-readable summary](summary.json).

Direct and prepared calls use the **same compiler, plugin artifacts, fixtures and improved direct implementation**, including the shared immutable G2 generator table. Preparation is measured separately. The following columns compare one direct verification with one verification using an existing prepared key; they do not hide preparation in the direct row. Every instruction/allocation sample was identical across the three trials.

| Operation | Direct instructions | Prepared instructions | Reduction | Allocated bytes, direct → prepared |
|---|---:|---:|---:|---:|
| IC single | 222,072,725 | 172,121,515 | 22.49% | 19,672 → 64 |
| Ethereum single | 286,405,944 | 274,167,416 | 4.27% | 39,280 → 39,280 |
| IC aggregate, 2 distinct messages | 310,532,835 | 210,626,139 | 32.17% | 40,552 → 544 |
| Ethereum aggregate, 2 distinct keys | 949,824,696 | 377,014,114 | 60.31% | 138,824 → 60,600 |
| Ethereum aggregate, 8 repeated references | 565,078,557 | 278,645,699 | 50.69% | 82,680 → 43,904 |
| Ethereum aggregate, 8 separately prepared equal keys | 565,078,557 | 278,645,699 | 50.69% | 82,680 → 43,904 |
| Ethereum aggregate, 8 distinct keys | 3,285,303,573 | 994,060,838 | 69.74% | 494,840 → 181,552 |
| Ethereum fast aggregate, 2 distinct keys | 850,994,532 | 278,183,952 | 67.31% | 118,064 → 39,840 |

The setup and storage costs are explicit:

| Operation | Preparation instructions | Created values / key references | Prepared payload bytes | First cheaper use, modeled |
|---|---:|---:|---:|---:|
| IC single | 49,992,831 | 1 / 1 | 19,680 | 2 |
| Ethereum single | 12,239,690 | 1 / 1 | 144 | 2 |
| IC aggregate, 2 distinct messages | 99,985,582 | 2 / 2 | 39,360 | 2 |
| Ethereum aggregate, 2 distinct keys | 572,812,094 | 2 / 2 | 288 | 2 |
| Ethereum aggregate, 8 repeated references | 286,406,258 | 1 / 8 | 144 | 1 |
| Ethereum aggregate, 8 separately prepared equal keys | 2,291,247,278 | 8 / 8 | 1,152 | 8 |
| Ethereum aggregate, 8 distinct keys | 2,291,247,278 | 8 / 8 | 1,152 | 2 |
| Ethereum fast aggregate, 2 distinct keys | 572,812,094 | 2 / 2 | 288 | 2 |

The repeated-key rows use identical keys, messages, proofs and signatures. One explicitly prepares a single key and stores eight references. The other executes eight factories and retains eight equal values. The verification cost is identical, but setup rises from **286,406,258 to 2,291,247,278 instructions** and the payload from **144 to 1,152 bytes**. Factories do not cache or intern equal prepared values. Reuse the returned value when the application already knows it has the same key.

Break-even uses the arithmetic model **P + N × H < N × D**, where P is measured preparation, H is a measured prepared call, and D is a measured direct call. [The detailed table](measurements.md) shows N = 1, 2, 10 and 100; these are projections, not large-batch measurements. Most first uses are nearly cost-neutral and become cheaper on the second use. The shared repeated-key case is only 26,600 instructions cheaper on its first modeled use; eight separate equal-key preparations need eight uses to amortize.

Payload sizes exclude ordinary Blob, variant, option, record and array overhead. IC stores a canonical key plus pairing coefficients (19,680 bytes); either Ethereum prepared type stores a canonical key plus affine coordinates (144 bytes). Ethereum single verification still allocates its message/signature pairing scratch, so its allocation remains 39,280 bytes despite faster key handling. Prepared actors are 2,072–17,566 Wasm bytes larger than their direct counterparts, including their explicit preparation and storage code.

All sampled Wasm capacities were **128 MiB**. Heap snapshots include setup allocations and message overhead; every benchmark snapshot reported **zero reclaimed bytes**, even after four further GC increments. They are occupied-heap observations, not retained-live-heap or peak measurements. In particular, an Ethereum prepared call can start with more occupied heap because its earlier preparation scratch has not yet been collected. The payload counts above describe the explicit values retained by the application, rather than pretending these snapshots isolate them.

The independent Ash pressure test separately proved collection: more than **4 MiB** was reclaimed while nine prepared keys remained valid through arrays and a capturing closure. It interleaved fresh keys over thirteen suspension boundaries and completed 186 post-suspension verifications. Its final empty-callback metrics are not crypto performance measurements.

[The independent audit](../../../../tests/crypto-audit/prepared/bls12-381/README.md) passed 128 factory, 32 single-verification and 68 aggregate cases, seven native bounds checks, nine type/Candid rejection cases, and seven Ash tests. Public tests passed in the interpreter and validated memory64 Wasm. [Owner validation](validation/validation.json) adds 28 runtime tests and six vendored-hook tests, including exact coefficient/generator parity. No production audit findings remained.

Prepared values are immutable, GC-managed and local: they cannot be forged from Blobs, sent through Candid or stored across upgrades. The Ethereum decode-only key and proof-validated key are distinct types; only the latter enters prepared aggregate verification. Factories retain canonical/subgroup/nonidentity checks and PoP verification, and consumers still validate signatures and enforce each profile's message and batch rules. Raw APIs retain their full validation. [Public API and representation](../../../../plugins/bls12-381/README.md).

The immutable stage is [build](../results/prepared-bls12-381-final/build.json) and [results](../results/prepared-bls12-381-final/results.json). [Fixtures](fixtures.json), [generator](generate.py) and [manifest](cases.json) preserve the independent IC/Ethereum/py_ecc inputs. Setup, result checking and heap queries are outside the timed interval; preparation remains included in the separate preparation rows. Source, runtime, compiler, RTS, PocketIC and dependency hashes are retained with the evidence.

After measurement, the current generator and manifest methodology text was clarified to describe all eight comparison groups and distinguish factory PoP checks from the untimed output oracle. Actor sources and the immutable measured stage are unchanged.
