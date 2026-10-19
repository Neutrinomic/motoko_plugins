//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";
func err<T>(result : Wire.Result<T>, kind : Text) {
  switch result { case (#ok _) Prim.trap("expected " # kind); case (#err e) {
    if (e.kind != kind) Prim.trap("expected " # kind # ", got " # debug_show e);
  } }
};
func at<T>(result : Wire.Result<T>, kind : Text, offset : Nat) {
  err(result, kind);
  switch result {case (#err e) if (Prim.nat64ToNat(e.offset) != offset) Prim.trap("expected offset " # debug_show offset # ", got " # debug_show e); case _ Prim.trap("expected error")}
};
at(Wire.decode<Nat>(""), "truncated", 0);
at(Wire.decode<Nat>("\80"), "truncated", 1);
at(Wire.decode<Nat>("\00\00"), "trailing", 1);
at(Wire.decode<Bool>("\02"), "bool", 0);
at(Wire.decode<?Nat>("\02"), "bool", 0);
at(Wire.decode<Nat32>("\01\02\03"), "truncated", 0);
at(Wire.decode<Nat>("\80\00"), "canonical", 0);
at(Wire.decode<Int>("\ff\7f"), "canonical", 0);
at(Wire.decode<Int>("\80\00"), "canonical", 0);
at(Wire.decode<Char>("\00\d8\00\00"), "char", 0);
at(Wire.decode<Char>("\00\00\11\00"), "char", 0);
at(Wire.decode<Text>("\01\ff"), "utf8", 0);
at(Wire.decode<Text>("\03\ed\a0\80"), "utf8", 0);
at(Wire.decode<Text>("\02\c0\80"), "utf8", 0);
at(Wire.decode<Text>("\04\f4\90\80\80"), "utf8", 0);
at(Wire.decode<Principal>("\1eabcdefghijklmnopqrstuvwxyz1234"), "principal", 0);
at(Wire.decode<Principal>("\1e"), "principal", 0);
at(Wire.decode<Blob>("\ff\ff\ff\ff\0f"), "limit", 0);
at(Wire.decode<[Null]>("\ff\ff\ff\ff\0f"), "limit", 5);
at(Wire.decode<Float>("\00\00\00\00\00\00\f0\7f"), "float", 0);
at(Wire.decode<Float32>("\00\00\c0\7f"), "float", 0);
err(Wire.encode(0.0 / 0.0 : Float), "float");
err(Wire.encode(1.0 / 0.0 : Float), "float");
err(Wire.encode(-1.0 / 0.0 : Float32), "float");
at(Wire.encode((true, 1.0 / 0.0 : Float)), "float", 1);
at(Wire.encode(({a = null : ?Nat; b = true}, 1.0 / 0.0 : Float)), "float", 2);
// The exact schema is required: fields cannot be absent or skipped.
at(Wire.decode<{a : Nat}>(""), "truncated", 0);
at(Wire.decode<{a : ?Nat}>(""), "truncated", 0);
at(Wire.decode<{a : Nat8; z : ?Text}>("\01"), "truncated", 1);
at(Wire.decode<{a : Nat8}>("\01\02"), "trailing", 1);
at(Wire.decode<{}>("\00"), "trailing", 0);
at(Wire.decode<{#a : Nat}>("\01"), "variant", 1);
at(Wire.decode<{#a : Nat}>("\80\01"), "variant", 2);
at(Wire.decode<{#a : Nat}>("\00"), "truncated", 1);
// Lengths, counts, and ordinals share canonical unsigned 32-bit LEB prefixes.
let malformed : [Blob] = ["\80\00", "\81\00", "\ff\ff\ff\ff\10", "\80\80\80\80\80"];
for (bytes in malformed.values()) {
  at(Wire.decode<Blob>(bytes), "canonical", 0);
  at(Wire.decode<Text>(bytes), "canonical", 0);
  at(Wire.decode<Principal>(bytes), "canonical", 0);
  at(Wire.decode<[Nat8]>(bytes), "canonical", 0);
  at(Wire.decode<[Nat16]>(bytes), "canonical", 0);
  at(Wire.decode<[Null]>(bytes), "canonical", 0);
  at(Wire.decode<{#a}>(bytes), "canonical", 0);
};
at(Wire.decode<Blob>("\80"), "truncated", 1);
at(Wire.decode<Text>("\80\80\80\80"), "truncated", 4);
at(Wire.decode<[Nat16]>("\02\00\00\00"), "truncated", 3);
at(Wire.decode<(Nat8, Text)>("\07\80\00"), "canonical", 1);
at(Wire.decode<(Nat8, Text)>("\07\01\ff"), "utf8", 1);
// Every prefix truncation fails, including inside a nested positional record.
let complete : Blob = "\03abc";
let bytes = Prim.blobToArray(complete);
var length = 0;
while (length < bytes.size()) {
  let prefix = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(length, func i { bytes[i] }));
  err(Wire.decode<{a : {b : Text}}>(prefix), "truncated");
  length += 1;
};
