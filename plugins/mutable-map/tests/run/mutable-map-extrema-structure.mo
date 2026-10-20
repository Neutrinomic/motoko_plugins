//MOC-FLAG --plugin ../../../../dist/mutable-map --package fast ../../../../packages/fast/src --package core $MOTOKO_CORE
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Map "mo:fast/Map";

type Node = Map.Node<Nat, Nat>;
type Tree = Map.Map<Nat, Nat>;

func tree(root : ?Node, size : Nat) : Tree {
  {var root = root; var size = size}
};

func leaf(key : Nat, value : Nat) : Node {
  let entries = Prim.Array_init<?(Nat, Nat)>(31, null);
  entries[0] := ?(key, value);
  {var count = 1; entries; children = [var]}
};

func branch(left : ?Node, right : ?Node) : Node {
  let entries = Prim.Array_init<?(Nat, Nat)>(31, null);
  entries[0] := ?(50, 500);
  {var count = 1; entries; children = [var left, right]}
};

// Forged structures pin the public traversal behavior independently of the
// stricter invariants required by point mutations and assertValid.
let empty = tree(null, 999);
assert Map.minEntry(empty) == null;
assert Map.maxEntry(empty) == null;

// A terminal leaf at depth 128 is still reachable in both directions.
var deep : ?Node = ?leaf(7, 70);
var depth = 0;
while (depth < 128) {
  deep := ?branch(deep, deep);
  depth += 1;
};
let deepestLeaf = tree(deep, 1);
assert Map.minEntry(deepestLeaf) == ?(7, 70);
assert Map.maxEntry(deepestLeaf) == ?(7, 70);

// The same depth limit permits a nullable terminal link at depth 128.
deep := null;
depth := 0;
while (depth < 128) {
  deep := ?branch(deep, deep);
  depth += 1;
};
let deepestNull = tree(deep, 1);
assert Map.minEntry(deepestNull) == null;
assert Map.maxEntry(deepestNull) == null;

// A null selected child ends the search even when the parent has an entry.
// The populated sibling distinguishes the left and right selection paths.
let missingLeft = tree(?branch(null, ?leaf(90, 900)), 2);
assert Map.minEntry(missingLeft) == null;
assert Map.maxEntry(missingLeft) == ?(90, 900);
let missingRight = tree(?branch(?leaf(10, 100), null), 2);
assert Map.minEntry(missingRight) == ?(10, 100);
assert Map.maxEntry(missingRight) == null;

// Public extrema inspect the selected slot without enforcing count <= 31.
let shortEntries = Prim.Array_init<?(Nat, Nat)>(31, null);
shortEntries[0] := ?(3, 30);
let oversizedMin : Node = {var count = 32; entries = shortEntries; children = [var]};
assert Map.minEntry(tree(?oversizedMin, 32)) == ?(3, 30);

let longEntries = Prim.Array_init<?(Nat, Nat)>(32, null);
longEntries[0] := ?(4, 40);
longEntries[31] := ?(93, 930);
let oversizedMax : Node = {var count = 32; entries = longEntries; children = [var]};
assert Map.maxEntry(tree(?oversizedMax, 32)) == ?(93, 930);
