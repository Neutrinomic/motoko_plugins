# Typed JSON: PocketIC instruction costs

The standalone JSON plugin encodes Motoko values and decodes directly into
the requested Motoko type, returning `#ok` or a structured `#err`.
These measurements use compiler plugin ABI 2 and PocketIC 14.0.0.

| Workload | Encode instructions | Decode instructions | Encode allocated bytes | Decode allocated bytes |
|---|---:|---:|---:|---:|
| Small record | 15,105 | 20,703 | 936 | 1,304 |
| 1,024 records | 10,652,793 | 30,899,899 | 226,640 | 1,371,360 |
| 64 KiB Blob | 3,257,044 | 7,353,704 | 175,136 | 218,840 |

Three trials produced identical counts for all six operations. Every trial
uses a fresh canister; all 18 measurements passed their correctness checks,
with zero reclaimed bytes during measurement. There is no native JSON library
baseline in this report.

Input construction and four forced GC increments happen before measurement.
The interval includes the plugin call, successful Result unwrapping, and
retained output assignment. Validation, UTF-8 reply conversion, and
message-end GC are excluded. Allocation counts include temporary parser and
writer storage; they are cumulative allocation, not retained memory or RSS.

Encoder outputs are parsed by the host's `JSON.parse` and checked against
independent Python-generated data. Decoder inputs come from Python; a separate
actor query checks the entire decoded value against independently constructed
Motoko data. The decoder's reported two-byte output is that query's `"ok"`
response, not the size of its typed result.

The record contains a boolean, an exact `Nat64`, Unicode text, and an optional
text field. Blob JSON is padded base64. Decoding counts array elements before
allocating their managed result; scalar syntax scans avoid copying skipped
strings and numbers. Nested arrays still repeat syntax scans, and object keys
allocate storage for duplicate detection. The parser does not build a generic
JSON tree.

- [Raw results](results.json), [CSV](summary.csv), [actor](main.mo),
  [manifest](cases.json), and [frozen runner](runner.mjs).
- [Source and artifact hashes](provenance.json), [plugin build metadata](build.json).
- [Reproduction commands and measurement protocol](../../README.md#typed-json).

The build metadata records the plugin working tree before its combined commit;
the provenance file identifies the exact measured sources by hash. The frozen
runner requires explicit `--sdk-package` and `--canonicalizer` paths when run
from this archive directory.
