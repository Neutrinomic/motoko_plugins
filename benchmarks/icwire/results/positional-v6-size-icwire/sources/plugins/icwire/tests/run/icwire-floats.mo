//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";
func ok<T>(result : Wire.Result<T>) : T {
  switch result { case (#ok value) value; case (#err e) Prim.trap(debug_show e) }
};
func at<T>(result : Wire.Result<T>, kind : Text, offset : Nat) {
  switch result {
    case (#ok _) Prim.trap("expected " # kind);
    case (#err error) {
      if (error.kind != kind or Prim.nat64ToNat(error.offset) != offset) {
        Prim.trap("expected " # debug_show (kind, offset) # ", got " # debug_show error)
      }
    };
  }
};
func append(a : Blob, b : Blob) : Blob {
  let left = Prim.blobToArray(a);
  let right = Prim.blobToArray(b);
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(left.size() + right.size(), func i {
    if (i < left.size()) left[i] else right[i - left.size()]
  }))
};
func decode64(bytes : Blob) : Wire.Result<Blob> {
  switch (Wire.decode<[Float]>(bytes)) {
    case (#ok value) Wire.encode(value);
    case (#err error) #err error;
  }
};
func decode32(bytes : Blob) : Wire.Result<Blob> {
  switch (Wire.decode<[Float32]>(bytes)) {
    case (#ok value) Wire.encode(value);
    case (#err error) #err error;
  }
};
// Both zero signs and finite bit patterns survive load, boxing, and reencoding.
let minusZero64 : Blob = "\00\00\00\00\00\00\00\80";
let minusZero32 : Blob = "\00\00\00\80";
let finite64 : Blob = "\03\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\80\00\00\00\00\00\00\f8\3f";
let finite32 : Blob = "\03\00\00\00\00\00\00\00\80\00\00\c0\3f";
assert ok(decode64("\00")) == "\00";
assert ok(decode32("\00")) == "\00";
assert ok(decode64(finite64)) == finite64;
assert ok(decode32(finite32)) == finite32;
let nested64 = (7 : Nat8, [0.0, -0.0, 1.5] : [Float], 0x1234 : Nat16);
let nested32 = (7 : Nat8, [0.0, -0.0, 1.5] : [Float32], 0x1234 : Nat16);
assert ok(Wire.encode(nested64)) == append("\07", append(finite64, "\34\12"));
assert ok(Wire.encode(nested32)) == append("\07", append(finite32, "\34\12"));
assert ok(Wire.encode(ok(Wire.decode<(Nat8, [Float], Nat16)>(ok(Wire.encode(nested64)))))) == ok(Wire.encode(nested64));
assert ok(Wire.encode(ok(Wire.decode<(Nat8, [Float32], Nat16)>(ok(Wire.encode(nested32)))))) == ok(Wire.encode(nested32));
let invalid64 : [Blob] = ["\00\00\00\00\00\00\f8\7f", "\00\00\00\00\00\00\f0\7f", "\00\00\00\00\00\00\f0\ff"];
let invalid32 : [Blob] = ["\00\00\c0\7f", "\00\00\80\7f", "\00\00\80\ff"];
var digest : Nat64 = 14695981039346656037;
var errors = 0;
func record(bytes : Blob, result : Wire.Result<Blob>) {
  switch result { case (#err _) errors += 1; case (#ok _) Prim.trap("expected malformed float array") };
  for (byte in Prim.encodeUtf8(debug_show (bytes.size(), result)).values()) {
    digest := (digest ^ Prim.natToNat64(Prim.nat8ToNat(byte))) *% 1099511628211;
  };
  digest := (digest ^ 255) *% 1099511628211;
};
// Check every truncation of arrays with NaN or infinity at first/middle/last.
// A complete invalid word wins over later truncation; partial words stay unread.
func exercise(width : Nat, zero : Blob, invalid : [Blob], decode : Blob -> Wire.Result<Blob>) {
  for (bad in invalid.values()) {
    var position = 0;
    while (position < 3) {
      var complete : Blob = "\03";
      var element = 0;
      while (element < 3) {
        complete := append(complete, if (element == position) bad else zero);
        element += 1;
      };
      let raw = Prim.blobToArray(complete);
      var length = 0;
      while (length <= raw.size()) {
        let prefix = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(length, func i { raw[i] }));
        let result = decode(prefix);
        if (length >= 1 + (position + 1) * width) {
          at(result, "float", 1 + position * width)
        } else if (length == 0) {
          at(result, "truncated", 0)
        } else {
          at(result, "truncated", 1 + (Prim.abs((length : Int) - 1) / width) * width)
        };
        record(prefix, result);
        length += 1;
      };
      position += 1;
    };
  }
};
exercise(8, minusZero64, invalid64, decode64);
exercise(4, minusZero32, invalid32, decode32);
at(Wire.decode<(Nat8, [Float], Nat16)>(append("\07\02", invalid64[0])), "float", 2);
at(Wire.decode<(Nat8, [Float32], Nat16)>(append("\07\02", invalid32[0])), "float", 2);
at(Wire.decode<[Float]>("\c0\84\3d"), "limit", 3);
at(Wire.decode<[Float32]>("\c0\84\3d"), "limit", 3);
at(Wire.decode<[Float]>("\bf\84\3d"), "truncated", 3);
at(Wire.decode<[Float32]>("\bf\84\3d"), "truncated", 3);
at(Wire.decode<(Null, [Float])>("\be\84\3d"), "limit", 3);
at(Wire.decode<(Null, [Float32])>("\be\84\3d"), "limit", 3);
type Nest64 = {#next : Nest64; #end : [Float]};
type Nest32 = {#next : Nest32; #end : [Float32]};
func nest64(n : Nat, values : [Float]) : Nest64 {
  var value : Nest64 = #end(values);
  var count = n;
  while (count > 0) { value := #next(value); count -= 1 };
  value
};
func nest32(n : Nat, values : [Float32]) : Nest32 {
  var value : Nest32 = #end(values);
  var count = n;
  while (count > 0) { value := #next(value); count -= 1 };
  value
};
let populated64 = nest64(125, [-0.0, 1.5]);
let populated32 = nest32(125, [-0.0, 1.5]);
assert ok(Wire.decode<Nest64>(ok(Wire.encode(populated64)))) == populated64;
assert ok(Wire.decode<Nest32>(ok(Wire.encode(populated32)))) == populated32;
let deep64 = nest64(126, []);
let deep32 = nest32(126, []);
assert ok(Wire.decode<Nest64>(ok(Wire.encode(deep64)))) == deep64;
assert ok(Wire.decode<Nest32>(ok(Wire.encode(deep32)))) == deep32;
let depthPrefix = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(128, func i {
  if (i < 126) 1 else if (i == 126) 0 else 1
}));
at(Wire.decode<Nest64>(append(depthPrefix, invalid64[0])), "limit", 128);
at(Wire.decode<Nest32>(append(depthPrefix, invalid32[0])), "limit", 128);
at(Wire.encode(nest64(126, [0.0 / 0.0])), "limit", 128);
at(Wire.encode(nest32(126, [0.0 / 0.0])), "limit", 128);
assert errors == 360;
Prim.debugPrint(debug_show (errors, digest));
