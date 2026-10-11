//MOC-FLAG --plugin ../../../../dist/json
import Prim "mo:⛔";
type Error = {kind : Text; message : Text; path : Text; offset : Nat64};
func err<T>(result : {#ok : T; #err : Error}) : Error {
  switch result {case (#err error) error; case (#ok _) Prim.trap("expected error")}
};
assert err(Prim.from_json<Nat8>("256")).kind == "range";
assert err(Prim.from_json<Nat>("-1")).kind == "range";
assert err(Prim.from_json<Nat>("1.5")).kind == "range";
assert err(Prim.from_json<Nat8>("\"1\"")).kind == "type";
assert err(Prim.from_json<Int>("\"01\"")).kind == "range";
assert err(Prim.from_json<Float>("1e999")).kind == "range";
assert err(Prim.from_json<Float32>("1e39")).kind == "range";
assert err(Prim.from_json<Text>("\"\\uD800\"")).kind == "syntax";
assert err(Prim.from_json<Text>("\"\\uDC00\"")).kind == "syntax";
assert err(Prim.from_json<Char>("\"ab\"")).kind == "type";
assert err(Prim.from_json<Blob>("\"Yh==\"")).kind == "base64";
assert err(Prim.from_json<Principal>("\"2vxsx-fab\"")).kind == "principal";
assert err(Prim.from_json<{x : Nat8}>("{\"x\":1,\"x\":2}")).kind == "duplicate";
assert err(Prim.from_json<{}>("{\"ignored\":{\"x\":1,\"x\":2}}")).kind == "duplicate";
assert err(Prim.from_json<{x : Nat8}>("{}")).kind == "missing";
assert err(Prim.from_json<{x : Nat8}>("{\"x\":256}")).path == "/x";
assert err(Prim.from_json<[{x : Nat8}]>("[{\"x\":1},{\"x\":256}]")).path == "/1/x";
assert err(Prim.from_json<[Nat8]>("[1,]")).kind != "missing";
assert err(Prim.from_json<(Nat8, Nat8)>("[1]")).kind == "type";
assert err(Prim.from_json<Nat8>("1 true")).kind == "syntax";
assert err(Prim.from_json<{#a : Nat8; #b : Bool}>("{\"c\":1}")).kind == "type";
assert err(Prim.from_json<{#a : Nat8; #b : Bool}>("{\"a\":1,\"b\":true}")).kind == "type";
assert err(Prim.from_json<??Nat>("{\"none\":null}")).kind == "type";
// A failed decoder leaves the allocator valid and later calls independent.
var i = 0;
while (i < 100) {
  ignore err(Prim.from_json<[{x : Nat8; y : [Text]}]>("[{\"x\":1,\"y\":[\"kept\"]},{\"x\":999}]") );
  switch (Prim.from_json<{x : Nat8}>("{\"x\":7}")) {case (#ok value) assert value.x == 7; case (#err _) assert false};
  i += 1;
};
