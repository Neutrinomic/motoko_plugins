//MOC-FLAG --package fast ../../src --package core ../../.mops/core@2.5.0/src --plugin ../../../../dist/base58 --plugin ../../../../dist/sha256 --sanity-checks
import Base58Check "mo:fast/Base58Check";
import Prim "mo:⛔";

// Fixed answers independently computed using Python hashlib double-SHA256
// and integer division by 58; includes genesis address and secret-1 WIF.
let vectors : [(Blob, Text)] = [
  ("", "3QJmnh"),
  ("\00", "1Wh4bh"),
  ("\00\00\00", "11146EAsf"),
  ("\00\01\09\66\77\60\06\95\3d\55\67\43\9e\5e\39\f8\6a\0d\27\3b\ee", "16UwLL9Risc3QfPqBUvKofHmBQ7wMtjvM"),
  ("\00\62\e9\07\b1\5c\bf\27\d5\42\53\99\eb\f6\f0\fb\50\eb\b8\8f\18", "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"),
  ("\80\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01", "5HpHagT65TZzG1PH3CSu63k8DbpvD8s5ip4nEB3kEsreAnchuDf"),
  ("\80\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01\01", "KwDiBf89QgGbjEhKnhXJuH7LrciVrZi3qYjgd9M7rFU73sVHnoWn"),
  ("\ff\00\80\ff", "jeqdndumPmu"),
];
for ((payload, encoded) in vectors.values()) {
  assert Base58Check.encode(payload) == encoded;
  assert Base58Check.decode(encoded) == #ok payload;
};
for (short in ["", "1", "11", "111"].values()) {
  assert Base58Check.decode(short) == #err(#tooShort);
};
assert Base58Check.decode("1111") == #err(#invalidChecksum);
assert Base58Check.decode("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNb") == #err(#invalidChecksum);
assert Base58Check.decode("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfN0") == #err(#invalidCharacter(33));
assert Base58Check.decode(" ") == #err(#invalidCharacter(0));
assert Base58Check.decode("é") == #err(#invalidCharacter(0));

let maxPayload = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(4092, func(_) { 0 }));
assert Base58Check.decode(Base58Check.encode(maxPayload)) == #ok maxPayload;
var tooLong = "";
var i = 0;
while (i < 5654) { tooLong #= "1"; i += 1 };
assert Base58Check.decode(tooLong) == #err(#tooLarge);
let encode : Blob -> Text = Base58Check.encode;
assert encode("abc") == Base58Check.encode("abc");
var order = "";
assert (do { order #= "callee;"; Base58Check.encode })(do { order #= "argument;"; "abc" : Blob }) == encode("abc");
assert order == "callee;argument;";
