//MOC-FLAG --package fast ../../src --plugin ../../../../dist/sha256 --sanity-checks
import SHA256 "mo:fast/SHA256";

// No other plugin is loaded when importing this module.
let digest = SHA256.digest;
assert digest("abc") ==
  "\ba\78\16\bf\8f\01\cf\ea\41\41\40\de\5d\ae\22\23\b0\03\61\a3\96\17\7a\9c\b4\10\ff\61\f2\00\15\ad";

func hash(bytes : Blob) : Blob { SHA256.digest(bytes) };
let callbacks : [Blob -> Blob] = [hash];
assert callbacks[0]("abc") == digest("abc");

// Compressed SEC1 public keys use the shared 32/33-byte padding path.
assert SHA256.digest("\02\79\be\66\7e\f9\dc\bb\ac\55\a0\62\95\ce\87\0b\07\02\9b\fc\db\2d\ce\28\d9\59\f2\81\5b\16\f8\17\98") == "\0f\71\5b\af\5d\4c\2e\d3\29\78\5c\ef\29\e5\62\f7\34\88\c8\a2\bb\9d\bc\57\00\b3\61\d5\4b\9b\05\54";
assert SHA256.digest("\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00") == "\7f\9c\9e\31\ac\82\56\ca\2f\25\85\83\df\26\2d\bc\7d\6f\68\f2\a0\30\43\d5\c9\9a\4a\e5\a7\39\6c\e9";
assert SHA256.digest("\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff\ff") == "\ff\b8\b6\e2\7a\06\ff\b9\8e\cf\60\d2\61\a6\81\8c\dc\57\3f\82\56\f0\64\29\00\0a\2b\12\5b\07\0c\37";
