//MOC-FLAG --plugin ../../../../dist/mutable-set --package fast ../../../../packages/fast/src --package core $MOTOKO_CORE
import Prim "mo:⛔";
import Set "mo:fast/Set";
ignore Prim.mset_contains_static<{key : Nat}>(Set.empty<{key : Nat}>(), {key = 1});
