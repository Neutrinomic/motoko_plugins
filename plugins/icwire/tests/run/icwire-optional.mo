//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";

type Nested = {#ok : {#err : ?Nat}; #err : ?Text};
let nested : [Nested] = [#ok(#err(null)), #ok(#err(?12345)), #err(null), #err(?"handled")];
for (value in nested.values()) {
  let bytes = Wire.encodeOrTrap(value);
  assert Wire.decodeOptional<Nested>(bytes) == ?value;
  assert Wire.decodeOptional<Nested>(bytes) == Wire.toOption(Wire.decode<Nested>(bytes));
  assert Wire.decode<Nested>(bytes) == #ok value;
  assert Wire.decodeOrTrap<Nested>(bytes) == value;
};
assert Wire.decodeOptional<Null>("") == ?null;
assert Wire.decodeOptional<Null>("\00") == null;
assert Wire.decodeOptional<?Null>("\00") == ?null;
assert Wire.decodeOptional<?Null>("\01") == ??null;
assert Wire.decodeOptional<??Null>("\01\00") == ??null;
assert Wire.decodeOptional<??Null>("\01\01") == ???null;
assert Wire.decodeOptional<??Null>("\01\02") == null;
assert Wire.decodeOptional<()>("") == ?();
assert Wire.decodeOptional<Bool>("\00") == ?false;
assert Wire.decodeOptional<Bool>("\01") == ?true;
assert Wire.decodeOptional<Bool>("\02") == null;
assert Wire.decodeOptional<Nat>("\80\01") == ?128;
assert Wire.decodeOptional<Nat>("\80\00") == null;
assert Wire.decodeOptional<Nat>("\80") == null;
assert Wire.decodeOptional<Nat>("\01\00") == null;
assert Wire.decodeOptional<Text>("\03abc") == ?"abc";
assert Wire.decodeOptional<Text>("\02\c0\80") == null;
assert Wire.decodeOptional<Blob>("\03abc") == ?"abc";
assert Wire.decodeOptional<Blob>("\04abc") == null;
assert Wire.decodeOptional<[Nat16]>("\03\00\00\01\00\ff\ff") == ?[0, 1, 65535];
assert Wire.decodeOptional<[Nat16]>("\03\00\00\01\00\ff") == null;
type Record = {tag : ?Nat; values : [Nested]};
let record : Record = {tag = ?123; values = nested};
let bytes = Wire.encodeOrTrap(record);
assert Wire.decodeOptional<Record>(bytes) == ?record;
assert Wire.decodeOptional<Record>(bytes) == Wire.toOption(Wire.decode<Record>(bytes));
assert Wire.decode<Record>(bytes) == #ok record;
assert Wire.decodeOrTrap<Record>(bytes) == record;

// Aliases must preserve the payload type needed for outer optional boxing.
type Nullable = ?Null;
assert Wire.decodeOptional<Nullable>("\00") == ?null;
assert Wire.decodeOptional<Nullable>("\01") == ??null;
// Both APIs and trapping success share value visitors, but not result modes.
// Interleave failed general parses with later valid parses to exercise cleanup.
for (_ in [0, 1, 2, 3].values()) {
  assert Wire.decodeOptional<Record>("\02") == null;
  assert Wire.decodeOptional<Record>(bytes) == ?record;
  assert Wire.decode<Record>(bytes) == #ok record;
  assert Wire.decodeOrTrap<Record>(bytes) == record;
};
