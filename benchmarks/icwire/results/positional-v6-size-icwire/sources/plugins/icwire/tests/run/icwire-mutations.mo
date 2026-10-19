//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";
type Packet = {
  sequence : Nat64;
  body : {#send : {amount : Nat; fee : Int; owner : Principal; memo : Blob}; #cancel : Nat32; #none};
  flags : [Bool];
  extra : ?{name : Text; levels : [?Int]};
  nested : [(Nat8, Text)];
};
func ok<T>(result : Wire.Result<T>) : T {
  switch result { case (#ok value) value; case (#err e) Prim.trap(debug_show e) }
};
let packets : [Packet] = [
  {
    sequence = 0x0123456789abcdef;
    body = #send({amount = 1361129467683753853853498429727072845824; fee = -18446744073709551617; owner = Prim.principalOfBlob("\04"); memo = "\00\ffmemo\80\01"});
    flags = [true, false, true];
    extra = ?{name = "snow ☃ 😀"; levels = [null, ?(-1), ?18446744073709551616]};
    nested = [(1, "one"), (2, ""), (255, "three")];
  },
  {sequence = 0; body = #cancel(0xffffffff); flags = []; extra = null; nested = []},
  {sequence = 18446744073709551615; body = #none; flags = [false]; extra = ?{name = ""; levels = [?0]}; nested = [(0, "zero")]},
];
var digest : Nat64 = 14695981039346656037;
var successes = 0;
var errors = 0;
func inspect(bytes : Blob) {
  // Reencoding every success checks canonical output and preservation of values.
  // The digest includes the exact error kind and offset for every failed decode.
  let outcome : Wire.Result<Blob> = switch (Wire.decode<Packet>(bytes)) {
    case (#ok value) { successes += 1; Wire.encode(value) };
    case (#err error) { errors += 1; #err error };
  };
  let text = debug_show (bytes.size(), outcome);
  for (byte in Prim.encodeUtf8(text).values()) {
    digest := (digest ^ Prim.natToNat64(Prim.nat8ToNat(byte))) *% 1099511628211;
  };
  digest := (digest ^ 255) *% 1099511628211;
};
var random : Nat32 = 0x83c96e21;
let masks : [Nat8] = [1, 128, 255];
func next() : Nat32 { random := random *% 1664525 +% 1013904223; random };
for (packet in packets.values()) {
  let original = ok(Wire.encode(packet));
  let bytes = Prim.blobToArray(original);
  inspect(original);
  // Every proper truncation and three independent single-byte mutations.
  var position = 0;
  while (position < bytes.size()) {
    inspect(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(position, func i { bytes[i] })));
    for (mask in masks.values()) {
      inspect(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(bytes.size(), func i {
        if (i == position) bytes[i] ^ mask else bytes[i]
      })));
    };
    position += 1;
  };
  // Reproducible multi-byte mutations exercise combinations in positional values.
  var sample = 0;
  while (sample < 128) {
    let first = Prim.nat32ToNat(next()) % bytes.size();
    let second = Prim.nat32ToNat(next()) % bytes.size();
    let firstMask = Prim.natToNat8(Prim.nat32ToNat(next()) % 256);
    let secondMask = Prim.natToNat8(Prim.nat32ToNat(next()) % 256);
    inspect(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(bytes.size(), func i {
      bytes[i] ^ (if (i == first) firstMask else 0) ^ (if (i == second) secondMask else 0)
    })));
    sample += 1;
  };
};
assert successes > 100;
assert errors > 100;
Prim.debugPrint(debug_show (successes, errors, digest));
