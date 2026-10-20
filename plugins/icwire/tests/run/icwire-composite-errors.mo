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
