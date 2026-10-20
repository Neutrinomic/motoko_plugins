//MOC-FLAG --plugin ../../../../dist/sha256
import Prim "mo:⛔";

// SHA-256 known answers and padding transitions at 55/56 and 63/64 bytes.
assert Prim.sha256("") ==
  "\e3\b0\c4\42\98\fc\1c\14\9a\fb\f4\c8\99\6f\b9\24\27\ae\41\e4\64\9b\93\4c\a4\95\99\1b\78\52\b8\55";
assert Prim.sha256("abc") ==
  "\ba\78\16\bf\8f\01\cf\ea\41\41\40\de\5d\ae\22\23\b0\03\61\a3\96\17\7a\9c\b4\10\ff\61\f2\00\15\ad";
// The 32-byte specialization must match the reference implementation too.
assert Prim.sha256("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") ==
  "\3b\a3\f5\f4\3b\92\60\26\83\c1\9a\ee\62\a2\03\42\b0\84\dd\59\71\dd\d3\38\08\d8\1a\32\88\79\a5\47";
assert Prim.sha256("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") ==
  "\24\8d\6a\61\d2\06\38\b8\e5\c0\26\93\0c\3e\60\39\a3\3c\e4\59\64\ff\21\67\f6\ec\ed\d4\19\db\06\c1";
assert Prim.sha256("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") ==
  "\9f\43\90\f8\d3\0c\2d\d9\2e\c9\f0\95\b6\5e\2b\9a\e9\b0\a9\25\a5\25\8e\24\1c\9f\1e\91\0f\73\43\18";
assert Prim.sha256("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") ==
  "\b3\54\39\a4\ac\6f\09\48\b6\d6\f9\e3\c6\af\0f\5f\59\0c\e2\0f\1b\de\70\90\ef\79\70\68\6e\c6\73\8a";
assert Prim.sha256("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") ==
  "\7d\3e\74\a0\5d\7d\b1\5b\ce\4a\d9\ec\06\58\ea\98\e3\f0\6e\ee\cf\16\b4\c6\ff\f2\da\45\7d\dc\2f\34";
assert Prim.sha256("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") ==
  "\ff\e0\54\fe\7a\e0\cb\6d\c6\5c\3a\f9\b6\1d\52\09\f4\39\85\1d\b4\3d\0b\a5\99\73\37\df\15\46\68\eb";
assert Prim.sha256("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") ==
  "\63\53\61\c4\8b\b9\ea\b1\41\98\e7\6e\a8\ab\7f\1a\41\68\5d\6a\d6\2a\a9\14\6d\30\1d\4f\17\eb\0a\e0";

// Inferred aliases preserve specialization. Explicit wrappers are ordinary
// Motoko functions and can be stored or passed as callbacks.
let hash = Prim.sha256;
assert hash("abc") == Prim.sha256("abc");
func apply(hash : Blob -> Blob, data : Blob) : Blob = hash(data);
func digest(data : Blob) : Blob { Prim.sha256(data) };
assert apply(digest, "abc") == Prim.sha256("abc");
let callbacks : [Blob -> Blob] = [func(data) { hash(data) }, digest];
assert callbacks[1]("abc") == callbacks[0]("abc");

// Segmentation preserves byte concatenation, including empty and crossing parts.
assert Prim.sha256_parts([]) == hash("");
assert Prim.sha256_parts(["", "a", "", "bc", ""]) == hash("abc");
let partsHash = Prim.sha256_parts;
assert partsHash(["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "a"]) ==
  hash("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
assert partsHash(["aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", "aa"]) ==
  hash("aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa");
func joinedHash(parts : [Blob]) : Blob { partsHash(parts) };
func applyParts(hash : [Blob] -> Blob, parts : [Blob]) : Blob {hash(parts)};
assert applyParts(joinedHash, ["ab", "c"]) == hash("abc");

// A returned result remains valid across later calls and allocations.
let saved = Prim.sha256("abc");
var i = 0;
while (i < 100) {
  assert Prim.sha256("a") ==
    "\ca\97\81\12\ca\1b\bd\ca\fa\c2\31\b3\9a\23\dc\4d\a7\86\ef\f8\14\7c\4e\72\b9\80\77\85\af\ee\48\bb";
  i += 1;
};
assert saved == digest("abc");

// Compressed SEC1 public keys use the shared 32/33-byte padding path.
assert Prim.sha256("\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98") == "\0f\71\5b\af\5d\4c\2e\d3\29\78\5c\ef\29\e5\62\f7\34\88\c8\a2\bb\9d\bc\57\00\b3\61\d5\4b\9b\05\54";
assert Prim.sha256("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00") == "\7f\9c\9e\31\ac\82\56\ca\2f\25\85\83\df\26\2d\bc\7d\6f\68\f2\a0\30\43\d5\c9\9a\4a\e5\a7\39\6c\e9";
assert Prim.sha256("\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff") == "\ff\b8\b6\e2\7a\06\ff\b9\8e\cf\60\d2\61\a6\81\8c\dc\57\3f\82\56\f0\64\29\00\0a\2b\12\5b\07\0c\37";
