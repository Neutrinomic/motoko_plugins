//MOC-FLAG --package fast ../../../../packages/fast/src --plugin ../../../../dist/bls12-381 --sanity-checks
import B "mo:fast/BLS12381";
import Prim "mo:⛔";

func copies(n : Nat, blob : Blob) : [Blob] {
  Prim.Array_tabulate<Blob>(n, func(_) { blob })
};
func messages(n : Nat) : [Blob] {
  Prim.Array_tabulate<Blob>(n, func(i) {
    Prim.arrayToBlob([Prim.natToNat8(i)])
  })
};

// Shape and bounded-descriptor checks precede point decoding.
assert B.aggregateVerifyIC([], [], "") == #err(#emptyBatch);
assert B.aggregateVerifyEthereum([], [], [], "") == #err(#emptyBatch);
assert B.fastAggregateVerifyEthereum([], [], "", "") == #err(#emptyBatch);
assert B.aggregateVerifyIC([], [""], "") == #err(#invalidLength);
assert B.aggregateVerifyEthereum([], [""], [], "") == #err(#invalidLength);
assert B.aggregateVerifyEthereum([""], [""], [], "") == #err(#invalidLength);
assert B.fastAggregateVerifyEthereum([], [""], "", "") == #err(#invalidLength);
assert B.aggregateVerifyIC(copies(128, ""), messages(128), "") == #err(#tooManyItems);
assert B.aggregateVerifyIC(copies(128, ""), [], "") == #err(#invalidLength);
assert B.aggregateVerifyEthereum(copies(128, ""), copies(128, ""), messages(128), "") == #err(#tooManyItems);
assert B.aggregateVerifyEthereum(copies(128, ""), [], messages(128), "") == #err(#invalidLength);
assert B.fastAggregateVerifyEthereum(copies(129, ""), copies(129, ""), "", "") == #err(#tooManyItems);
assert B.fastAggregateVerifyEthereum(copies(129, ""), [], "", "") == #err(#invalidLength);

// Maximum accepted counts reach the profile's cryptographic validation.
assert B.aggregateVerifyIC(copies(127, ""), messages(127), B.g1Identity) == #err(#identity);
assert B.aggregateVerifyEthereum(copies(127, ""), copies(127, ""), messages(127), B.g2Identity) == #err(#identity);
assert B.fastAggregateVerifyEthereum(copies(128, B.g1Identity), copies(128, B.g2Identity), "", "") == #err(#identity);

// These precedence rules are shared by the interpreter and Wasm profiles.
assert B.aggregateVerifyIC(["", ""], ["same", "same"], "") == #err(#duplicateMessage);
assert B.aggregateVerifyIC([""], [""], B.g1Identity) == #err(#identity);
assert B.aggregateVerifyEthereum([""], [""], [""], B.g2Identity) == #err(#identity);
assert B.fastAggregateVerifyEthereum([B.g1Identity], [""], "", B.g2Identity) == #err(#invalidLength);
assert B.fastAggregateVerifyEthereum([B.g1Identity], [B.g2Identity], "", "") == #err(#identity);

// Ordinary argument expressions retain left-to-right, exactly-once evaluation.
var order : Nat = 0;
func arrayArg(expected : Nat) : [Blob] {
  assert order == expected;
  order += 1;
  []
};
func blobArg(expected : Nat) : Blob {
  assert order == expected;
  order += 1;
  ""
};
assert B.aggregateVerifyEthereum(arrayArg(0), arrayArg(1), arrayArg(2), blobArg(3)) == #err(#emptyBatch);
assert order == 4;
