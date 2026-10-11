//MOC-FLAG --plugin ../../../../dist/json
import Prim "mo:⛔";

type Error = { kind : Text; message : Text; path : Text; offset : Nat64 };
type Result<T> = { #ok : T; #err : Error };
func error<T>(result : Result<T>) : Error {
  switch result {
    case (#err value) value;
    case (#ok _) Prim.trap("expected JSON error");
  }
};

// Nullable options retain every distinction, including present null payloads.
type Nested = ??Null;
assert Prim.from_json<Nested>("null") == #ok null;
assert Prim.from_json<Nested>("{\"some\":null}") == #ok (?null);
assert Prim.from_json<Nested>("{\"some\":{\"some\":null}}") == #ok (?(?null));
assert Prim.to_json((?(?null) : Nested)) ==
  #ok "{\"some\":{\"some\":null}}";

// Original Motoko names are JSON keys, including Candid-looking identifiers.
type Names = { _42_ : Nat8; some : Text };
assert Prim.from_json<Names>("{\"_42_\":7,\"some\":\"literal\"}") ==
  #ok { _42_ = 7; some = "literal" };
assert Prim.to_json(({ _42_ = 7; some = "literal" } : Names)) ==
  #ok "{\"_42_\":7,\"some\":\"literal\"}";
assert Prim.to_json([]) == #ok "[]";
let withType = object { public type Count = Nat; public let count : Count = 3 };
assert Prim.to_json(withType) == #ok "{\"count\":\"3\"}";

type Node = { name : Text; next : ?Node };
let node : Node = { name = "first"; next = ?{ name = "second"; next = null } };
switch (Prim.to_json(node)) {
  case (#ok text) assert Prim.from_json<Node>(text) == #ok node;
  case (#err _) Prim.trap("recursive JSON encoding failed");
};

// Error paths must match in source/IR interpretation and generated Wasm.
assert error(Prim.from_json<??Nat>("{\"some\":\"bad\"}")).path == "/some";
assert error(Prim.from_json<??Nat>("{\"wrong\":null}")).path == "/wrong";
assert error(Prim.from_json<??Nat>("{\"some\":null,\"extra\":1}")) == {
  kind = "type"; message = "Expected exactly one object field";
  path = "/extra"; offset = 21;
};
assert error(Prim.from_json<{ #a : Nat }>("{\"b\":1}")).path == "/b";
assert error(Prim.from_json<{ #a : Nat }>("{\"a\":1,\"extra\":2}")).path == "/extra";
assert error(Prim.from_json<[Nat]>("[0, truX]")).path == "/1";
assert error(Prim.from_json<{}>("{\"ghost\":[{\"x\":1,\"\\u0078\":2}]}")).path == "/ghost/0";
assert error(Prim.from_json<[{ value : Nat }]>("[{\"value\":1,\"value\":2}]")).path == "/0";
assert error(Prim.from_json<[Nat]>("[\"wrong\",trux]")) == {
  kind = "type"; message = "Unexpected JSON literal"; path = "/1";
  offset = 9;
};
assert error(Prim.from_json<(Nat, Nat)>("[1]")) == {
  kind = "type"; message = "Unexpected JSON tuple length"; path = "";
  offset = 1;
};

// Field names containing a slash/tilde use JSON Pointer escaping in errors.
assert error(Prim.from_json<{}>("{\"a/b~\":[{\"x\":1,\"x\":2}]}")).path == "/a~1b~0/0";

// Decimal integers remain exact at both signs and fixed-width boundaries.
assert Prim.from_json<Int>("\"-18446744073709551617000000000000000000\"") ==
  #ok (-18446744073709551617000000000000000000 : Int);
assert Prim.from_json<Int64>("\"-9223372036854775808\"") ==
  #ok (-9223372036854775808 : Int64);
assert Prim.from_json<Nat64>("\"18446744073709551615\"") ==
  #ok (18446744073709551615 : Nat64);
assert error(Prim.from_json<Nat64>("\"18446744073709551616\"")).kind == "range";
assert Prim.from_json<Float>("\"-Infinity\"") == #ok (-1.0 / 0.0);
// These decimals are just above binary32 midpoints. Parsing via binary64
// followed by demotion would incorrectly return 1.0 and -1.0, respectively.
assert Prim.from_json<Float32>("1.0000000596046448") ==
  #ok (Prim.floatToFloat32(1.0 + 1.0 / 8388608.0));
assert Prim.from_json<Float32>("-1.0000000596046448") ==
  #ok (Prim.floatToFloat32(-(1.0 + 1.0 / 8388608.0)));
switch (Prim.from_json<Float>("-0.0")) {
  case (#ok value) assert 1.0 / value == -1.0 / 0.0;
  case (#err _) Prim.trap("negative zero decoding failed");
};

assert Prim.from_json<Blob>("\"\"") == #ok ("" : Blob);
assert error(Prim.from_json<Blob>("\"Zh==\"")).kind == "base64";
assert Prim.from_json<Char>("\"\\uD83D\\uDE00\"") == #ok '😀';
