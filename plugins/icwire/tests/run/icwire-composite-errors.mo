//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";

func at<T>(result : Wire.Result<T>, kind : Text, offset : Nat) {
  switch result {
    case (#ok _) Prim.trap("expected " # kind);
    case (#err error) {
      assert error.kind == kind;
      assert Prim.nat64ToNat(error.offset) == offset;
    };
  }
};
func ok<T>(result : Wire.Result<T>) : T {
  switch result {
    case (#ok value) value;
    case (#err error) Prim.trap(debug_show error);
  }
};

// Direct composite failures must stop their parent before it constructs a
// record, option, tuple, variant or array from the failed child's placeholder.
type Choice = {#value : Null};
at(Wire.decode<Choice>("\01\ff"), "variant", 1);
at(Wire.decode<{a : Nat8; b : Choice; z : Bool}>("\07\01\02"), "variant", 2);
at(Wire.decode<(Nat8, Choice, Bool)>("\07\01\02"), "variant", 2);
at(Wire.decode<?Choice>("\01\01\ff"), "variant", 2);
at(Wire.decode<{#outer : Choice}>("\00\01\ff"), "variant", 2);
at(Wire.decode<[Choice]>("\02\00\01\ff"), "variant", 3);
at(Wire.decode<[[Choice]]>("\01\02\00\01\ff"), "variant", 4);

// None has no valid value. An absent option or empty array containing None is
// nevertheless valid, whereas an admitted payload fails at its own position.
at(Wire.decode<None>(""), "type", 0);
at(Wire.decode<?None>("\01\ff"), "type", 1);
at(Wire.decode<[None]>("\01\ff"), "type", 1);
at(Wire.decode<{#value : None}>("\00\ff"), "type", 1);
assert ok(Wire.decode<?None>("\00")) == null;
assert ok(Wire.decode<[None]>("\00")).size() == 0;

// Earlier scalar errors keep precedence over a later invalid variant, and
// count/tag failures still retain the exact first failing byte position.
at(Wire.decode<(Bool, Choice)>("\02\01"), "bool", 0);
at(Wire.decode<{a : Text; z : Choice}>("\01\ff\01"), "utf8", 0);
at(Wire.decode<?Choice>("\02\01"), "bool", 0);
at(Wire.decode<[Choice]>("\80\00\01"), "canonical", 0);
at(Wire.decode<[Choice]>("\c0\84\3d\01"), "limit", 3);
at(Wire.decode<[Choice]>("\01\00\ff"), "trailing", 2);

// No read occurs for empty records, tuples or zero-byte children. Their
// successful epilogues must still leave depth balanced for following siblings.
ignore ok(Wire.decode<{}>(""));
ok(Wire.decode<()>(""));
assert ok(Wire.decode<[()]>("\03")) == [(), (), ()];
let (_, empty, absent, byte) = ok(Wire.decode<({a : ()}, [None], ?None, Nat8)>("\00\00\09"));
assert empty.size() == 0;
assert absent == null;
assert byte == 9;
assert ok(Wire.decode<[?Choice]>("\03\00\01\00\00")) == [null, ?#value(null), null];

// Integer failures retain their absolute position after successful siblings,
// including when a previous integer needed more than a machine word. The
// literals/formulas below are independent canonical LEB boundary goldens.
func append(left : Blob, right : Blob) : Blob {
  let a = Prim.blobToArray(left);
  let b = Prim.blobToArray(right);
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(a.size() + b.size(), func i {
    if (i < a.size()) a[i] else b[i - a.size()]
  }))
};
func prefix(bytes : Blob, size : Nat) : Blob {
  let raw = Prim.blobToArray(bytes);
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func i { raw[i] }))
};
func extended(bytes : Blob, sign : Nat8) : Blob {
  let raw = Prim.blobToArray(bytes);
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(raw.size() + 1, func i {
    if (i == raw.size()) sign
    else if (i + 1 == raw.size()) raw[i] | 128 else raw[i]
  }))
};
func natBoundary(value : Nat, bytes : Blob) {
  assert ok(Wire.decode<(Nat8, Nat, Bool)>(append("\07", append(bytes, "\01")))) == (7, value, true);
  assert ok(Wire.decode<[Nat]>(append("\03\01", append(bytes, "\02")))) == [1, value, 2];
  at(Wire.decode<(Nat8, Nat, Bool)>(append("\07", append(bytes, "\02"))), "bool", bytes.size() + 1);
  at(Wire.decode<(Nat, Nat, Bool)>(append(bytes, "\80\00\02")), "canonical", bytes.size());
  at(Wire.decode<(Nat8, ?Nat, Bool)>(append("\07\01", append(extended(bytes, 0), "\02"))), "canonical", 2);
  var size = 0;
  while (size < bytes.size()) {
    at(Wire.decode<(Nat8, Nat)>(append("\07", prefix(bytes, size))), "truncated", size + 1);
    size += 1;
  };
};
func intBoundary(value : Int, bytes : Blob) {
  assert ok(Wire.decode<(Nat8, Int, Bool)>(append("\07", append(bytes, "\01")))) == (7, value, true);
  assert ok(Wire.decode<[Int]>(append("\03\01", append(bytes, "\7e")))) == [1, value, -2];
  at(Wire.decode<(Nat8, Int, Bool)>(append("\07", append(bytes, "\02"))), "bool", bytes.size() + 1);
  at(Wire.decode<(Int, Int, Bool)>(append(bytes, "\ff\7f\02")), "canonical", bytes.size());
  at(Wire.decode<(Nat8, ?Int, Bool)>(append("\07\01", append(extended(bytes, if (value < 0) 127 else 0), "\02"))), "canonical", 2);
  var size = 0;
  while (size < bytes.size()) {
    at(Wire.decode<(Nat8, Int)>(append("\07", prefix(bytes, size))), "truncated", size + 1);
    size += 1;
  };
};
var width = 1;
while (width <= 9) {
  natBoundary(2 ** (width * 7) - 1,
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(width, func i { if (i + 1 == width) 127 else 255 })));
  intBoundary(2 ** (width * 7 - 1) - 1,
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(width, func i { if (i + 1 == width) 63 else 255 })));
  intBoundary(-(2 ** (width * 7 - 1) : Int),
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(width, func i { if (i + 1 == width) 64 else 128 })));
  width += 1;
};
natBoundary(9223372036854775808, "\80\80\80\80\80\80\80\80\80\01");
intBoundary(4611686018427387904, "\80\80\80\80\80\80\80\80\c0\00");
intBoundary(-4611686018427387905, "\ff\ff\ff\ff\ff\ff\ff\ff\bf\7f");
intBoundary(-9223372036854775808, "\80\80\80\80\80\80\80\80\80\7f");
at(Wire.decode<(Bool, Nat)>("\02\80\00"), "bool", 0);
at(Wire.decode<(Bool, Int)>("\02\ff\7f"), "bool", 0);
let oversizedInteger = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(4097, func _ { 128 }));
at(Wire.decode<(Nat8, Nat)>(append("\07", oversizedInteger)), "limit", 1);
at(Wire.decode<(Nat8, Int)>(append("\07", oversizedInteger)), "limit", 1);
