//MOC-FLAG --plugin ../../../../dist/mutable-map --package fast ../../../../packages/fast/src --package core $MOTOKO_CORE
import Prim "mo:⛔";
import Map "mo:fast/Map";
let self = Map.empty<{key : Nat}, Nat>();
ignore Prim.mmap_get_static<{key : Nat}, Nat>(self, {key = 1});
