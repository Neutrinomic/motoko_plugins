//MOC-FLAG --plugin ../../../../dist/mutable-map
import Prim "mo:⛔";
import Map "../../motoko/Map";
let self = Map.empty<{key : Nat}, Nat>();
ignore Prim.mmap_get_static<{key : Nat}, Nat>(self, {key = 1});
