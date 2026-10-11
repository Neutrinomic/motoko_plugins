//MOC-FLAG --plugin ../../../../dist/mutable-set --package fast ../../../../packages/fast/src --package core $MOTOKO_CORE
//MOC-FLAG -A M0236
import Prim "mo:⛔";
import Set "mo:fast/Set";
let node : Set.Node<Nat> = {
  var count = 1;
  entries = Prim.Array_init<?Nat>(31, null);
  children = Prim.Array_init<?Set.Node<Nat>>(32, null);
};
node.entries[0] := ?1;
node.children[0] := ?node;
let self : Set.Set<Nat> = {var root = ?node; var size = 1};
ignore Set.containsNat(self, 0);
