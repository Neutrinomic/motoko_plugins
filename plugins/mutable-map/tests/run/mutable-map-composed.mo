//MOC-FLAG --plugin ../../../../dist/mutable-map --plugin ../../../../dist/pure-map --plugin ../../../../dist/json --plugin ../../../../dist/cbor --plugin ../../../../dist/candidx --plugin ../../../../dist/sha256 --package fast ../../../../packages/fast/src --package core $MOTOKO_CORE
//MOC-FLAG --sanity-checks -A M0236
import Prim "mo:⛔";
import Mutable "mo:fast/Map";
import Pure "mo:fast/pure/Map";
func compare(a : Nat, b : Nat) : Mutable.Order { if (a < b) #less else if (a == b) #equal else #greater };
type Error = {kind : Text; message : Text; path : Text; offset : Nat64};
func ok<T>(result : {#ok : T; #err : Error}) : T {
  switch result { case (#ok value) value; case (#err error) Prim.trap(error.message) }
};
func candid(result : {#ok : Blob; #err : Text}) : Blob {
  switch result { case (#ok value) value; case (#err error) Prim.trap(error) }
};
type Row = {id : Nat64; data : Blob; note : ?Text};
let rows : [Row] = [{id = 42; data = "\00\ff"; note = null}, {id = 9000; data = ""; note = ?"é"}];
let json = ok(Prim.to_json(rows));
let decoded = ok(Prim.from_json<[Row]>(json));
let cbor = ok(Prim.to_cbor(decoded));
assert ok(Prim.from_cbor<[Row]>(cbor)) == rows;
let hash = Prim.sha256(candid(Prim.to_candid_canonical(decoded)));
assert hash == Prim.sha256(candid(Prim.to_candid_canonical(rows)));
let mutable = Mutable.empty<Nat, Pure.Map<Nat, Blob>>();
let first = Pure.addNat<Blob>(Pure.empty<Nat, Blob>(), 1, hash);
Mutable.addNat(mutable, 0, first);
let outer = Pure.addNat<Mutable.Map<Nat, Pure.Map<Nat, Blob>>>(null, 10, mutable);
let retained = switch (Pure.getNat(outer, 10)) { case (?value) value; case null Prim.trap("missing shared map") };
Mutable.add(retained, compare, 1, Pure.addNat(first, 2, cbor));
let changed = switch (Mutable.getNat(mutable, 1)) { case (?value) value; case null Prim.trap("missing nested pure map") };
assert Pure.getNat(first, 2) == null;
assert Pure.getNat(changed, 2) == ?cbor;
let cloned = Mutable.clone(mutable);
Mutable.clear(mutable);
assert Mutable.size(retained) == 0;
assert Mutable.size(cloned) == 2;
Mutable.assertValid(cloned, compare);
assert Prim.sha256(candid(Prim.to_candid_canonical(ok(Prim.from_json<[Row]>(json))))) == hash;
