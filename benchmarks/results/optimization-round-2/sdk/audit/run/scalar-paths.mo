//MOC-FLAG --plugin /srv/shared/code/motoko_experiments/optimization-round-2/sdk/_build/compute-plugin-tests/callbacks
//MOC-FLAG --sanity-checks
import Prim "mo:⛔";
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
type AliasNat8 = Nat8;
verify<AliasNat8>([0, 1, 127, 128, 254, 255], func (a : AliasNat8, b : AliasNat8) : Int { Prim.fixtureCompare<AliasNat8>(a, b) });
type AliasInt8 = Int8;
verify<AliasInt8>([-128, -127, -1, 0, 1, 127], func (a : AliasInt8, b : AliasInt8) : Int { Prim.fixtureCompare<AliasInt8>(a, b) });
type AliasNat16 = Nat16;
verify<AliasNat16>([0, 1, 32767, 32768, 65534, 65535], func (a : AliasNat16, b : AliasNat16) : Int { Prim.fixtureCompare<AliasNat16>(a, b) });
type AliasInt16 = Int16;
verify<AliasInt16>([-32768, -32767, -1, 0, 1, 32767], func (a : AliasInt16, b : AliasInt16) : Int { Prim.fixtureCompare<AliasInt16>(a, b) });
type AliasNat32 = Nat32;
verify<AliasNat32>([0, 1, 2147483647, 2147483648, 4294967294, 4294967295], func (a : AliasNat32, b : AliasNat32) : Int { Prim.fixtureCompare<AliasNat32>(a, b) });
type AliasInt32 = Int32;
verify<AliasInt32>([-2147483648, -2147483647, -1, 0, 1, 2147483647], func (a : AliasInt32, b : AliasInt32) : Int { Prim.fixtureCompare<AliasInt32>(a, b) });
type AliasChar = Char;
verify<AliasChar>(['\u{0}', 'a', '☃', '\u{d7ff}', '\u{e000}', '\u{ffff}', '\u{10000}', '💫', '\u{10fffe}', '\u{10ffff}'], func (a : AliasChar, b : AliasChar) : Int { Prim.fixtureCompare<AliasChar>(a, b) });
// Exercise arithmetic/bit conversions before the plugin boundary as well.
let high : Nat32 = 2147483648;
let low : Int32 = -2147483648;
assert Prim.fixtureCompare<Nat32>((high >> 31), high +% 2147483647) == -1;
assert Prim.fixtureCompare<Int32>((low >> 31), low +% 1) == 1;
