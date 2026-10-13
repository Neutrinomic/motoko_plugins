# Indexed priority queue

A mutable minimum-priority queue with native heap operations and handles for
constant-time entry lookup and logarithmic cancellation or rescheduling.
Priorities and values are ordinary Motoko values; neither is serialized or
copied as an object graph. The plugin uses the existing managed compiler SDK
and has no separate runtime Wasm or persistent foreign memory.

```motoko
import PriorityQueue "mo:fast/IndexedPriorityQueue";
import Nat "mo:core/Nat";

let jobs = PriorityQueue.empty<Nat, Text>();
let job = PriorityQueue.push(jobs, Nat.compare, 100, "retry");
ignore PriorityQueue.reschedule(job, Nat.compare, 25);
assert PriorityQueue.peek(jobs) == ?(25, "retry");
ignore PriorityQueue.remove(job, Nat.compare);
assert PriorityQueue.get(job) == null;
```

Load `dist/indexed-priority-queue` using the compiler's `--plugin` option and
resolve the `fast` package to `packages/fast/src` (or use the installed bundle).

## API

| Operation | Result | Cost |
| --- | --- | --- |
| `empty<K,V>()` | `Queue<K,V>` | O(1) |
| `size(queue)`, `isEmpty(queue)` | `Nat`, `Bool` | O(1) |
| `push(queue, compare, priority, value)` | `Handle<K,V>` | Amortized O(log n) |
| `peek(queue)` | `?(K,V)` | O(1) |
| `peekPriority(queue)` | `?K` without a priority/value pair | O(1) |
| `pop(queue, compare)` | Removed `?(K,V)` | Amortized O(log n) |
| `get(handle)` | Current `?(K,V)` | O(1) |
| `remove(handle, compare)` | Removed `?(K,V)` | Amortized O(log n) |
| `reschedule(handle, compare, priority)` | Whether handle was active | O(log n) |
| `replace(handle, compare, priority, value)` | Previous `?(K,V)` | O(log n) |
| `entries(queue)` | Iterator in heap order | O(n) traversal |
| `clear(queue)` | `()` | O(n) |

`peekPriority` is useful when checking whether a deadline is due without
reading its payload. Empty queues return `null`; a present nullable priority
keeps its option layer (`?null` for a stored `null`). It avoids constructing
a priority/value pair, although nullable priorities may need an option box.

The comparator parameter is implicit, like `mo:fast/Map`. Compiler-proven scalar
comparators use native scalar comparison; ordinary callbacks remain supported.
Use the same lawful ordering throughout a queue's lifetime, and do not mutate
stored priorities so that their ordering changes. Equal priorities have
unspecified order. Include an explicit ticket in a composite priority when
exact deterministic tie ordering matters.

Handles direct their operations to the owning queue, so a handle cannot target
a different queue. An active handle retains that queue. `remove`, `pop`, and
`clear` immediately detach affected handles; detached handles retain neither
the queue nor its payloads, and all later lookups/removals/replacements return
`null` (`reschedule` returns `false`). `clear` visits active handles to invalidate
them before releasing the backing array. No numeric generation counter or raw
heap address is exposed or needed.

## Storage and callbacks

The heap is a lazily grown mutable array of managed entry references. Array
growth and shrink copy references, not payloads. Entries, handles, and their
owner references form ordinary managed Motoko objects and are stable when the
priority and value types are stable. Removed slots are cleared. Treat every
public representation field as private, as with the fast Map and Set modules.

Comparators may read the queue's evolving state, mutate payloads without
changing their ordering, and mutate other containers. They must not insert,
remove, reschedule, replace, or clear entries in this queue. Sifting keeps slot
and handle indices consistent between callbacks, but a comparator must not
assume the whole heap operation is atomic. Queue mutation invalidates existing
iterators. There is no runtime lock or fail-fast iterator check.

Core's PriorityQueue is already a binary heap. The extra capability here is
indexed cancellation/rescheduling plus generated native operations, not a new
asymptotic improvement for ordinary push/pop. Handles add storage overhead;
choose integrations from measured workload results rather than assuming every
heap workload becomes faster.
