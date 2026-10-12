//MOC-FLAG --package fast ../../src --plugin ../../../../dist/blake3 --sanity-checks
import Prim "mo:⛔";
import BLAKE3 "mo:fast/BLAKE3";

func must(result : BLAKE3.Result<Blob>) : Blob {
  switch result { case (#ok(value)) value; case (#err(_)) { assert false; "" } }
};
let key : Blob = "whats the Elvish word for friend";
// Independently generated with upstream blake3 1.8.7 OutputReader.
assert BLAKE3.xof("abc", 18_446_744_073_709_551_484, 131) == #ok("\d2\0b\a2\a4\69\94\4f\e8\bf\68\a1\09\cd\d6\49\bb\82\73\5d\0b\be\8c\16\bf\fd\1c\7c\86\dc\eb\9d\c2\13\f5\1a\6e\8b\55\82\73\7d\68\3e\de\79\16\9e\43\ad\15\2b\45\ef\db\4a\3d\60\b4\8a\d0\2e\c9\0d\3f\19\c6\d6\59\3d\fc\72\f2\18\65\e6\ef\61\8a\81\70\83\19\1e\dd\5a\67\33\fa\db\5d\3b\d3\27\46\db\ad\71\35\27\54\ec\b2\67\82\fd\46\2f\41\39\a3\77\9c\ed\e7\f5\42\82\34\55\91\b5\95\b6\6b\52\ef\72\f2\3a\02\58");
let initial = BLAKE3.new();
assert BLAKE3.keyedHash("", "abc") == #err(#invalidKey);
assert BLAKE3.newKeyed("short") == #err(#invalidKey);
assert BLAKE3.finalize("") == #err(#invalidState);
assert BLAKE3.update("wrong", "abc") == #err(#invalidState);
assert BLAKE3.xof("abc", 0, 16_777_217) == #err(#outputTooLarge);
assert BLAKE3.xof("abc", 18_446_744_073_709_551_615, 1) == #err(#invalidSeek);
assert BLAKE3.xof("abc", 18_446_744_073_709_551_615, 0) == #ok("");
assert BLAKE3.finalizeXof(initial, 18_446_744_073_709_551_615, 0) == #ok("");
assert BLAKE3.finalizeXof("bad", 18_446_744_073_709_551_615, 1) == #err(#invalidSeek);
assert BLAKE3.finalizeXof("bad", 18_446_744_073_709_551_615, 16_777_217) == #err(#outputTooLarge);
let initialBytes = Prim.blobToArray(initial);
for ((offset, byte) in ([(0, 0), (4, 32), (5, 1), (8, 1), (40, 1), (47, 64), (49, 5), (50, 1), (51, 1), (64, 1), (1088, 1), (2815, 1)] : [(Nat, Nat8)]).values()) {
  let malformed = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(2816, func(i) {
    if (i == offset) byte else initialBytes[i]
  }));
  assert BLAKE3.update(malformed, "x") == #err(#invalidState);
  assert BLAKE3.finalize(malformed) == #err(#invalidState);
};
let full = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(2816, func(i) {
  if (i >= 40 and i < 46) 255
  else if (i == 46) 63
  else if (i == 48) 255
  else if (i == 49) 3
  else if (i == 50) 54
  else initialBytes[i]
}));
assert BLAKE3.update(full, "x") == #err(#inputTooLong);
let prefix = must(BLAKE3.update(initial, "prefix"));
let left = must(BLAKE3.update(prefix, "left"));
let right = must(BLAKE3.update(prefix, "right"));
assert must(BLAKE3.finalize(prefix)) == BLAKE3.digest("prefix");
assert must(BLAKE3.finalize(left)) == BLAKE3.digest("prefixleft");
assert must(BLAKE3.finalize(right)) == BLAKE3.digest("prefixright");
assert BLAKE3.deriveKey("application A", "secret") != BLAKE3.deriveKey("application B", "secret");
assert BLAKE3.deriveKey("unicode λ context", "secret") == must(BLAKE3.finalize(must(BLAKE3.update(BLAKE3.newDeriveKey("unicode λ context"), "secret"))));
var order = "";
ignore BLAKE3.keyedHash(do { order #= "key;"; key }, do { order #= "data;"; "abc" : Blob });
assert order == "key;data;";
func ordinaryHash(input : Blob) : Blob { BLAKE3.digest(input) };
let callback : Blob -> Blob = ordinaryHash;
assert callback("abc") == BLAKE3.digest("abc");
