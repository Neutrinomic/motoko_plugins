//MOC-FLAG --package fast ../../src --plugin ../../../../dist/candidx --sanity-checks
import CandidX "mo:fast/CandidX";

let encode = CandidX.encode;
let empty : CandidX.Result = encode();
assert empty == #ok "DIDL\00\00";
assert encode(1 : Nat) == #ok "DIDL\00\01\7d\01";
let two = encode(1 : Nat, true);
let tuple = encode((1 : Nat, true));
switch (two, tuple) {
  case (#ok arguments, #ok record) assert arguments != record;
  case _ assert false;
};
// Canonical omission of absent optional fields survives the public alias.
assert encode({ value = 42 : Nat; absent = null : ?Text }) ==
  encode({ value = 42 : Nat });
let service : actor { call : shared () -> async () } = actor "aaaaa-aa";
switch (encode(service.call)) {
  case (#ok _) assert false;
  case (#err error) {
    let typed : CandidX.Error = error;
    assert typed == "function and service values are excluded";
  };
};
