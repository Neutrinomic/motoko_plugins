//MOC-FLAG --package fast ../../src --plugin ../../../../dist/base58 --sanity-checks
import Base58 "mo:fast/Base58";
import Prim "mo:⛔";

// Bitcoin Core v29.0 src/test/data/base58_encode_decode.json (MIT).
// All 21 upstream positive vectors, including the full alphabet and 0..255.
let vectors : [(Blob, Text)] = [
  ("", ""),
  ("\61", "2g"),
  ("\62\62\62", "a3gV"),
  ("\63\63\63", "aPEr"),
  ("\73\69\6d\70\6c\79\20\61\20\6c\6f\6e\67\20\73\74\72\69\6e\67", "2cFupjhnEsSn59qHXstmK2ffpLv2"),
  ("\00\eb\15\23\1d\fc\eb\60\92\58\86\b6\7d\06\52\99\92\59\15\ae\b1\72\c0\66\47", "1NS17iag9jJgTHD1VXjvLCEnZuQ3rJDE9L"),
  ("\51\6b\6f\cd\0f", "ABnLTmg"),
  ("\bf\4f\89\00\1e\67\02\74\dd", "3SEo3LWLoPntC"),
  ("\57\2e\47\94", "3EFU7m"),
  ("\ec\ac\89\ca\d9\39\23\c0\23\21", "EJDM8drfXA6uyA"),
  ("\10\c8\51\1e", "Rt5zm"),
  ("\00\00\00\00\00\00\00\00\00\00", "1111111111"),
  ("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00", "1111111111111111111111111111111111111111"),
  ("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\01", "1111111111111111111111111111111111111112"),
  ("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\ec\39\d0\4c\37\e7\1e\5d\59\18\81\f6", "111111111111111111111111111111111111111111111111111111111111111111111111111111111111115TYzLYH1udmLdzCLM"),
  ("\00\01\11\d3\8e\5f\c9\07\1f\fc\d2\0b\4a\76\3c\c9\ae\4f\25\2b\b4\e4\8f\d6\6a\83\5e\25\2a\da\93\ff\48\0d\6d\d4\3d\c6\2a\64\11\55\a5", "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"),
  ("\00\01\02\03\04\05\06\07\08\09\0a\0b\0c\0d\0e\0f\10\11\12\13\14\15\16\17\18\19\1a\1b\1c\1d\1e\1f\20\21\22\23\24\25\26\27\28\29\2a\2b\2c\2d\2e\2f\30\31\32\33\34\35\36\37\38\39\3a\3b\3c\3d\3e\3f\40\41\42\43\44\45\46\47\48\49\4a\4b\4c\4d\4e\4f\50\51\52\53\54\55\56\57\58\59\5a\5b\5c\5d\5e\5f\60\61\62\63\64\65\66\67\68\69\6a\6b\6c\6d\6e\6f\70\71\72\73\74\75\76\77\78\79\7a\7b\7c\7d\7e\7f\80\81\82\83\84\85\86\87\88\89\8a\8b\8c\8d\8e\8f\90\91\92\93\94\95\96\97\98\99\9a\9b\9c\9d\9e\9f\a0\a1\a2\a3\a4\a5\a6\a7\a8\a9\aa\ab\ac\ad\ae\af\b0\b1\b2\b3\b4\b5\b6\b7\b8\b9\ba\bb\bc\bd\be\bf\c0\c1\c2\c3\c4\c5\c6\c7\c8\c9\ca\cb\cc\cd\ce\cf\d0\d1\d2\d3\d4\d5\d6\d7\d8\d9\da\db\dc\dd\de\df\e0\e1\e2\e3\e4\e5\e6\e7\e8\e9\ea\eb\ec\ed\ee\ef\f0\f1\f2\f3\f4\f5\f6\f7\f8\f9\fa\fb\fc\fd\fe\ff", "1cWB5HCBdLjAuqGGReWE3R3CguuwSjw6RHn39s2yuDRTS5NsBgNiFpWgAnEx6VQi8csexkgYw3mdYrMHr8x9i7aEwP8kZ7vccXWqKDvGv3u1GxFKPuAkn8JCPPGDMf3vMMnbzm6Nh9zh1gcNsMvH3ZNLmP5fSG6DGbbi2tuwMWPthr4boWwCxf7ewSgNQeacyozhKDDQQ1qL5fQFUW52QKUZDZ5fw3KXNQJMcNTcaB723LchjeKun7MuGW5qyCBZYzA1KjofN1gYBV3NqyhQJ3Ns746GNuf9N2pQPmHz4xpnSrrfCvy6TVVz5d4PdrjeshsWQwpZsZGzvbdAdN8MKV5QsBDY"),
  ("\27\1f\35\9e", "zzzzy"),
  ("\27\1f\35\9f", "zzzzz"),
  ("\27\1f\35\a0", "211111"),
  ("\27\1f\35\a1", "211112"),
];
for ((bytes, encoded) in vectors.values()) {
  assert Base58.encode(bytes) == encoded;
  assert Base58.decode(encoded) == #ok bytes;
};

// Strict alphabet: no trimming, omitted ambiguous letters, or Unicode.
for (bad in ["0", "O", "I", "l", " ", "\n", "\t", "\00", "é", "😀"].values()) {
  assert Base58.decode(bad) == #err(#invalidCharacter(0));
  assert Base58.decode("12" # bad) == #err(#invalidCharacter(2));
};
assert Base58.decode("12é0") == #err(#invalidCharacter(2));
assert Base58.decode("12\n34") == #err(#invalidCharacter(2));

func repeated(text : Text, count : Nat) : Text {
  var result = "";
  var i = 0;
  while (i < count) { result #= text; i += 1 };
  result
};
let zeros = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(4096, func(_) { 0 }));
assert Base58.decode(repeated("1", 4096)) == #ok zeros;
assert Base58.encode(zeros) == repeated("1", 4096);
assert Base58.decode(repeated("1", 4097)) == #err(#tooLarge);
assert Base58.decode(repeated("z", 5653)) == #err(#tooLarge);
assert Base58.decode(repeated("1", 5654)) == #err(#tooLarge);
// Input quota first; alphabet errors precede the decoded-output quota.
assert Base58.decode("0" # repeated("1", 5653)) == #err(#tooLarge);
assert Base58.decode(repeated("1", 4097) # "0") == #err(#invalidCharacter(4097));
assert Base58.decode(repeated("1", 5651) # "é") == #err(#invalidCharacter(5651));
assert Base58.decode(repeated("1", 5652) # "é") == #err(#tooLarge);

let encode = Base58.encode;
let decode = Base58.decode;
let codec = { encode; decode };
func identity<T>(value : T) : T = value;
let encoders = [encode, identity(encode)];
assert encoders[0]("abc") == "ZiCa";
assert encoders[1]("abc") == codec.encode("abc");
assert codec.decode("ZiCa") == #ok ("abc" : Blob);
var order = "";
assert (do { order #= "callee;"; Base58.encode })(do { order #= "argument;"; "abc" : Blob }) == "ZiCa";
assert order == "callee;argument;";
order := "";
assert (do { order #= "callee;"; Base58.decode })(do { order #= "argument;"; "ZiCa" }) == #ok ("abc" : Blob);
assert order == "callee;argument;";
