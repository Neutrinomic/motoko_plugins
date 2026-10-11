//MOC-FLAG --plugin ../../../../dist/mutable-map
import Prim "mo:⛔";
// A mutable map must expose typed mutable fields; an immutable record is not
// accepted as an owner of the managed mutation kernel.
let self = {root = null; size = 0};
Prim.mmap_add<Nat, Nat>(self, func(a : Nat, b : Nat) : {#less; #equal; #greater} { if (a < b) #less else if (a == b) #equal else #greater }, 1, 2);
