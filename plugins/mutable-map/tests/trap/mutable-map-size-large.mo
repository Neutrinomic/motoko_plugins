//MOC-FLAG --plugin ../../../../dist/mutable-map --package fast ../../../../packages/fast/src --package core $MOTOKO_CORE
import Prim "mo:⛔";
import Map "mo:fast/Map";
let self = Map.singleton<Nat, Nat>(1, 2);
self.size := 18446744073709551616;
// Forged metadata must not wrap through the runtime's Nat-to-machine bridge.
ignore Prim.mmap_take_static<Nat, Nat>(self, 1);
