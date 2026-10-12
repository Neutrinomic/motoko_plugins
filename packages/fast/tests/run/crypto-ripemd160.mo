//MOC-FLAG --package fast ../../src --plugin ../../../../dist/ripemd160 --sanity-checks
import Hash "mo:fast/RIPEMD160";
import Prim "mo:⛔";

func bytes(n : Nat) : Blob = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(n, func(i) {
  Prim.natToNat8((i * 131 + 17) % 256)
}));
func slice(b : Blob, start : Nat, size : Nat) : Blob {
  let a = Prim.blobToArray(b);
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func(i) { a[start + i] }))
};
func set(b : Blob, offset : Nat, value : Nat8) : Blob {
  let a = Prim.blobToArray(b);
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(a.size(), func(i) {
    if (i == offset) value else a[i]
  }))
};
func must(value : ?Blob) : Blob = switch value {
  case (?b) b;
  case null Prim.trap("expected valid RIPEMD160 state");
};

assert Hash.digest("") == "\9c\11\85\a5\c5\e9\fc\54\61\28\08\97\7e\e8\f5\48\b2\25\8d\31";
assert Hash.digest("abc") == "\8e\b2\08\f7\e0\5d\98\7a\9b\04\4a\8e\98\c6\b0\87\f1\5a\0b\fc";
assert Hash.digest("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq") == "\12\a0\53\38\4a\9c\0c\88\e4\05\a0\6c\27\dc\f4\9a\da\62\eb\2b";

let initial = Hash.init();
assert initial.size() == 104;
assert Hash.finalize(initial) == ?Hash.digest("");
assert Hash.update(initial, "") == ?initial;
let a = must(Hash.update(initial, "a"));
let abc = must(Hash.update(a, "bc"));
assert Hash.finalize(abc) == ?Hash.digest("abc");
assert Hash.finalize(abc) == Hash.finalize(abc);
assert Hash.finalize(must(Hash.update(a, "def"))) == ?Hash.digest("adef");
assert Hash.finalize(a) == ?Hash.digest("a");
assert Hash.finalize(initial) == ?Hash.digest("");

// Exercise every split through both one- and two-block padding transitions.
for (size in [0, 1, 32, 55, 56, 57, 63, 64, 65, 119, 120, 127, 128, 129].values()) {
  let input = bytes(size);
  let canonical = must(Hash.update(initial, input));
  var split = 0;
  while (split <= size) {
    let left = must(Hash.update(initial, slice(input, 0, split)));
    let full = must(Hash.update(left, slice(input, split, size - split)));
    assert full == canonical;
    assert Hash.finalize(full) == ?Hash.digest(input);
    assert Hash.finalize(left) == ?Hash.digest(slice(input, 0, split));
    split += 1;
  };
};

// Malformed states are values rejected as null, including canonical padding,
// reserved bytes, initial chaining words, and the total-byte bound.
for (size in [0, 1, 20, 64, 103, 105].values()) {
  assert Hash.update(bytes(size), "abc") == null;
  assert Hash.finalize(bytes(size)) == null;
};
for (offset in [0, 3, 4, 7, 15, 16, 35, 36, 39, 40, 103].values()) {
  let invalid = set(initial, offset, 255);
  assert Hash.update(invalid, "") == null;
  assert Hash.finalize(invalid) == null;
};
// A maximum-length synthetic state is structurally valid, but cannot grow.
var limit = initial;
var i = 8;
while (i < 15) { limit := set(limit, i, 255); i += 1 };
limit := set(limit, 15, 31);
assert Hash.finalize(limit) != null;
assert Hash.update(limit, "") == ?limit;
assert Hash.update(limit, "a") == null;

let stream = Hash.Digest();
assert stream.write("ab");
assert stream.sum() == Hash.digest("ab");
assert stream.write("c");
assert stream.sum() == Hash.digest("abc");
assert stream.sum() == Hash.digest("abc");
stream.reset();
assert stream.sum() == Hash.digest("");

let alias = Hash.digest;
let ops = { hash = alias };
assert ops.hash("abc") == Hash.digest("abc");
func callback(b : Blob) : Blob = Hash.digest(b);
let callbacks : [Blob -> Blob] = [callback];
assert callbacks[0]("abc") == Hash.digest("abc");
var order = "";
let result = (do { order #= "callee;"; Hash.update })(
  do { order #= "state;"; initial }, do { order #= "input;"; "abc" : Blob }
);
assert order == "callee;state;input;";
assert Hash.finalize(must(result)) == ?Hash.digest("abc");
