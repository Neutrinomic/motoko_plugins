//MOC-FLAG --plugin ../../../../dist/mutable-map --package fast ../../../../packages/fast/src
import Prim "mo:⛔";
import Map "mo:fast/Map";
// Structural fields are private by contract. Forged cyclic input must still
// stop with a controlled trap, without unbounded recursion or raw heap writes.
let node : Map.Node<Nat, Nat> = {
  var count = 1;
  entries = Prim.Array_init<?(Nat, Nat)>(31, null);
  children = Prim.Array_init<?Map.Node<Nat, Nat>>(32, null);
};
node.entries[0] := ?(1, 2);
node.children[0] := ?node;
let self : Map.Map<Nat, Nat> = {var root = ?node; var size = 1};
ignore Prim.mmap_get_static<Nat, Nat>(self, 0);
