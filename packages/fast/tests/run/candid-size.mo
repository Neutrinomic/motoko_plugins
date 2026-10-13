//MOC-FLAG --package fast ../../src --plugin ../../../../dist/candidx --sanity-checks
import CandidX "mo:fast/CandidX";

let estimate = CandidX.estimateSize;
assert estimate() >= 6;
assert estimate(42 : Nat) >= 8;
assert estimate(-65 : Int) >= 9;
assert estimate("hello 🌍") >= 17;
assert estimate("\00\01" : Blob) >= 11;
assert estimate([1, 2, 3] : [Nat64]) >= 34;
assert estimate([1, 2, 3] : [Nat64]) == estimate([0, 0, 0] : [Nat64]);
assert estimate(2 ** 4096 : Nat) >= 586;
assert estimate(-(2 ** 4096) : Int) >= 586;

type List = ?(Text, List);
let list : List = ?("a", ?("b", null));
assert estimate(list) >= 20;
var calls = 0;
func next() : Nat { calls += 1; calls };
ignore estimate(next(), next(), next());
assert calls == 3;

// Values erased to Any are not traversed, including mutable cycles.
let mutable = [var 1];
assert estimate(mutable : Any) == estimate(null : Any);
let cycle = object { public var next : ?Any = null };
cycle.next := ?cycle;
assert estimate(cycle : Any) == estimate(null : Any);

type Tree = { #leaf : Text; #fork : (Tree, Tree) };
var tree : Tree = #leaf "x";
var depth = 0;
while (depth < 25) { tree := #fork(tree, tree); depth += 1 };
assert estimate(tree) == 2_305_843_009_213_693_951;

var deep : List = null;
depth := 0;
while (depth < 300) { deep := ?("", deep); depth += 1 };
assert estimate(deep) == 2_305_843_009_213_693_951;
assert estimate("recovery") < 100;
