//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";

func at<T>(result : Wire.Result<T>, kind : Text, offset : Nat) {
  switch result {
    case (#ok _) Prim.trap("expected " # kind # " at " # debug_show offset);
    case (#err error) assert error == {kind; offset = Prim.natToNat64(offset)};
  }
};
func both<T>(compact : Wire.Result<T>, speed : Wire.Result<T>, kind : Text, offset : Nat) {
  at(compact, kind, offset); at(speed, kind, offset);
};

// A failed shared scalar helper must return through every enclosing visitor
// before a parent can consume its placeholder or advance to a later error.
type Choice = {#value : Null};
both(Wire.Compact.decode<(Bool, Choice)>("\02\01"), Wire.Speed.decode<(Bool, Choice)>("\02\01"), "bool", 0);
both(Wire.Compact.decode<{a : Text; z : Choice}>("\01\ff\01"), Wire.Speed.decode<{a : Text; z : Choice}>("\01\ff\01"), "utf8", 0);
both(Wire.Compact.decode<?Bool>("\01\02\ff"), Wire.Speed.decode<?Bool>("\01\02\ff"), "bool", 1);
both(Wire.Compact.decode<[{a : Bool; z : Choice}]>("\02\01\00\02\01"), Wire.Speed.decode<[{a : Bool; z : Choice}]>("\02\01\00\02\01"), "bool", 3);
both(Wire.Compact.decode<(Nat8, Nat, Bool)>("\07\80\00\02"), Wire.Speed.decode<(Nat8, Nat, Bool)>("\07\80\00\02"), "canonical", 1);
both(Wire.Compact.decode<(Nat8, Int, Bool)>("\07\ff\7f\02"), Wire.Speed.decode<(Nat8, Int, Bool)>("\07\ff\7f\02"), "canonical", 1);
both(Wire.Compact.decode<(Nat8, Char, Bool)>("\07\00\d8\00\00\02"), Wire.Speed.decode<(Nat8, Char, Bool)>("\07\00\d8\00\00\02"), "char", 1);
both(Wire.Compact.decode<(Nat8, Float, Bool)>("\07\00\00\00\00\00\00\f0\7f\02"), Wire.Speed.decode<(Nat8, Float, Bool)>("\07\00\00\00\00\00\00\f0\7f\02"), "float", 1);
both(Wire.Compact.decode<(Nat8, Float32, Bool)>("\07\00\00\c0\7f\02"), Wire.Speed.decode<(Nat8, Float32, Bool)>("\07\00\00\c0\7f\02"), "float", 1);
both(Wire.Compact.decode<(Nat8, Nat64)>("\07\01\02\03"), Wire.Speed.decode<(Nat8, Nat64)>("\07\01\02\03"), "truncated", 1);
both(Wire.Compact.decode<(Nat8, Blob, Bool)>("\07\03ab"), Wire.Speed.decode<(Nat8, Blob, Bool)>("\07\03ab"), "truncated", 2);
both(Wire.Compact.decode<(Nat8, Principal, Bool)>("\07\1e\02"), Wire.Speed.decode<(Nat8, Principal, Bool)>("\07\1e\02"), "principal", 1);
type Remote = actor {read : shared query () -> async Nat};
type Callback = shared icwire (Nat) -> async Nat;
both(Wire.Compact.decode<(Nat8, Remote, Bool)>("\07\1e\02"), Wire.Speed.decode<(Nat8, Remote, Bool)>("\07\1e\02"), "principal", 1);
both(Wire.Compact.decode<(Nat8, Callback, Bool)>("\07\00\01\ff\02"), Wire.Speed.decode<(Nat8, Callback, Bool)>("\07\00\01\ff\02"), "utf8", 2);
both(Wire.Compact.decode<(Nat8, Null)>("\07\00"), Wire.Speed.decode<(Nat8, Null)>("\07\00"), "trailing", 1);
both(Wire.Compact.decode<(Nat8, None, Bool)>("\07\02"), Wire.Speed.decode<(Nat8, None, Bool)>("\07\02"), "type", 1);

// Root general decoding retains the distinctions between empty values,
// successful nullable payloads, and an absent outer Optional result.
assert Wire.Compact.decode<()>("") == #ok ();
assert Wire.Compact.decode<{}>("") == #ok {};
assert Wire.Compact.decodeOptional<Null>("") == ?null;
assert Wire.Compact.decodeOptional<?Null>("\00") == ?null;
assert Wire.Compact.decodeOptional<?Null>("\01") == ??null;
assert Wire.Compact.decodeOptional<??Null>("\01\01") == ???null;
assert Wire.Compact.decodeOptional<??Null>("\01\02") == null;
assert Wire.Compact.decodeOptional<Bool>("\02") == null;
assert Wire.Compact.decode<Blob>("\00") == #ok "";
assert Wire.Compact.decode<Text>("\00") == #ok "";
assert Wire.Compact.decode<Principal>("\00") == #ok (Prim.principalOfBlob(""));
assert Wire.Compact.decode<[{a : (); z : ?Null}]>("\02\00\00") == #ok([{a = (); z = null}, {a = (); z = null}]);
switch (Wire.Compact.decode<([()], [None], ?None, Nat8)>("\03\00\00\09")) {
  case (#ok (units, nonValues, noneValue, byte)) {
    assert units == [(), (), ()];
    assert nonValues.size() == 0;
    assert noneValue == null;
    assert byte == 9;
  };
  case (#err error) Prim.trap(debug_show error);
};

// The physical object can be wider and can contain cells and local functions;
// only the immutable fields of the selected wire schema may be read.
type Narrow = {_1_ : Nat8; _3_ : Text; _5_ : Nat};
let golden : Blob = "\11\02ok\ac\02";
func narrow(value : Narrow) {
  assert Wire.Compact.encode(value) == #ok golden;
  assert Wire.Speed.encode(value) == #ok golden;
  assert Wire.Compact.encodeOrTrap(value) == golden;
  assert Wire.Compact.encodeBounded(value, golden.size()) == #ok golden;
  assert Wire.Compact.encodeBoundedOrTrap(value, golden.size()) == golden;
  assert Wire.Compact.estimateSize(value) == golden.size();
  assert Wire.Speed.estimateSize(value) == golden.size();
  assert Wire.Compact.decode<Narrow>(golden) == #ok value;
  assert Wire.Compact.decodeOptional<Narrow>(golden) == ?value;
  assert Wire.Compact.decodeOrTrap<Narrow>(golden) == value;
  both(Wire.Compact.encodeBounded(value, 5), Wire.Speed.encodeBounded(value, 5), "limit", 4);
};
let exact : Narrow = {_1_ = 17; _3_ = "ok"; _5_ = 300};
let wide = object {
  public var _0_ = 91;
  public let _1_ : Nat8 = 17;
  public let _2_ = func() : Nat {999};
  public let _3_ = "ok";
  public var _4_ = "extra";
  public let _5_ = 300;
  public let _6_ = [false, true];
};
narrow(exact); narrow(wide);
wide._0_ := 92; wide._4_ := "changed";
narrow(wide);

// Numeric labels use unsigned wire ordering. Generic object lookup must still
// respect the SDK heap's order, which also contains escaped lexical labels.
func escaped(value : {x_ : Nat8; _0_ : Text; _4294967295_ : Nat8}) {
  assert Wire.Compact.encodeOrTrap(value) == "\02ok\03\04";
  assert Wire.Speed.encodeOrTrap(value) == "\02ok\03\04";
  assert Wire.Compact.estimateSize(value) == 5;
};
let namedWide = {_0_ = "ok"; x_ = 3 : Nat8; xx = false; _4294967295_ = 4 : Nat8};
escaped(namedWide);

// Boxed integers cross both managed-limb and LEB boundaries. Expected bytes
// are arithmetic goldens, independent of either generated visitor.
func repeated(width : Nat, body : Nat8, last : Nat8) : Blob {
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(width, func i {if (i + 1 == width) last else body}))
};
for (width in [9, 10, 18, 19, 127, 4095, 4096].values()) {
  let natural : Nat = 2 ** (width * 7) - 1;
  let positive : Int = 2 ** (width * 7 - 1) - 1;
  let negative : Int = -(positive + 1);
  let natBytes = repeated(width, 255, 127);
  let positiveBytes = repeated(width, 255, 63);
  let negativeBytes = repeated(width, 128, 64);
  assert Wire.Compact.encode(natural) == #ok natBytes;
  assert Wire.Speed.encode(natural) == #ok natBytes;
  assert Wire.Compact.encode(positive) == #ok positiveBytes;
  assert Wire.Speed.encode(positive) == #ok positiveBytes;
  assert Wire.Compact.encode(negative) == #ok negativeBytes;
  assert Wire.Speed.encode(negative) == #ok negativeBytes;
  assert Wire.Compact.encodeBounded(natural, width) == #ok natBytes;
  assert Wire.Compact.encodeBounded(negative, width) == #ok negativeBytes;
  assert Wire.Compact.estimateSize(natural) == width;
  assert Wire.Compact.estimateSize(positive) == width;
  assert Wire.Compact.estimateSize(negative) == width;
  assert Wire.Compact.decode<Nat>(natBytes) == #ok natural;
  assert Wire.Compact.decode<Int>(positiveBytes) == #ok positive;
  assert Wire.Compact.decode<Int>(negativeBytes) == #ok negative;
  both(Wire.Compact.encodeBounded((7 : Nat8, negative), width), Wire.Speed.encodeBounded((7 : Nat8, negative), width), "limit", 1);
};
let excessiveNat : Nat = 2 ** (4096 * 7);
let excessiveInt : Int = 2 ** (4096 * 7 - 1);
both(Wire.Compact.encode(excessiveNat), Wire.Speed.encode(excessiveNat), "limit", 0);
both(Wire.Compact.encode(excessiveInt), Wire.Speed.encode(excessiveInt), "limit", 0);
both(Wire.Compact.encode(-excessiveInt - 1), Wire.Speed.encode(-excessiveInt - 1), "limit", 0);
both(Wire.Compact.encode((7 : Nat8, excessiveNat)), Wire.Speed.encode((7 : Nat8, excessiveNat)), "limit", 1);
let rejected : Nat = 2_305_843_009_213_693_951;
assert Wire.Compact.estimateSize(excessiveNat) == rejected;
assert Wire.Compact.estimateSize(excessiveInt) == rejected;
assert Wire.Compact.estimateSize(-excessiveInt - 1) == rejected;
both(Wire.Compact.encodeBounded(1 : Nat, 2 ** 80), Wire.Speed.encodeBounded(1 : Nat, 2 ** 80), "limit", 0);

// A late non-finite float retains the first error after successful variable
// data; sizing deliberately remains a byte bound without float validation.
let lateFloat = (7 : Nat8, "abc" : Text, 0.0 / 0.0 : Float);
both(Wire.Compact.encode(lateFloat), Wire.Speed.encode(lateFloat), "float", 5);
both(Wire.Compact.encodeBounded(lateFloat, 4), Wire.Speed.encodeBounded(lateFloat, 4), "limit", 1);
both(Wire.Compact.encodeBounded(lateFloat, 5), Wire.Speed.encodeBounded(lateFloat, 5), "float", 5);
assert Wire.Compact.estimateSize(lateFloat) == 13;
assert Wire.Speed.estimateSize(lateFloat) == 13;

// Static and recursive depth helpers can coexist for the same leaf types.
type Chain = ?(Nat8, Chain);
func chain(n : Nat) : Chain {
  var value : Chain = null;
  var remaining = n;
  while (remaining > 0) {value := ?(8, value); remaining -= 1};
  value
};
let allowed = chain(63);
let chainBytes = Wire.Speed.encodeOrTrap(allowed);
assert Wire.Compact.encodeOrTrap(allowed) == chainBytes;
assert Wire.Compact.decodeOrTrap<Chain>(chainBytes) == allowed;
assert Wire.Compact.estimateSize(allowed) == 127;
assert Wire.Compact.estimateSize(chain(64)) == rejected;
both(Wire.Compact.encode(chain(64)), Wire.Speed.encode(chain(64)), "limit", 127);
type Nest = {#next : Nest; #end : [Nat8]};
func nest(n : Nat, values : [Nat8]) : Nest {
  var value : Nest = #end(values);
  var remaining = n;
  while (remaining > 0) {value := #next(value); remaining -= 1};
  value
};
let deepEmpty = nest(126, []);
assert Wire.Compact.encode(deepEmpty) == Wire.Speed.encode(deepEmpty);
assert Wire.Compact.decodeOrTrap<Nest>(Wire.Compact.encodeOrTrap(deepEmpty)) == deepEmpty;
assert Wire.Compact.estimateSize(deepEmpty) == 128;
both(Wire.Compact.encode(nest(126, [1])), Wire.Speed.encode(nest(126, [1])), "limit", 128);
both(Wire.Compact.encode(nest(127, [])), Wire.Speed.encode(nest(127, [])), "limit", 128);
let tooMany = Prim.Array_tabulate<Null>(1_000_000, func _ {null});
assert Wire.Compact.estimateSize(tooMany) == rejected;
both(Wire.Compact.encodeBounded(tooMany, 3), Wire.Speed.encodeBounded(tooMany, 3), "limit", 0);

// Every intrinsic argument is evaluated once, left-to-right, even on failure.
var visits = 0;
assert Wire.Compact.encode(do {visits += 1; 7 : Nat8}) == #ok "\07";
assert visits == 1;
assert Wire.Compact.encodeOrTrap(do {visits += 1; 7 : Nat8}) == "\07";
assert visits == 2;
assert Wire.Compact.estimateSize(do {visits += 1; 7 : Nat8}) == 1;
assert visits == 3;
assert Wire.Compact.encodeBounded(do {visits += 1; 7 : Nat8}, do {assert visits == 4; visits += 1; 1}) == #ok "\07";
assert visits == 5;
assert Wire.Compact.encodeBoundedOrTrap(do {visits += 1; 7 : Nat8}, do {assert visits == 6; visits += 1; 1}) == "\07";
assert visits == 7;
assert Wire.Compact.decode<Nat8>(do {visits += 1; "\07"}) == #ok 7;
assert visits == 8;
assert Wire.Compact.decodeOptional<Nat8>(do {visits += 1; "\07"}) == ?7;
assert visits == 9;
assert Wire.Compact.decodeOrTrap<Nat8>(do {visits += 1; "\07"}) == 7;
assert visits == 10;
at(Wire.Compact.encodeBounded(do {visits += 1; 7 : Nat8}, do {assert visits == 11; visits += 1; 0}), "limit", 0);
assert visits == 12;

// Recoverable failures discard their context before a later successful call.
for (_ in [0, 1, 2, 3].values()) {
  assert Wire.Compact.decodeOptional<(Bool, Choice)>("\02\01") == null;
  assert Wire.Compact.decode<Narrow>(golden) == #ok exact;
  assert Wire.Speed.decode<Narrow>(golden) == #ok exact;
  assert Wire.Compact.encodeOrTrap(exact) == golden;
};
