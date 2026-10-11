//MOC-FLAG --plugin ../../../../dist/candidx
import Prim "mo:⛔";

let service : actor {} = actor "aaaaa-aa";
assert Prim.to_candid_canonical(service) == #err("function and service values are excluded");
assert Prim.to_candid_canonical(1 : Nat) == #ok("DIDL\00\01\7d\01");
