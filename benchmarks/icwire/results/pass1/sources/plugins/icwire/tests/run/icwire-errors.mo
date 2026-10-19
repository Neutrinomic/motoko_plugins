//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";
func err<T>(result : Wire.Result<T>, kind : Text) {
  switch result { case (#ok _) Prim.trap("expected " # kind); case (#err e) {
    if (e.kind != kind) Prim.trap("expected " # kind # ", got " # debug_show e);
  } }
};
func at<T>(result : Wire.Result<T>, kind : Text, offset : Nat64) {
  err(result, kind);
  switch result {case (#err e) assert e.offset == offset; case _ Prim.trap("expected error")}
};
at(Wire.decode<Nat>(""), "truncated", 0);
at(Wire.decode<Nat>("ICW0\00"), "header", 0);
at(Wire.decode<Nat>("ICW1"), "truncated", 4);
at(Wire.decode<Nat>("ICW1\00\00"), "trailing", 5);
at(Wire.decode<Bool>("ICW1\02"), "bool", 4);
at(Wire.decode<?Nat>("ICW1\02"), "bool", 4);
at(Wire.decode<Nat32>("ICW1\01\02\03"), "truncated", 4);
at(Wire.decode<Nat>("ICW1\80\00"), "canonical", 4);
at(Wire.decode<Int>("ICW1\ff\7f"), "canonical", 4);
at(Wire.decode<Int>("ICW1\80\00"), "canonical", 4);
at(Wire.decode<Char>("ICW1\00\d8\00\00"), "char", 4);
at(Wire.decode<Char>("ICW1\00\00\11\00"), "char", 4);
err(Wire.decode<Text>("ICW1\01\00\00\00\ff"), "utf8");
err(Wire.decode<Text>("ICW1\03\00\00\00\ed\a0\80"), "utf8");
err(Wire.decode<Text>("ICW1\02\00\00\00\c0\80"), "utf8");
err(Wire.decode<Text>("ICW1\04\00\00\00\f4\90\80\80"), "utf8");
err(Wire.decode<Principal>("ICW1\1e\00\00\00abcdefghijklmnopqrstuvwxyz1234"), "principal");
err(Wire.decode<Blob>("ICW1\ff\ff\ff\ff"), "limit");
at(Wire.decode<[Null]>("ICW1\ff\ff\ff\ff"), "limit", 8);
at(Wire.decode<Float>("ICW1\00\00\00\00\00\00\f0\7f"), "float", 4);
at(Wire.decode<Float32>("ICW1\00\00\c0\7f"), "float", 4);
err(Wire.encode(0.0 / 0.0 : Float), "float");
err(Wire.encode(1.0 / 0.0 : Float), "float");
err(Wire.encode(-1.0 / 0.0 : Float32), "float");
at(Wire.decode<{a : Nat}>("ICW1\00\00\00\00"), "missing", 8);
at(Wire.decode<{#a : Nat}>("ICW1\62\00\00\00"), "variant", 8);
// Fields cannot consume a sibling, leave unused payload, or explicitly encode null options.
err(Wire.decode<{a : Nat16}>("ICW1\09\00\00\00\61\00\00\00\01\00\00\00\01"), "truncated");
err(Wire.decode<{a : Nat8}>("ICW1\0a\00\00\00\61\00\00\00\02\00\00\00\01\02"), "length");
err(Wire.decode<{a : ?Nat}>("ICW1\09\00\00\00\61\00\00\00\01\00\00\00\00"), "canonical");
err(Wire.decode<{}>("ICW1\0a\00\00\00\61\00\00\00\ff\ff\ff\ff\01\02"), "truncated");
// Duplicate and descending tags are rejected even when every field is unknown.
err(Wire.decode<{}>("ICW1\10\00\00\00\61\00\00\00\00\00\00\00\61\00\00\00\00\00\00\00"), "canonical");
err(Wire.decode<{}>("ICW1\10\00\00\00\62\00\00\00\00\00\00\00\61\00\00\00\00\00\00\00"), "canonical");
// Every prefix truncation must fail, including those inside a nested record field.
let complete : Blob = "ICW1\0f\00\00\00\61\00\00\00\07\00\00\00\03\00\00\00abc";
var prefix = "" : Blob;
for (byte in complete.vals()) {
  err(Wire.decode<{a : Text}>(prefix), "truncated");
  prefix := Prim.arrayToBlob(Prim.Array_append<Nat8>(Prim.blobToArray(prefix), [byte]));
};
