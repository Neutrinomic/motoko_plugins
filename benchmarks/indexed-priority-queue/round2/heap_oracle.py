#!/usr/bin/env python3
"""Independent scalar Pop model: ordinary sift versus Floyd's hole algorithm.

Run with Python 3 (stdlib only). Entries carry unique IDs, not just keys; all
heap positions and live/detached handle states must match after every operation.
This models observable heap behavior, not Wasm instructions or GC barriers.
"""

import argparse
import hashlib
import json
import random
from pathlib import Path


class Heap:
    def __init__(self, entries=(), floyd=False):
        self.entries = list(entries)
        self.handles = {entry[1]: [True, i] for i, entry in enumerate(entries)}
        self.floyd = floyd
        self.next_id = len(entries)

    def put(self, pos, entry):
        self.entries[pos] = entry
        self.handles[entry[1]][1] = pos

    def child(self, pos):
        child = 2 * pos + 1
        if child >= len(self.entries):
            return None
        if child + 1 < len(self.entries) and self.entries[child + 1][0] < self.entries[child][0]:
            child += 1
        return child

    def up(self, start):
        pos = start
        moving = self.entries[pos]
        while pos:
            parent = (pos - 1) // 2
            if not moving[0] < self.entries[parent][0]:
                break
            self.put(pos, self.entries[parent])
            pos = parent
        if pos != start:
            self.put(pos, moving)

    def down(self, start):
        pos = start
        moving = self.entries[pos]
        while (child := self.child(pos)) is not None:
            if not self.entries[child][0] < moving[0]:
                break
            self.put(pos, self.entries[child])
            pos = child
        if pos != start:
            self.put(pos, moving)

    def floyd_down(self, start=0, strict_ascent=False):
        pos = start
        moving = self.entries[pos]
        child = self.child(pos)
        # Preserve the cheap no-movement path, including ties at the root.
        if child is None or not self.entries[child][0] < moving[0]:
            return
        while child is not None:
            self.put(pos, self.entries[child])
            pos = child
            child = self.child(pos)
        while pos > start:
            parent = (pos - 1) // 2
            parent_entry = self.entries[parent]
            restore = moving[0] < parent_entry[0] if strict_ascent else moving[0] <= parent_entry[0]
            if not restore:
                break
            self.put(pos, parent_entry)
            pos = parent
        self.put(pos, moving)

    def repair(self, pos):
        if pos and self.entries[pos][0] < self.entries[(pos - 1) // 2][0]:
            # Match the delivered repair's complete first swap.
            parent = (pos - 1) // 2
            moving, other = self.entries[pos], self.entries[parent]
            self.put(pos, other)
            self.put(parent, moving)
            self.up(parent)
        else:
            self.down(pos)

    def remove_at(self, pos, scalar_pop=False):
        old = self.entries[pos]
        self.handles[old[1]][0] = False  # Detached handles retain their old index.
        last = self.entries.pop()
        if pos < len(self.entries):
            self.put(pos, last)
            if scalar_pop and self.floyd:
                self.floyd_down()
            else:
                self.repair(pos)
        return old

    def pop(self):
        return self.remove_at(0, scalar_pop=True) if self.entries else None

    def push(self, key):
        entry = (key, self.next_id)
        self.next_id += 1
        self.handles[entry[1]] = [True, len(self.entries)]
        self.entries.append(entry)
        self.up(len(self.entries) - 1)
        return entry[1]

    def remove(self, ident):
        handle = self.handles[ident]
        return self.remove_at(handle[1]) if handle[0] else None

    def reschedule(self, ident, key):
        handle = self.handles[ident]
        if not handle[0]:
            return False
        self.put(handle[1], (key, ident))
        self.repair(handle[1])
        return True

    def clear(self):
        for _, ident in self.entries:
            self.handles[ident][0] = False
        self.entries.clear()

    def validate(self):
        assert len({ident for _, ident in self.entries}) == len(self.entries)
        for pos, (key, ident) in enumerate(self.entries):
            assert self.handles[ident] == [True, pos]
            assert not pos or self.entries[(pos - 1) // 2][0] <= key
        assert sum(handle[0] for handle in self.handles.values()) == len(self.entries)


def equal(a, b):
    a.validate()
    b.validate()
    assert a.entries == b.entries, (a.entries, b.entries)
    assert a.handles == b.handles, (a.handles, b.handles)
    assert a.next_id == b.next_id


def heaps(n, keys=3):
    """Generate each valid ordered-key heap exactly once, assigning IDs by slot."""
    entries = []

    def generate(pos):
        if pos == n:
            yield tuple(entries)
            return
        minimum = entries[(pos - 1) // 2][0] if pos else 0
        for key in range(minimum, keys):
            entries.append((key, pos))
            yield from generate(pos + 1)
            entries.pop()

    yield from generate(0)


def drain(a, b):
    count = 0
    equal(a, b)
    while a.entries:
        assert a.pop() == b.pop()
        equal(a, b)
        count += 1
    assert a.pop() is None and b.pop() is None
    return count


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--max-size", type=int, default=12)
    parser.add_argument("--seed", type=int, default=20261012)
    parser.add_argument("--random-heaps", type=int, default=400)
    parser.add_argument("--mixed-sequences", type=int, default=80)
    parser.add_argument("--mixed-steps", type=int, default=1000)
    parser.add_argument("--output", type=Path, default=Path(__file__).with_name("heap-oracle.json"))
    args = parser.parse_args()
    exhaustive = []
    for n in range(args.max_size + 1):
        count = pops = 0
        for entries in heaps(n):
            pops += drain(Heap(entries), Heap(entries, floyd=True))
            count += 1
        exhaustive.append({"size": n, "valid_heaps": count, "pops_checked": pops})
        print(json.dumps(exhaustive[-1]), flush=True)

    rng = random.Random(args.seed)
    random_pops = 0
    random_max_size = 0
    for trial in range(args.random_heaps):
        n = rng.randrange(1, 1025)
        random_max_size = max(random_max_size, n)
        a, b = Heap(), Heap(floyd=True)
        for _ in range(n):
            # Frequent ties, signed priorities, and large exact integer keys.
            key = rng.randrange(3) if trial % 3 == 0 else rng.randrange(-10**30, 10**30)
            assert a.push(key) == b.push(key)
        random_pops += drain(a, b)

    mixed = {name: 0 for name in ["push", "pop", "remove", "reschedule", "clear"]}
    for _ in range(args.mixed_sequences):
        a, b = Heap(), Heap(floyd=True)
        for _ in range(args.mixed_steps):
            op = rng.choices(list(mixed), [43, 23, 12, 21, 1])[0]
            if not a.handles and op in ("remove", "reschedule"):
                op = "push"
            mixed[op] += 1
            if op == "push":
                key = rng.randrange(-30, 31)
                assert a.push(key) == b.push(key)
            elif op == "pop":
                assert a.pop() == b.pop()
            elif op == "remove":
                ident = rng.randrange(a.next_id)
                assert a.remove(ident) == b.remove(ident)
            elif op == "reschedule":
                ident, key = rng.randrange(a.next_id), rng.randrange(-30, 31)
                assert a.reschedule(ident, key) == b.reschedule(ident, key)
            else:
                a.clear()
                b.clear()
            equal(a, b)
        drain(a, b)

    report = {
        "result": "pass",
        "scope": "Independent Python model; not native code verification or GC proof",
        "source_sha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
        "seed": args.seed,
        "algorithm": "Scalar Pop only; left child on ties; early first-child stop; descend to leaf; ascend on moving <= parent",
        "assertions": ["Exact (key, unique payload ID) heap array", "Every live handle's owner and index", "Detached handle identity and retained index", "Heap order and no duplicate IDs", "Return values including stale-handle operations"],
        "exhaustive": {"keys": [0, 1, 2], "by_size": exhaustive, "valid_heaps": sum(row["valid_heaps"] for row in exhaustive), "pops_checked": sum(row["pops_checked"] for row in exhaustive)},
        "random": {"heaps": args.random_heaps, "max_size": random_max_size, "pops_checked": random_pops, "key_distributions": ["0..2", "signed integers in [-10^30, 10^30)"]},
        "mixed": {"sequences": args.mixed_sequences, "steps_per_sequence": args.mixed_steps, "operations": mixed, "extra_final_drains": True},
        "proof": [
            "After removing the root, all descendant subheaps are unchanged and valid; replacing it by the last entry leaves only the root potentially out of order.",
            "Both algorithms follow the same path of minimum children, choosing the left child on equality. Descent writes only ancestors, so subsequent child choices see the same original descendants.",
            "Keys on that path are nondecreasing. Ordinary sift promotes exactly the strict-less-than-moving prefix and stops before the first greater-or-equal key.",
            "Floyd descent promotes the full path. Ascending on moving <= parent restores every greater-or-equal suffix entry to its exact original slot, including equal-key payload identities; its final position is therefore the same strict prefix boundary.",
            "Every promoted/restored entry has its handle index updated with its slot; placing moving fixes its handle. The same removed root is detached before either sift, with the same retained index. Array shrink follows both algorithms identically.",
            "IDs assigned by initial slot cover all distinct-payload permutations by renaming symmetry: neither algorithm compares IDs. Mixed operations preserve the equality invariant inductively because only scalar Pop differs."
        ],
        "assumptions": ["Total, consistent scalar order", "No callbacks or reentrant observation during hole movement", "Memory safety and write barriers are separately audited in native implementation"]
    }
    args.output.write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({"result": "pass", "report": str(args.output), "exhaustive_heaps": report["exhaustive"]["valid_heaps"], "random_pops": random_pops}), flush=True)


if __name__ == "__main__":
    main()
