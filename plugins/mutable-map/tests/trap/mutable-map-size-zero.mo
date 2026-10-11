//MOC-FLAG --plugin ../../../../dist/mutable-map
import Prim "mo:⛔";
import Map "../../motoko/Map";
let self = Map.singleton<Nat, Nat>(1, 2);
self.size := 0;
// Forged metadata must not produce a negative Nat during successful removal.
ignore Prim.mmap_take_static<Nat, Nat>(self, 1);
