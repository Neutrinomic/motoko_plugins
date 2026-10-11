# Persistent ordered-map plugin research

Research date: 2026-10-11. Compiler inspected read-only at
`be7aa9f9b51b1737221d335465b7acc9a8dce423`; plugin ABI is **1**.
API reference: `/srv/shared/code/sr9/sr9scol/core/src/pure/BMap.sr9`
at checkout HEAD `aed5b84fdf3e9db1334399bfa2110f90fc8d473a`.
Benchmark baseline: the existing pinned `core@2.5.0`, specifically
`src/pure/Map.mo`, not the mutable `src/Map.mo`.
No compiler changes, compiler rebuild, plugin implementation, or performance
measurements were performed for this report. All byte counts below are layout
estimates from the inspected compiler, not measured allocation results.

## Recommendation

Build an ordered map over **ordinary managed Motoko nodes**, starting with a
compact, join-based persistent AVL tree with subtree counts. Updates reuse
untouched children and payloads and allocate only the changed search path and
the constant-sized neighborhoods needed by rotations. Use an optional tuple
for a node to avoid an extra variant allocation. This offers a tractable
correctness argument, deterministic logarithmic operations, rank/range support,
and a strong baseline for tuning.

Benchmark a size-balanced binary tree and small blocked leaves before freezing
the public stable representation. A size-balanced node saves one word; blocked
leaves substantially reduce the live footprint of a large map. Neither
automatically minimizes bytes allocated by a single update. Do not adopt the
reference BMap's degree 32 merely because it has a short height.

The current heap SDK can implement structural sharing. The current **typing
and callback interfaces cannot provide an ordinary, fully generic BMap-style
API**. Discuss and implement the small typing improvements described below
before building the full public library. Prefer a hybrid comparator design:
ordinary Motoko performs custom callbacks; a callback-free plugin performs
path reconstruction and balancing. Static key orderings can also have a fully
generated search/update fast path. This keeps raw-pointer borrowing entirely
inside synchronous intervals without introducing callback rooting machinery.

The achievable improvement is a hypothesis: fewer allocations and indirections,
less closure machinery, tighter scalar comparisons, and better bulk algorithms.
The core baseline already uses path copying. This is a constant-factor and
API/algorithm improvement over a persistent tree, not elimination of a hidden
whole-map clone in the baseline. There is no measured speedup to report.

## What the two reference APIs actually provide

[`core@2.5.0` pure Map](https://github.com/caffeinelabs/motoko-core/blob/v2.5.0/src/pure/Map.mo)
is a red-black tree: the map has `size` and `root`, and each nonempty tree is a
`#red`/`#black` variant containing a four-field tuple. Its functions include
lookup, updates with old values or insertion/deletion flags, ordered iterators,
min/max, transformations, folds, predicates, comparison, and formatting.
It accepts a user comparator. Its iterator creates temporary traversal objects;
its filter rebuilds the accepted entries by insertion. The local pinned
[source](../_build/codec-comparison/deps/.mops/core@2.5.0/src/pure/Map.mo)
and [types](../_build/codec-comparison/deps/.mops/core@2.5.0/src/Types.mo)
are the implementation evidence used here.

The supplied
[BMap](</srv/shared/code/sr9/sr9scol/core/src/pure/BMap.sr9>)
is a B+ style tree: payload values live in leaves, and internal nodes contain
separator keys and children. Its minimum degree is 32, with at most 63 keys and
64 children. It already reuses leaf key arrays when changing only a value, and
reuses internal key arrays when changing a child does not change its minimum
key. See
[BMapInternal](</srv/shared/code/sr9/sr9scol/core/src/pure/BMapInternal.sr9>).
Its breadth additionally includes bounded/reverse traversal, replayable entry
snapshots, sorted building, arrays/sequences, and validation/debugging helpers.

Two reference behaviors should not be copied blindly:

- BMap currently materializes selected range entries into a sequence to make
  a receipt replayable without calling the comparator again. A new map can
  capture the root and rank bounds instead, avoiding an implicit O(k) copy.
- The pinned core `Internal.fromIter` increments `size` per input entry even
  when an equal key replaces an earlier value. Benchmarks must use distinct
  keys for that constructor or build the oracle by repeated `add`; duplicate
  semantics need an independent oracle. This observation is out of scope for
  an upstream fix here.

The Sr9 `Spec` module, ghost functions, and lemmas are verification-language
facilities, not Motoko plugin runtime APIs to reproduce literally.

## Algorithm and representation choices

| Candidate | Structural sharing and update cost | Strength | Limitation / decision |
|---|---|---|---|
| Compact AVL + subtree size | O(log n) new nodes; two unchanged children/payload references reused wherever possible | Tight deterministic height; straightforward invariant; good lookup, rank, split and join | One height word beyond a size-balanced node. Recommended first candidate. |
| Size-balanced / weight-balanced binary tree | O(log n) new nodes; size is both balance metadata and rank metadata | Smallest straightforward ordered binary node; mature join and bulk operations | Deletion and join inequalities require care. Benchmark against AVL; do not mix different papers' weight definitions or rotation rules. |
| Compact red-black tree | O(log n) path and rotation/recoloring nodes | Familiar baseline; worst-case bounds | Color changes can allocate nodes without changing bindings. Merely translating the existing variant/tuple layout leaves substantial allocation overhead. |
| Persistent B+ tree, small fanout such as 8/16 | O(log_B n) nodes but O(B log_B n) reference slots copied in the general case | Lower live bytes per entry; fewer node visits; good scans | Array headers, zero initialization, write barriers and splits matter. Try several occupancies; no universal winning B. |
| Binary tree with small packed leaves | O(log(n/B)) internal nodes plus O(B) leaf slots on update | Middle ground between small changed paths and compact live storage | More cases for split/join/leaf growth. A good second representation experiment. |
| CHAMP/HAMT | Short hash path; copies compact bitmap nodes, not the map | Strong unordered-map candidate | Does not provide key order, predecessor/successor, ordered ranges or rank without another index. Not the BMap replacement. |
| Patricia/radix tree | Copies affected radix path | Interesting specialization for fixed-width integer or byte keys | Different ordering and key encoding work; not a universal comparator map. |
| Treap | Expected O(log n) copied path | Simple join/split | Random priorities or deterministic hashed priorities add policy and adversarial-shape questions. Prefer deterministic worst-case bounds first. |

The join framework supports ordered union, intersection, difference, insert,
delete and split across multiple balancing schemes; its comparison-work target
for two sets of sizes m <= n is O(m log(n/m + 1)). Reuse it **sequentially**;
the IC execution model does not obtain the papers' multicore speedups.
[Blelloch, Ferizovic and Sun, 2016](https://www.cs.cmu.edu/~blelloch/papers/BFS16.pdf)
and their expanded
[2022 treatment](https://www.cs.cmu.edu/~guyb/papers/3512769.pdf).

For the size-balanced competitor, use a pinned, mature implementation and its
small-tree cases rather than the early Adams rules alone. The maintained
[Haskell containers v0.8 implementation](https://raw.githubusercontent.com/haskell/containers/v0.8/containers/src/Data/Map/Internal.hs)
uses delta 3 and ratio 2 and documents errors in older parameter choices.
The authors' [weight-balance verification materials](https://www.mew.org/~kazu/proj/weight-balanced-tree/)
explain why the exact algorithm and weight definition matter.

[PaC-trees](https://arxiv.org/abs/2204.06077) motivate blocked leaves and
compression as a later live-space optimization. Compressing generic Motoko
references into a Blob is not valid: only pointer-free scalar keys/metadata
can be encoded there; references need managed fields. The recent
[joinable B-tree preprint](https://arxiv.org/abs/2510.20053) concerns I/O bounds;
those bounds do not predict Wasm instruction counts or GC allocation.
[CHAMP](https://ir.cwi.nl/pub/24029/) is relevant to a separate unordered map;
its JVM ratios should not be projected onto Motoko.

### Concrete initial node design

Illustrative representation, not implemented source:

```motoko
type Map<K, V> = ?Node<K, V>;
type Node<K, V> = (
  Map<K, V>, // left
  K,
  V,
  Map<K, V>, // right
  Nat64,     // subtree entry count
  Nat8      // subtree height
);
```

`null` is empty. A nonempty optional tuple needs no option box in this RTS.
All six fields are vanilla Motoko values. A child, key, value, or count object
is retained by reference, never recursively copied. Use `Tuple.load_n` rather
than generic record-field hash lookup in hot traversal. `Nat64` count is easy
to unbox with the existing SDK; expose a natural `Nat` size in the library.
Validate arithmetic overflow. Do not encode private metadata by inventing
tagged values or relying on undocumented scalar tag bits.

Invariants: keys strictly ordered by the map's agreed ordering; node size is
`1 + size(left) + size(right)`; node height is
`1 + max(height(left), height(right))`; child heights differ by at most one.
An empty subtree has size/height zero. A valid AVL tree with at most
`Nat64.maximumValue` nodes fits comfortably in a path of 128 bits and a
`Nat8` height. The bound is an implementation invariant, not permission to
trust arbitrary user-supplied metadata.

The core layout costs approximately 88 bytes per nonempty node (32-byte
variant plus 56-byte four-tuple). This six-tuple costs 72 bytes; the
size-balanced five-tuple would cost 64. The estimates exclude payload objects,
temporary return tuples, instrumentation, and any boxed metadata. The core
map wrapper additionally costs approximately 40 bytes. These figures follow
the current tuple/variant layouts in
[`compile.ml`](../../motoko_sha/src/codegen/compile.ml), especially `Variant`,
`Tuple`, `Arr`, `Opt`, and `BoxedWord64`; they are not a stable public ABI.

For a no-rotation replacement on a path with h nodes, the initial target is
about `72*h` new node bytes, plus the chosen public return value and any
argument packaging. A million-entry AVL map has paths on the order of a few
dozen nodes, not a million. Rotations add/rearrange a bounded number of nodes
per affected level. Construct the final rotated nodes directly, avoiding a
temporary parent that is immediately discarded. Insertion/deletion allocate
O(log n) nodes overall, not necessarily exactly one per path level.

For B+ replacement, sharing the key arrays still leaves a leaf values array
and ancestor children arrays to copy. One fully populated 64-child array alone
is 536 bytes before its enclosing node and other metadata. Lower height can
outweigh that cost, but does not prove it. Existing `Arr.tabulate` additionally
initializes slots and uses normal write barriers. Measure actual bytes and
instructions, not just the number of nodes.

### Core algorithms

- `get`/membership/min/max: iterative traversal, no scratch allocation;
  optional results may need an option box when V itself is null/optional.
- `add`/`insert`/`swap`/`replace`: one search; reconstruct on return using
  managed children. Return old value and a changed/found flag as Wasm
  multivalues internally rather than heap-allocating a tuple at each level.
- `remove`/`delete`/`take`: defer allocation until a match is found. An absent
  key returns the exact existing root. A two-child deletion follows one
  predecessor/successor path and rebalances the affected ancestors.
- `join(left, entry, right)` and `join2(left, right)`: establish AVL joins
  first; all keys in the left input must precede the entry/right input.
  Expose checked joins publicly or keep the unchecked kernel internal.
- `split`, `splitLookup`, range maps and range deletion: rebuild boundary
  paths; reuse complete interior subtrees. No flatten/reinsert step.
- `union`, `intersection`, `difference`: divide using split/join; preserve
  left/right conflict semantics independently of which tree is smaller.
  Empty inputs are immediate sharing cases. Identity shortcuts must respect
  whether callbacks are required to run.
- `rank`, `select`, count in range and split by rank: navigate stored subtree
  sizes. Do not enumerate the selected range just to count it.
- `fromSortedDistinctArray`: build a balanced tree bottom-up in O(n), allocating
  final nodes once. Validate sorted/distinct preconditions in the checked API.
- `fromArray`: explicit bulk construction may sort indices and build once.
  Scratch holds indices, not a serialized copy of all key/value payloads.
  Preserve a documented duplicate winner, for example last input wins.
- `applySortedBatch`: after the basics are correct, process changes through
  shared split/join subproblems rather than allocating a complete persistent
  path for every sequential update.

Native Wasm helper generation (`Func.share_code`, including multivalue results)
is sufficient for recursion and balancing. Most tree logic need not live in
Rust. A Rust kernel can compare borrowed Blob bytes, but should not duplicate
Motoko heap layouts or own a persistent `Vec`/map of Motoko addresses.

## Exact existing-SDK feasibility

These conclusions come from
[`plugin_codegen.mli`](../../motoko_sha/src/codegen/plugin_codegen.mli),
[`compute_plugin.ml`](../../motoko_sha/src/mo_values/compute_plugin.ml),
[`typing.ml`](../../motoko_sha/src/mo_frontend/typing.ml), and the
`ComputePlugins` adapter in
[`compile.ml`](../../motoko_sha/src/codegen/compile.ml).

| Capability | Existing ABI 1 status | Consequence |
|---|---|---|
| Reuse a child/key/value in a fresh managed node | Supported | Constructors take vanilla values; path copying needs no new heap object category. |
| Return an untouched subtree/root | Supported | O(1) clone and sharing fast paths are possible. |
| Recursive concrete map types | Supported by the core concreteness walk | Plugin schema checking still must terminate on recursive definitions and validate its own shape. |
| Arbitrary concrete shared V carried opaquely | Supported via `Shared` | Do not visit V's internals; schema complexity need not become runtime work. |
| Ordinary generic `func add<K,V>(...)` calling an intrinsic | Rejected today | `specialize` rejects abstract type arguments and argument types; it also requires a concrete result. Inferred aliases retain intrinsic specialization, but are not normal first-class generic function values. |
| User comparator / update callback inside the generator | Not supported | No closure construction/application API, rooted callback transition, or safepoint contract. `Backend.call` invokes named plugin imports only. |
| Callback in interpreter reference | Not supported by this binding interface | `evaluate` is synchronous and has no interpreter context/apply service. `Value.Func` uses an execution context and continuations. |
| Closure iterator returned directly by a plugin | No constructor for it | Use an ordinary Motoko iterator over managed representation or a data-only cursor. |
| Persistent Rust-owned map / raw-address table | Invalid under this contract | GC cannot trace references in pointer-free scratch Blobs; addresses cannot survive a call/GC/upgrade. |
| Mutating previously returned nodes as a transient optimization | Not supported/safe | No uniqueness/ownership proof; old versions must remain valid. |

### Argument typing is a separate issue from accepting opaque V

`Shared` infers the actual argument types, but disallows non-shared values such
as local comparator functions and maps containing local closures or mutable
payloads. A pure container may reasonably carry such payloads by reference;
that would be shallow persistence, as with other generic Motoko containers.

`Fixed [Any; Any; ...]` is **not** a sound shortcut. `infer_call` checks the
argument tuple against the expected fixed tuple, and `check_exp`'s tuple case
records that expected tuple. The result-type callback therefore receives
`Any` components, not enough evidence to verify that a key and value match the
map's K and V. Explicit type arguments cannot make an unchecked Any cast safe.

A unary `Fixed [Any]` argument can preserve an inferred record shape in the
post-inference check, but the preliminary typing pass still supplies the
fixed expected `Any` to `result_type`. This is not established as a robust
solution and is not recommended as the public API. A new typing contract should
handle both passes explicitly instead of accepting unvalidated placeholders.

A limited current-SDK package can use `Shared`, concrete call sites, static
key order and intrinsic aliases such as `public let add = Prim.pmapAdd`.
Generic Motoko traversal helpers can read the published representation without
calling an intrinsic. This is useful for a narrow prototype, not equivalent to
the requested fully generic comparator API.

### Key comparison matrix

| Key family | Existing direct path | Proposed treatment |
|---|---|---|
| Nat8/16/32, Int8/16/32, Char | SDK tagged-small-word adjustment | Straightforward supported static order. |
| Nat64, Int64 | SDK boxed-word unbox handles scalar and boxed forms | Strong first benchmark family, including values outside the inline range. |
| Bool | SDK Boolean bridge | Simple total order; specify false before true. |
| Blob | Borrow length/payload via SDK; compare bytes | Allocation-free lexicographic kernel is feasible; no payload copy. |
| Principal | Blob-like managed representation and byte payload access | Verify ordering against `Principal.compare`; do not compare textual encodings. |
| Nat, Int | LEB bridge exists; direct numeric comparator is not exposed | Add compiler-owned comparison. Re-encoding visited keys as Blobs would add avoidable garbage. |
| Text | `to_blob` reuses flat text but flattens/copies a concatenation rope | Expose the existing rope-aware compiler comparison; never advertise the current flattening fallback as free. |
| Float / Float32 | Unbox and Wasm comparison available | NaN needs an explicit total-order policy. Defer default support rather than treating every unordered comparison as equality. |
| Tuples / immutable records of supported keys | Field/tuple reads and recursive comparison generation | Optional later lexicographic schema, with documented field ordering. Reject mutable/order-unstable keys. |
| Arbitrary custom K | Needs user-supplied ordering | Hybrid Motoko search or a separately designed rooted callback interface. |

`Text.to_blob`'s allocation behavior is explicit in
[`rts/text.rs`](../../motoko_sha/rts/motoko-rts/src/text.rs), `blob_of_text`.
The existing compiler has `Text.compare` and `BigNum.compile_relop`, but neither
is exposed in the plugin Backend. Simply exposing `BigNum.compile_relop` avoids
the LEB roundtrip; it is not a universal zero-allocation promise. Its mixed
tagged/boxed path boxes the scalar operand before the libtommath operation.
Budget and test that behavior. A strictly allocation-free mixed comparison
would need additional backend/RTS work.

## SDK choices to discuss before implementation

| Option | Benefit | Cost / boundary | Recommendation |
|---|---|---|---|
| A. Current SDK; concrete shared types and static keys | Fastest narrow prototype; sharing already works | Restricted generics, payloads and ordering; Nat/Text costs need attention | Useful feasibility baseline only. |
| B. Compiler-owned scalar comparison helpers | Natural Nat/Int/Text keys without serialization workarounds | Small API surface, reuse existing semantics; mixed bigint allocation still needs measurement | High-value addition. No raw RTS import escape hatch needed. |
| C. Fixed argument schemas that depend on type arguments, plus explicit opaque type parameters | Normal typed generic wrappers; arbitrary K/V can be retained as vanilla values | Must update preliminary/final checking, result checking, IR validation and interpreter validation consistently | Preferred typing improvement. Keep Shared/Fixed as the two policies and ABI 1; no legacy entrypoints. |
| D. C plus ordinary Motoko comparator search and callback-free plugin reconstruction | Full custom comparator and alter API without borrowing across callbacks | One generated rewalk of the recorded path; scalar path descriptor overhead | Preferred first full-API design. |
| E. Compiler-generated ordinary Motoko/IR orchestration around no-GC kernels | Potentially avoid the rewalk and expose normal callbacks safely | Larger typed IR/call-generation interface; effects and rooting require design | Evaluate if D's measured overhead is significant. |
| F. General plugin-to-Motoko closure calls | Arbitrary comparators/resolvers/folds entirely in generated operations | Requires rooted handles, reloading after GC, effect semantics, callback apply in both interpreters, and reentrancy rules | Separate substantial SDK project. Do not just expose closure offsets/call_indirect. |

For C, distinguish **opaque** type parameters, whose values are moved but never
inspected, from parameters needed to choose a runtime layout/operation. A static
key comparator still requires a known supported K; an opaque V does not.
A callback-driven search can treat K as opaque too. This is more precise than
removing the concrete-type check for every plugin. Existing JSON/Candid schema
walkers must continue to reject unsupported abstract shapes.

One possible uniform API evolution is for Fixed's input schema to be computed
from the explicit type arguments, so it can state `Map<K,V>`, K and V rather
than Any. The binding also declares where abstract parameters are permitted.
The frontend uses the schema for contextual typing and supplies checked
metadata without losing the generic relationships. The plugin result checker
must be parametric; the compiler must not trust an arbitrary reinterpretation
of K/V. Exact field names and representation should be decided in the SDK
discussion; this report does not prescribe an unreviewed signature patch.

### Hybrid custom-comparator update

1. An ordinary generic Motoko helper walks the immutable tree with the user's
   comparator. Its references are managed Motoko locals during callback calls.
2. Record only left/right decisions and depth, for example two Nat64 words
   plus a small depth, and the found/missing status. Keep the root itself as a
   normal managed argument. Do not record raw addresses in the descriptor.
3. If this is `alter`, invoke `(?V -> ?V)` exactly once in Motoko. `get` can
   simply return the found value; no plugin is needed for the read-only custom
   comparator path.
4. Invoke a typed no-callback intrinsic with the original root, validated path
   descriptor, key and update decision. It rewalks the path, rebuilds/balances,
   and returns a normal managed root.

This avoids one managed path-list allocation per level. Nat64 route words may
themselves box; include that in allocation measurements. The descriptor is tied
to that immutable root and does not become a globally valid cursor/handle.
Validate depth/path coherence before unsafe indexing or recursion. The bounded
path assumes the proposed AVL invariants; another balancing scheme needs its
own proven bound.

This design does not remove user comparator dispatch cost. It moves balancing
and reconstruction into the plugin while keeping generic callbacks safe. The
fully generated static-order operation can remain a distinct fast entrypoint.
Inlining/recognizing arbitrary comparator functions is a further compiler
optimization, not something current type specialization already provides.

## Public API and allocation matrix

Costs assume constant-cost comparison; long text/blob/bigint comparisons add
their own work. H means an ordinary Motoko helper is appropriate; P means a
callback-free plugin kernel is appropriate. Generic H-to-P calls need option C
above; P is otherwise limited to current concrete call sites.

| Family / operations | Target work and newly allocated tree nodes | Placement / semantics |
|---|---|---|
| `empty`, `singleton`, `size`, `isEmpty`, `clone` | O(1); clone returns same root, singleton one node | H or P; no deep clone API masquerading as clone. |
| `get`, `containsKey`, `getEntry` | O(log n); zero new tree nodes | P static order; H custom compare. `getEntry` includes the stored key. |
| `add`, `insert`, `swap`, `replace` | O(log n); O(log n) nodes | P / hybrid. Preserve reference semantics: insert means add/replace plus was-new; replace does not insert missing keys. |
| `remove`, `delete`, `take` | O(log n); O(log n) nodes when present | Absent removal returns the original root; flags/old values distinguish variants. |
| `alter`, `update`, `insertWith` | O(log n) plus callback cost | H callback plus P reconstruction. Specify callback count, order and absent-key behavior. |
| `minEntry`, `maxEntry`, `popMin`, `popMax` | O(log n); pop copies one boundary path | No comparator needed. |
| `lower`, `floor`, `ceiling`, `higher` | O(log n); zero new tree nodes | Explicit strict/inclusive neighbor semantics. |
| `rank`, `indexOf`, `select`, `splitAt`, `takeRank`, `dropRank` | O(log n); path copies only for tree outputs | Subtree counts justify these features. Distinguish absent index from insertion rank. |
| `entries`, `reverseEntries`, `keys`, `values` | O(log n) cursor initialization; O(n) full traversal | H managed iterator. A mutable private stack avoids a persistent list allocation for every visited node. |
| `entriesFrom`, reverse forms, bounded ranges | O(log n + k) traversal, O(log n) cursor space | Capture root and rank endpoints. No implicit selected-entry array/sequence. |
| `snapshot`, replay cursor | O(1) root/rank descriptor; O(log n) cursor initialization | Data-only snapshot may be stable when K/V are stable; closure iterator is transient. |
| `split`, `splitLookup`, `join`, `concatDisjoint`, `rangeMap`, `removeRange` | O(log n) boundary work/new nodes | P static or hybrid boundaries. Check disjoint/order preconditions publicly. |
| `union`, `intersection`, `difference`, symmetric difference | Target O(m log(n/m + 1)) for m <= n | P for fixed conflict policy; H/IR orchestration for user resolvers. Reuse whole unaffected subtrees. |
| `unionWith`, general merge | Above plus callbacks/output changes | Specify left/right order and callback obligations. Do not skip required callbacks through identity shortcuts. |
| `map`, `filterMap`, `mapKeys` | O(n) or more when reordering keys | H callback. A transform changing every V necessarily creates a new map; no logarithmic-allocation promise. |
| `filter`, `partition` | O(n) predicate work; share fully unchanged subtrees | H recursive traversal and join/rebuild; all-accepted filter should retain the old root. |
| `foldLeft`, `foldRight`, `foldValues`, `forEach`, `all`, `any`, `find` | O(n), short-circuit where specified | H direct traversal can avoid entry tuples entirely. User code may dominate cost. |
| `equal`, lexicographic `compare`, submap/disjoint checks | Size/identity fast cases; otherwise traversal | Arbitrary V equality/order is a callback, not pointer equality. |
| `fromIter`, `fromArray`, `fromSortedDistinctArray`, `addList`, batches | Explicit O(n) construction / bounded bulk update work | `fromIter` consumes callbacks in H; sorted bulk builder is P. Document duplicate policy. |
| `thaw`/builder append/`freeze` | Mutable build storage plus final O(n) tree | Ordinary managed builder. No persistent Rust pointer state; freezing must isolate future builder mutations. |
| `toArray`, `toText`, sequence conversion | O(n) output is intentional | H formatting callbacks; P array extraction possible. Explicit materialization is different from implicit copying on update. |
| `assertValid`, `treeDepth`, `nodeCount`, debug rendering | O(n) validation/debug | Test/debug API. Do not validate the whole tree inside each ordinary lookup/update. |

The immutable guarantee applies to the map structure. If V contains a mutable
object, two versions still reference that same payload object. For a deeply
immutable map require an immutable payload contract; do not silently deep-copy
V. Keys must retain their ordering while stored, and an existing map must not
be reused with an inconsistent comparator. Comparator equality may equate
different key representations, so specify whether replacing a binding replaces
the stored key. The core add path replaces it with the newly supplied key.

## GC, ownership and persistence

The inspected
[allocation/write barriers](../../motoko_sha/rts/motoko-rts/src/gc/incremental/barriers.rs)
support this design. Newly allocated nodes must be completely initialized
before the allocation barrier. That barrier marks new objects during relevant
GC phases and resolves outgoing references during pointer updating.
Tuple/variant/object constructors apply it; array construction initializes
every slot before invoking element generation and uses the normal write
barrier. Existing loads follow forwarding pointers. An unchanged child can
therefore be inserted into a new node without cloning it.

Implementation requirements:

- All long-lived edges live in compiler-constructed pointer-bearing objects.
  A Blob of node addresses is not a managed persistent tree.
- No GC safepoint, Motoko callback, suspension, or retained pointer occurs
  during a borrowing interval. GC being in an incremental phase does not
  remove this requirement. Memory growth itself preserves Wasm addresses.
- No update mutates an input node, including an apparently unshared root.
  The SDK has no uniqueness proof. Reference-count tricks from C++ libraries
  are not transferable to this traced heap.
- Never hand-copy a node header or mutate a fresh managed field after its
  allocation barrier without the proper write barrier. Use the SDK builders.
- Keep per-update temporary state in Wasm locals/call frames when possible.
  Rust scratch uses pointer-free Motoko Blobs and deallocation is a no-op;
  it still contributes to cumulative allocation until a later GC.
- Avoid raw-address equality as a semantic equality operation. Forwarding can
  give two references to the same object different addresses. Use an explicit
  changed flag for no-op updates. A compiler-provided forwarding-aware identity
  helper could later improve safe shortcut hit rates.
- Treat the exposed structural type as forgeable. Debug validation checks the
  full invariant; production operations must still bound traversal and reject
  malformed counts/paths before unsafe accesses. Full O(n) validation on every
  call would defeat the API's complexity claims.

Retaining q versions keeps the union of their reachable nodes alive. One
snapshot costs only a root reference, but q independent edits can retain
O(q log n) additional nodes, and arbitrary new payloads add their own size.
Dropping old roots permits reclamation; it does not necessarily shrink Wasm
linear memory. Iterators/snapshots also retain roots, so a long-lived cursor
can intentionally retain an older map.

Ordinary stable Motoko nodes participate in
[enhanced orthogonal persistence](../../motoko_sha/design/OrthogonalPersistence.md)
without a plugin-owned stable-memory index. K/V must themselves be stable for
the map to be stored in a persistent field. Local closures are useful transient
payloads but not stable payloads. Keep comparators and closure iterators outside
stable map data. Do not change the node shape or comparison ordering in a later
upgrade and assume compatibility: representation changes need a migration,
and changing key order can require rebuilding even when types are compatible.
The representation deserves an explicit version decision before deployment.

## Benchmark and stress-test plan

Keep all generated actors, binaries, reports and probes in this repository.
Use the selected existing compiler host; any plugin build must pass
`--skip-motoko-build`. This report authorizes no compiler rebuild or SDK patch.
Use the existing
[benchmark machinery](../benchmarks/README.md),
[plugin tests](../tests/README.md), and
[forced-GC fixture](../tests/integration/run-drun/compute-plugins-gc.mo)
as patterns. Do not mutate existing benchmark artifacts or expectations by hand.

1. **Agree the API/SDK boundary.** Decide static and custom ordering, opaque
   type parameters, duplicate/key-replacement semantics, and stable node shape.
   If the required SDK support is missing, stop dependent implementation until
   that change is discussed and available. Keep ABI 1 and no legacy entrypoints.
2. **Executable reference and kernel correctness.** Differentially compare
   point operations to core and an independent sorted-array oracle. Verify all
   invariants after randomized histories and preserve selected earlier roots.
   Exercise empty/singleton trees, all AVL rotations, deletion cascades,
   alternating extremes, repeated absent removals, equal-key replacement,
   null/nested-option V, huge shared payloads, and many concrete K/V schemas.
   Run the source interpreter, IR interpreters and Wasm with matching results.
3. **Point-operation matrix.** Sizes 0, 1, 16, 256, 4K, 64K and larger sizes
   within the environment's budget; sorted/reverse/random/adversarial insertion
   order; uniform and skewed reads; hit/miss; insert-new, overwrite, replace-miss,
   delete-hit and delete-miss. Compare equal key/value types and semantics in
   the same actor/compiler. Separate static-order from custom-comparator paths.
4. **Key and payload matrix.** Small/full-range Nat64 and Int64, small/large
   Nat/Int, flat/rope Text with long common prefixes and Unicode, Blob and
   Principal, and small versus large payload objects. Prebuild keys/payloads
   outside the measured operation. An update of a node holding a 1 MiB Blob
   must not allocate another MiB merely to retain that unchanged Blob.
5. **Prove incremental allocation.** Record `rts_total_allocation` deltas and
   instruction counts separately from input setup, validation and result
   serialization. Fit update allocation against measured path height as n
   grows. Zero-change operations should allocate no new tree nodes; public
   argument/result packaging may still allocate. Compare retained versions
   against allocation in a latest-version-only run. Avoid per-level return
   tuples and hidden Rust vector growth.
6. **Prove sharing, not merely equal output.** Check that a one-key edit shares
   untouched subtrees and that input nodes never change. Allocation bounds,
   retained-version checks and inspection of constructor inputs work now.
   For direct shared/unique-node counts through forwarding, add a reviewed
   compiler-provided identity helper; the current SDK does not expose one.
   Tuple loads follow forwarding to read fields, but do not return a canonical
   identity for the tuple itself. Raw pointer comparison can undercount sharing
   during pointer updating and must not be presented as exact. A diagnostic
   should return counts, never raw addresses as stable identities, and stay
   outside production measurements. Allocation limits alone do not prove
   old-version correctness.
7. **Retention across collection and upgrade.** Retain a branching history of
   roots with shared keys, values, child nodes and partially advanced cursors.
   Churn multiple GC partitions and use actual ingress calls plus repeated
   forced-GC boundaries. Update after each collection phase and read every
   retained version. Drop most roots, force collection and check substantial
   reclamation; do not assert Wasm memory must shrink. Perform an unchanged-
   representation canister upgrade and verify the retained snapshots again.
   Include an upgrade during an unfinished incremental collection if supported
   by the harness. Recheck sharing after forwarding, not just before it.
8. **Bulk and API costs.** Vary union/intersection ratios and overlap, narrow
   and broad ranges, sorted and unsorted construction, batch sizes, all/none/
   sparse filters, and cursor initialization versus full scans. Explicit
   output arrays, callback work and node construction are separate columns.
   Compare AVL, size-balanced and blocked-leaf designs under the same workload.
9. **Audit and optimize.** Once the design/implementation exists, independent
   algorithm auditors and runtime/GC auditors review it; independent performance
   agents investigate only measured costs. Re-run changed workloads and the
   relevant regressions. A faster kernel is not acceptable if it weakens
   persistence, type safety or input validation.

Record raw trials, compiler/plugin/core revisions, artifact hashes, key order,
seed, retained-version count, instructions, cumulative allocation, reclaimed
bytes and live-heap estimates after collection. Include both synchronous
operation costs and a separate end-to-end GC-inclusive workload. Comparison
ratios from codecs or hashing do not predict a map's performance. The core
baseline is already logarithmic, and custom callbacks or expensive key
comparison may dominate the remaining cost.

## Decision ready for discussion

The heap ownership model needs no new map object or external allocator.
The useful first SDK work is accurate type-dependent Fixed inputs, explicit
opaque parameters, and scalar comparison helpers. With those agreed, the
hybrid comparator design can cover a broad generic API while retaining the
current no-callback borrowing rule. Fully general callbacks inside a plugin
are an optional larger investment, not a prerequisite for a complete library.
Choose the final node layout from measured instruction/live-space/update-byte
tradeoffs before declaring a stable persistent representation.
