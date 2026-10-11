//MOC-FLAG --plugin ../../../../dist/mutable-map --package fast ../../../../packages/fast/src
import Prim "mo:⛔";
import Map "mo:fast/Map";
let self = Map.singleton<Nat, Nat>(1, 2);
self.size := 0;
// Forged metadata must not produce a negative Nat during successful removal.
ignore Prim.mmap_take_static<Nat, Nat>(self, 1);
