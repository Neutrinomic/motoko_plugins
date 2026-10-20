//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";

type Small = {_1_ : Nat8; _3_ : Text; _5_ : Nat};
type Alias = Small;
let golden : Blob = "\11\02ok\ac\02";
// The argument's concrete wire schema stays narrow even when its physical
// object has additional fields before, between and after those it projects.
func check(value : Alias) {
  assert Wire.estimateSize(value) == golden.size();
  assert Wire.encode(value) == #ok golden;
  assert Wire.encodeOrTrap(value) == golden;
  assert Wire.encodeBounded(value, golden.size()) == #ok golden;
  assert Wire.encodeBoundedOrTrap(value, golden.size()) == golden;
  assert Wire.encodeBounded(value, 5) == #err({kind = "limit"; offset = 4});
  assert Wire.decode<Alias>(golden) == #ok value;
  assert Wire.decodeOptional<Alias>(golden) == ?value;
  assert Wire.decodeOrTrap<Alias>(golden) == value;
};
let exact : Small = {_1_ = 17; _3_ = "ok"; _5_ = 300};
let wider = {_0_ = false; _1_ = 17 : Nat8; _2_ = "before"; _3_ = "ok";
  _4_ = "\04"; _5_ = 300; _6_ = [1, 2, 3]};
check(exact); check(wider);
// Width subtyping can hide non-shared physical fields as well. The logical
// payload remains an immutable shared record, and extra cells are not read.
let withCell = object {
  public var _0_ = 0;
  public let _1_ : Nat8 = 17;
  public let _2_ = func() : Nat {999};
  public let _3_ = "ok";
  public var _4_ = "extra";
  public let _5_ = 300;
  public let _6_ = false;
};
check(withCell);
withCell._0_ := 55; withCell._4_ := "updated";
check(withCell);
func sparse(value : {_3_ : Text; _5_ : Nat}) {
  assert Wire.encodeOrTrap(value) == "\02ok\ac\02";
  assert Wire.encodeBoundedOrTrap(value, 5) == "\02ok\ac\02";
  assert Wire.estimateSize(value) == 5;
};
sparse(wider);
func empty(value : {}) {
  assert Wire.encodeOrTrap(value) == "";
  assert Wire.encodeBoundedOrTrap(value, 0) == "";
  assert Wire.estimateSize(value) == 0;
};
empty(wider); empty({});
// Lexical names and escaped numeric names do not share a common heap/wire
// ordering. The SDK computes its heap lower bound; wire order is unchanged.
func named(value : {aa : Text; z : Nat8; _4294967295_ : Nat8}) {
  assert Wire.encodeOrTrap(value) == "\09\02ok\07";
  assert Wire.encodeBoundedOrTrap(value, 5) == "\09\02ok\07";
  assert Wire.estimateSize(value) == 5;
};
let namedWide = {a = 100; aa = "ok"; z = 9 : Nat8; zz = false; _0_ = "ignored"; _4294967295_ = 7 : Nat8};
named(namedWide);
func escaped(value : {x_ : Nat8; _0_ : Text; _4294967295_ : Nat8}) {
  assert Wire.encodeOrTrap(value) == "\02ok\03\04";
  assert Wire.encodeBoundedOrTrap(value, 5) == "\02ok\03\04";
  assert Wire.estimateSize(value) == 5;
};
let escapedWide = {_0_ = "ok"; x_ = 3 : Nat8; xx = false; _4294967295_ = 4 : Nat8};
escaped(escapedWide);
type Outer = {a : Small; z : ?Small};
func nested(value : Outer) {
  let bytes : Blob = "\11\02ok\ac\02\01\11\02ok\ac\02";
  assert Wire.encodeOrTrap(value) == bytes;
  assert Wire.encodeBoundedOrTrap(value, bytes.size()) == bytes;
  assert Wire.estimateSize(value) == bytes.size();
  assert Wire.decodeOptional<Outer>(bytes) == ?value;
};
let nestedWide = {a = wider; mid = "ignored"; z = ?withCell; zz = [false]};
nested(nestedWide);
type Tree = {#_0_ : Small; #_1_ : {a : Tree; z : ?Tree}};
func recursive(value : Tree) {
  let bytes : Blob = "\01\00\11\02ok\ac\02\01\00\11\02ok\ac\02";
  assert Wire.encodeOrTrap(value) == bytes;
  assert Wire.encodeBoundedOrTrap(value, bytes.size()) == bytes;
  assert Wire.estimateSize(value) == bytes.size();
  assert Wire.decode<Tree>(bytes) == #ok value;
  assert Wire.decodeOptional<Tree>(bytes) == ?value;
  assert Wire.decodeOrTrap<Tree>(bytes) == value;
};
recursive(#_1_({a = #_0_(wider); z = ?#_0_(withCell)}));
func invalid(value : {a : Nat8; z : Float}) {
  assert Wire.encode(value) == #err({kind = "float"; offset = 1});
  assert Wire.encodeBounded(value, 9) == #err({kind = "float"; offset = 1});
  assert Wire.encodeBounded(value, 0) == #err({kind = "limit"; offset = 0});
};
let invalidWide = {_0_ = 9; a = 1 : Nat8; middle = "ignored"; z = 0.0 / 0.0; zz = false};
invalid(invalidWide);
func shortBound(value : {a : Nat8; z : Float}) {
  assert Wire.encodeBounded(value, 8) == #err({kind = "limit"; offset = 1});
};
let shortWide = {_0_ = 9; a = 1 : Nat8; middle = "ignored"; z = 1.5; zz = false};
shortBound(shortWide);
