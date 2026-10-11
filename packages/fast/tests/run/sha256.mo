//MOC-FLAG --package fast ../../src --plugin ../../../../dist/sha256 --sanity-checks
import SHA256 "mo:fast/SHA256";

// No other plugin is loaded when importing this module.
let digest = SHA256.digest;
assert digest("abc") ==
  "\ba\78\16\bf\8f\01\cf\ea\41\41\40\de\5d\ae\22\23\b0\03\61\a3\96\17\7a\9c\b4\10\ff\61\f2\00\15\ad";

func hash(bytes : Blob) : Blob { SHA256.digest(bytes) };
let callbacks : [Blob -> Blob] = [hash];
assert callbacks[0]("abc") == digest("abc");
