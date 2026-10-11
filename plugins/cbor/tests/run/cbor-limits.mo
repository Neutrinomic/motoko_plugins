//MOC-FLAG --plugin ../../../../dist/cbor
import Prim "mo:⛔";
type Error = {kind : Text; message : Text; path : Text; offset : Nat64};
func err<T>(result : {#ok : T; #err : Error}) : Error {
  switch result {case (#err e) e;case _ Prim.trap("expected limit error")}
};
type Chain = ?{next : Chain};
var chain : Chain = null;
var i = 0;
while (i < 100) {
  chain := ?{next=chain};
  i += 1;
};
assert err(Prim.to_cbor(chain)).kind == "limit";
let prefix : [Nat8] = [0xa1,0x64,0x6e,0x65,0x78,0x74];
let raw = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(601,func(i) {if (i == 600) 0xf6 else prefix[i % 6]}));
assert err(Prim.from_cbor<Chain>(raw)).kind == "limit";
assert err(Prim.from_cbor<Blob>("\5a\01\00\00\01")).kind == "limit";
// Collection bounds are checked before traversing or decoding elements.
let tooMany = Prim.Array_tabulate<Null>(1_000_000,func(_) {null});
assert err(Prim.to_cbor(tooMany)).kind == "limit";
assert err(Prim.to_cbor({items=tooMany})).path == "/items";
let huge : Nat = 2 ** 32768;
assert err(Prim.to_cbor(huge)).kind == "limit";
assert err(Prim.to_cbor(??huge : ??Nat)).path == "/some";
assert Prim.from_cbor<Nat8>("\18\2a") == #ok(42 : Nat8);
assert Prim.to_cbor([true,false]) == #ok("\82\f5\f4" : Blob);
