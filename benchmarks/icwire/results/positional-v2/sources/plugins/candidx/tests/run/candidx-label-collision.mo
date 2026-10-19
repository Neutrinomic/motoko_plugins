//MOC-FLAG --plugin ../../../../dist/candidx
import Prim "mo:⛔";

assert Prim.to_candid_canonical({ a = 1 : Nat; _97_ = 2 : Nat }) == #err("source type field ids must strictly increase");
assert Prim.to_candid_canonical(1 : Nat) == #ok("DIDL\00\01\7d\01");
