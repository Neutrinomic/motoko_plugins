//MOC-FLAG --plugin /srv/shared/code/motoko_experiments/optimization-round-2/sdk/_build/compute-plugin-tests/callbacks
//MOC-FLAG --sanity-checks --force-gc
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
actor {
func rankOrder(left : Nat, right : Nat) : Int {
  if (left < right) -1 else if (left == right) 0 else 1
};
// Compare source-order ranks, not the target type's comparison implementation.
func verify<T>(values : [T], compare : (T, T) -> Int) {
  let copied = Prim.Array_tabulate<{var value : T; read : () -> T}>(values.size(), func (i : Nat) {
    let item = values[i];
    {var value = item; read = func () : T { item }}
  });
  var i = 0;
  while (i < values.size()) {
    var j = 0;
    while (j < values.size()) {
      assert compare(copied[i].value, copied[j].read()) == rankOrder(i, j);
      copied[i].value := copied[i].read();
      j += 1;
    };
    i += 1;
  };
};
type Stored = { nat8 : [Nat8]; int8 : [Int8]; nat16 : [Nat16]; int16 : [Int16]; nat32 : [Nat32]; int32 : [Int32]; char : [Char] };
transient var stored : ?Stored = null;
transient var reclaimed = 0;
public func prepare() : async () {
  let input : Stored = {
    nat8 = [0, 1, 127, 128, 254, 255];
    int8 = [-128, -127, -1, 0, 1, 127];
    nat16 = [0, 1, 32767, 32768, 65534, 65535];
    int16 = [-32768, -32767, -1, 0, 1, 32767];
    nat32 = [0, 1, 2147483647, 2147483648, 4294967294, 4294967295];
    int32 = [-2147483648, -2147483647, -1, 0, 1, 2147483647];
    char = ['\u{0}', 'a', '☃', '\u{d7ff}', '\u{e000}', '\u{ffff}', '\u{10000}', '💫', '\u{10fffe}', '\u{10ffff}'];
  };
  stored := from_candid (to_candid (input));
  assert stored != null;
};
public func churn() : async () {
  reclaimed := Prim.rts_reclaimed();
  var i = 0;
  while (i < 9) { ignore Prim.Array_init<Nat>(1024 * 1024, i); i += 1 };
};
public func check() : async () {
  await async {};
  let ?input = stored else Prim.trap("missing stored record");
  verify<Nat8>(input.nat8, func (a : Nat8, b : Nat8) : Int { Prim.fixtureCompare<Nat8>(a, b) });
  verify<Int8>(input.int8, func (a : Int8, b : Int8) : Int { Prim.fixtureCompare<Int8>(a, b) });
  verify<Nat16>(input.nat16, func (a : Nat16, b : Nat16) : Int { Prim.fixtureCompare<Nat16>(a, b) });
  verify<Int16>(input.int16, func (a : Int16, b : Int16) : Int { Prim.fixtureCompare<Int16>(a, b) });
  verify<Nat32>(input.nat32, func (a : Nat32, b : Nat32) : Int { Prim.fixtureCompare<Nat32>(a, b) });
  verify<Int32>(input.int32, func (a : Int32, b : Int32) : Int { Prim.fixtureCompare<Int32>(a, b) });
  verify<Char>(input.char, func (a : Char, b : Char) : Int { Prim.fixtureCompare<Char>(a, b) });
  assert Prim.rts_reclaimed() > reclaimed + 32 * 1024 * 1024;
};
};
//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress churn "DIDL\x00\x00"
//CALL ingress check "DIDL\x00\x00"
