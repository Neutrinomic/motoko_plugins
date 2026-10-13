//MOC-FLAG --package fast ../../../../packages/fast/src --plugin ../../../../dist/ml-dsa --sanity-checks
import MLDSA "mo:fast/MLDSA";
import Prim "mo:⛔";
import Vectors "../Vectors";

// Official ACVP tcId 4 has at least two hints in every row and spare padding.
let v = Vectors.sigGen[0];
let signature = v.signature;
let hintStart : Nat = 2336;
let endpointStart : Nat = 2416;
let omega : Nat = 80;
let rows : [Nat] = [0, 1, 2, 3];
assert v.id == 4;
assert signature.size() == 2420;
let total = Prim.nat8ToNat(signature[endpointStart + 3]);
assert total + 1 < omega;

let prepared = switch (MLDSA.preparePublicKey(v.publicKey)) {
  case (#ok key) key;
  case (#err _) Prim.trap("canonical hints: public-key preparation failed")
};
assert MLDSA.verify(v.publicKey, v.message, signature, v.context) == #ok(true);
assert MLDSA.verifyPrepared(prepared, v.message, signature, v.context) == #ok(true);

// Decode only the mathematical hint bits, deliberately ignoring index order,
// duplicates and unused padding. Every mutation below preserves this value.
// Consequently a verifier that omits the relevant canonical-encoding check
// would accept the mutation; a different challenge cannot mask that regression.
func hintBits(encoded : Blob) : Blob {
  let bits = Prim.Array_init<Nat8>(4 * 256, 0);
  var start : Nat = 0;
  for (row in rows.values()) {
    let finish = Prim.nat8ToNat(encoded[endpointStart + row]);
    assert start <= finish and finish <= omega;
    while (start < finish) {
      bits[row * 256 + Prim.nat8ToNat(encoded[hintStart + start])] := 1;
      start += 1;
    };
  };
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(bits.size(), func(i) { bits[i] }))
};
let originalHints = hintBits(signature);

func rejected(encoded : Blob) {
  assert encoded != signature;
  assert encoded.size() == signature.size();
  var i : Nat = 0;
  while (i < hintStart) {
    assert encoded[i] == signature[i];
    i += 1;
  };
  assert hintBits(encoded) == originalHints;
  assert MLDSA.verify(v.publicKey, v.message, encoded, v.context) == #ok(false);
  assert MLDSA.verifyPrepared(prepared, v.message, encoded, v.context) == #ok(false);
};

var first : Nat = 0;
for (row in rows.values()) {
  let finish = Prim.nat8ToNat(signature[endpointStart + row]);
  assert first + 2 <= finish;
  let at = hintStart + first;
  assert signature[at] < signature[at + 1];

  // Swap two existing indices in this row without changing its hint bits.
  rejected(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(signature.size(), func(i) {
    if (i == at) signature[at + 1]
    else if (i == at + 1) signature[at]
    else signature[i]
  })));

  // Insert a duplicate of this row's first index, shift the remaining used
  // indices right and advance this and every later endpoint by one.
  rejected(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(signature.size(), func(i) {
    if (i < at + 1) signature[i]
    else if (i <= hintStart + total) signature[i - 1]
    else if (i < endpointStart) 0
    else if (i >= endpointStart + row) signature[i] + 1
    else signature[i]
  })));
  first := finish;
};

// Modify the first and last unused padding bytes while retaining all hints.
for (at in ([hintStart + total, endpointStart - 1] : [Nat]).values()) {
  assert signature[at] == 0;
  rejected(Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(signature.size(), func(i) {
    if (i == at) 1 else signature[i]
  })));
};

// Public-key t1 fills its ten-bit coefficient range exactly. Both extremes
// are canonical encodings, even though they do not verify this official answer.
for (byte in ([0, 255] : [Nat8]).values()) {
  let rawPublic = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(1312, func _ { byte }));
  let key = switch (MLDSA.preparePublicKey(rawPublic)) {
    case (#ok key) key;
    case (#err _) Prim.trap("canonical hints: valid public encoding rejected")
  };
  assert MLDSA.verify(rawPublic, v.message, signature, v.context) == #ok(false);
  assert MLDSA.verifyPrepared(key, v.message, signature, v.context) == #ok(false);
};
