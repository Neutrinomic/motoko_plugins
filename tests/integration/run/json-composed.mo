//MOC-FLAG --plugin ../../../dist/json --plugin ../../../dist/sha256 --plugin ../../../dist/candidx --plugin ../../../dist/cbor
//MOC-FLAG --sanity-checks
import Prim "mo:⛔";

type JsonError = {kind : Text; message : Text; path : Text; offset : Nat64};
func jsonOk<T>(r : {#ok : T; #err : JsonError}) : T {
  switch r {case (#ok value) value; case (#err e) Prim.trap(e.message)}
};
func candidOk(r : {#ok : Blob; #err : Text}) : Blob {
  switch r {case (#ok value) value; case (#err e) Prim.trap(e)}
};
type Row = {value : Nat64; note : ?Text; data : Blob};
let input : [Row] = [
  {value = 18_446_744_073_709_551_615; note = ?"☃"; data = "\00\ff"},
  {value = 42; note = null; data = ""},
];
let text = jsonOk(Prim.to_json(input));
let decoded = jsonOk(Prim.from_json<[Row]>(text));
assert decoded == input;
let cbor = jsonOk(Prim.to_cbor(decoded));
let fromCbor = jsonOk(Prim.from_cbor<[Row]>(cbor));
assert fromCbor == input;
assert jsonOk(Prim.to_json(fromCbor)) == text;
let canonical = candidOk(Prim.to_candid_canonical(fromCbor));
assert canonical == candidOk(Prim.to_candid_canonical(input));
assert Prim.sha256(canonical) == Prim.sha256(candidOk(Prim.to_candid_canonical(input)));
assert Prim.sha256(canonical).size() == 32;
switch (Prim.from_json<[Row]>("[{\"value\":-1}]")) {
  case (#ok _) Prim.trap("expected range error");
  case (#err e) assert e.kind == "range";
};
