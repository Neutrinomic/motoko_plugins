# Heap allocation comparisons

These are the allocation counters from the same three-trial PocketIC runs as
[the instruction comparison](README.md). Each cell is the median **bytes
allocated during one complete operation**, including result objects and
intermediate garbage. Input preparation, validation, and message-end GC are
excluded. Allocation is not peak Wasm memory, host RSS, or retained live memory
after GC. No synchronous reclamation occurred in successful measured phases.

All library versions, compiler versions, inputs, conversions, and validation
boundaries are unchanged from that report. Failed decoders have no allocation
comparison; their partial work is not treated as a successful result.

| Operation | serde 3.5.0 bytes | serde-core 0.2.1 bytes | json 1.4.0 / cbor 4.1.0 bytes | Plugin bytes |
| --- | ---: | ---: | ---: | ---: |
| json-record-encode | 38,304 | 217,280 | 8,472 | 968 |
| json-record-decode | 185,312 | 184,072 | 25,312 | 1,000 |
| json-records-1024-encode | 17,766,800 | 100,570,736 | 7,145,616 | 194,208 |
| json-records-1024-decode | 136,203,896 | 144,797,768 | 764,303,144 | 172,848 |
| json-text-64k-encode | 43,260,064 | 321,688,880 | 5,244,360 | 262,600 |
| json-text-64k-decode | stack overflow | stack overflow | 8,043,472 | 65,888 |
| cbor-record-encode | 18,032 | 21,312 | 4,568 | 784 |
| cbor-record-decode | 49,560 | 37,384 | 13,352 | 1,272 |
| cbor-records-1024-encode | 6,041,088 | 6,039,896 | 2,452,232 | 174,224 |
| cbor-records-1024-decode | 22,644,936 | 20,164,416 | 11,545,504 | 173,192 |
| cbor-blob-64k-encode | 6,598,376 | 6,599,224 | 1,676,112 | 131,480 |
| cbor-blob-64k-decode | 9,455,408 | 8,142,752 | 1,145,048 | 65,872 |

Raw counters and every implementation are in [summary.csv](summary.csv).

| Operation | Native library bytes | Plugin bytes |
| --- | ---: | ---: |
| sha256-32 | 1,008 | 56 |
| sha256-65536 | 1,008 | 56 |
| sha256-1048576 | 1,008 | 56 |
| candid-static-record | 24,912 | 136 |
| candid-blob-64k | 138,280 | 65,608 |
| candid-sparse-1024 | 3,578,064 | 22,624 |

The native libraries here are CandidX `94c2868` and `sha2 0.2.5`.
SHA-256 returns a 32-byte digest; the plugin allocates 56 bytes including its
Motoko Blob header, independent of the tested input sizes. Raw results are in
[candidx-sha/summary.csv](candidx-sha/summary.csv).

Persistent-map allocation, retained-version workloads, and cases where the
plugin allocates more than core are in the [map report](../pure-map/README.md).
