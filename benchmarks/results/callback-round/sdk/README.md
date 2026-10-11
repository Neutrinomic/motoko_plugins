# Plugin callback argument dispatch

Compiler `fc7612098` removes redundant argument spills from `Call.local`.
Closure evaluation and argument effects still run once, left to right. The
prepared closure and earlier arguments remain on the Wasm operand stack, just
as they do for ordinary Motoko calls. ABI 1 and the callback API are unchanged.

PocketIC results below include the loop, arithmetic, counters and callback
dispatch for **4,096 calls**, with three identical trials per case:

| Callback arguments | Before instructions | After instructions | Saved per call | Total reduction |
| --- | ---: | ---: | ---: | ---: |
| 0 | 749,885 | 749,885 | 0 | 0% |
| 1 | 930,109 | 917,821 | 3 | 1.32% |
| 2 | 950,589 | 930,109 | 5 | 2.15% |

All phases allocate **0 bytes** and reclaim **0 bytes**. These are cumulative
allocation/reclamation counters, not live or peak memory. Zero-call controls
are 317 instructions on both versions; single-call cases show the same exact
0/3/5 savings. There are 54 successful samples across the two builds.

Deleting a local store and load saves two instructions per argument. For
nonempty argument lists, the closure store and read become adjacent, allowing
the existing compiler peephole to replace them with one `local.tee`.

The actor uses callbacks stored in mutable fields to require dynamic dispatch.
Its arithmetic checksum is verified outside timing. Both binaries load the
**same baseline callback fixture**, whose source is archived here; the fixture
ABI did not change. The baseline is `abfba892f`, the candidate is clean commit
`fc7612098`. Exact compiler, runtime, fixture, source and actor hashes are in
`provenance.json`. Compiler version strings differ outside the measured code.
Actor binaries are omitted from this source archive.

`baseline-and-pilot.log` records baseline execution and the initial dirty
candidate pilot. The authoritative candidate report is `candidate.json`,
generated again after the clean compiler commit; `final-candidate.log` records
that rerun. The pilot has the same counts but is not relabeled as the final
compiler. `callback-committed-tests.log` records **53 passing SDK tests plus
packaging checks** on the final binary. The full release native/JS build and
unit checks passed before the version-only rebuild (`callback-build.log`).
The existing JS `caml_unix_map_file_bytecode` warning is unchanged.

Run `python3 verify.py` to check archived source/provenance hashes, sample
coverage, exact per-call instruction deltas and allocation/reclamation counts.
See `commands.txt` for compilation and measurement commands.

## Further opportunities

This small change does not remove the entire generic-versus-scalar gap. The
generic path still dispatches a closure and decodes `Order`; the ordinary
boxed `Nat64.compare` body can unbox its operands again for the equality test.
Its nullary `Order` variants are constants, not a fresh allocation per call.

A scoped prepared-callback helper could retain a managed closure and immutable
function-table index for a traversal, saving roughly four more instructions
per comparison before setup costs. Pure-map lookup has a suitable loop;
recursive updates would need extra helper parameters, and mutable-map lookup
would otherwise prepare once per node. The emitter must prevent captured
caller-local getters from being used in a different shared helper function.
That API and complexity are not included in this change.

A larger follow-up could preserve known callback identity through intrinsic
aliases or recognized forwarding wrappers and specialize shared helper keys
by that identity. Direct calls could then replace indirect calls, while
unknown callbacks retain their existing path. Known identity does not imply
purity: effects, captures and invocation order must remain intact. Removing
comparison-body and `Order` overhead would require further body specialization
or inlining, with code-size limits; changing dispatch alone cannot promise the
entire scalar speedup.
