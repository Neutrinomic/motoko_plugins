//MOC-FLAG --plugin ../../../../dist/icwire
import Wire "../../../../packages/fast/src/ICWire";
import Prim "mo:⛔";

func ok<T>(result : Wire.Result<T>) : T {
  switch result {
    case (#ok value) value;
    case (#err error) Prim.trap(debug_show error);
  }
};
func limit<T>(result : Wire.Result<T>, offset : Nat) {
  switch result {
    case (#ok _) Prim.trap("expected depth limit");
    case (#err error) {
      assert error.kind == "limit";
      assert Prim.nat64ToNat(error.offset) == offset;
    };
  }
};
func full(levels : Nat) : Blob {
  Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(levels + 1, func i {
    if (i == levels) 7 else 1
  }))
};

// Count primitive leaves as well as composite nodes in the static proof.
type D000 = Nat8;
type D001 = ?D000;
type D002 = ?D001;
type D003 = ?D002;
type D004 = ?D003;
type D005 = ?D004;
type D006 = ?D005;
type D007 = ?D006;
type D008 = ?D007;
type D009 = ?D008;
type D010 = ?D009;
type D011 = ?D010;
type D012 = ?D011;
type D013 = ?D012;
type D014 = ?D013;
type D015 = ?D014;
type D016 = ?D015;
type D017 = ?D016;
type D018 = ?D017;
type D019 = ?D018;
type D020 = ?D019;
type D021 = ?D020;
type D022 = ?D021;
type D023 = ?D022;
type D024 = ?D023;
type D025 = ?D024;
type D026 = ?D025;
type D027 = ?D026;
type D028 = ?D027;
type D029 = ?D028;
type D030 = ?D029;
type D031 = ?D030;
type D032 = ?D031;
type D033 = ?D032;
type D034 = ?D033;
type D035 = ?D034;
type D036 = ?D035;
type D037 = ?D036;
type D038 = ?D037;
type D039 = ?D038;
type D040 = ?D039;
type D041 = ?D040;
type D042 = ?D041;
type D043 = ?D042;
type D044 = ?D043;
type D045 = ?D044;
type D046 = ?D045;
type D047 = ?D046;
type D048 = ?D047;
type D049 = ?D048;
type D050 = ?D049;
type D051 = ?D050;
type D052 = ?D051;
type D053 = ?D052;
type D054 = ?D053;
type D055 = ?D054;
type D056 = ?D055;
type D057 = ?D056;
type D058 = ?D057;
type D059 = ?D058;
type D060 = ?D059;
type D061 = ?D060;
type D062 = ?D061;
type D063 = ?D062;
type D064 = ?D063;
type D065 = ?D064;
type D066 = ?D065;
type D067 = ?D066;
type D068 = ?D067;
type D069 = ?D068;
type D070 = ?D069;
type D071 = ?D070;
type D072 = ?D071;
type D073 = ?D072;
type D074 = ?D073;
type D075 = ?D074;
type D076 = ?D075;
type D077 = ?D076;
type D078 = ?D077;
type D079 = ?D078;
type D080 = ?D079;
type D081 = ?D080;
type D082 = ?D081;
type D083 = ?D082;
type D084 = ?D083;
type D085 = ?D084;
type D086 = ?D085;
type D087 = ?D086;
type D088 = ?D087;
type D089 = ?D088;
type D090 = ?D089;
type D091 = ?D090;
type D092 = ?D091;
type D093 = ?D092;
type D094 = ?D093;
type D095 = ?D094;
type D096 = ?D095;
type D097 = ?D096;
type D098 = ?D097;
type D099 = ?D098;
type D100 = ?D099;
type D101 = ?D100;
type D102 = ?D101;
type D103 = ?D102;
type D104 = ?D103;
type D105 = ?D104;
type D106 = ?D105;
type D107 = ?D106;
type D108 = ?D107;
type D109 = ?D108;
type D110 = ?D109;
type D111 = ?D110;
type D112 = ?D111;
type D113 = ?D112;
type D114 = ?D113;
type D115 = ?D114;
type D116 = ?D115;
type D117 = ?D116;
type D118 = ?D117;
type D119 = ?D118;
type D120 = ?D119;
type D121 = ?D120;
type D122 = ?D121;
type D123 = ?D122;
type D124 = ?D123;
type D125 = ?D124;
type D126 = ?D125;
type D127 = ?D126;
type D128 = ?D127;

// 127 options and one Nat8 fit exactly. Flattened helpers preserve the value.
let exact : D127 = ???????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????7;
assert ok(Wire.decode<D127>(full(127))) == exact;
// This schema can reach 129 nodes, so it must retain dynamic depth checks.
limit(Wire.decode<D128>(full(128)), 128);
assert ok(Wire.decode<D128>("\00")) == null;
let nullAt128 = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(128, func i {
  if (i == 127) 0 else 1
}));
let allowedDeepNull : D128 = ???????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????????null;
assert ok(Wire.decode<D128>(nullAt128)) == allowedDeepNull;

// Decode the identical child schema both as a depth-proven root and beneath
// a recursive variant. Its helper names must distinguish these two contexts.
type Recursive = {#f : D127; #r : Recursive};
let tooDeepRecursive = Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(129, func i {
  if (i == 0) 0 else if (i == 128) 7 else 1
}));
limit(Wire.decode<Recursive>(tooDeepRecursive), 128);
assert ok(Wire.decode<Recursive>("\00\00")) == #f(null);
assert ok(Wire.decode<D127>(full(127))) == exact;
// Repeated sibling containers and empty collections do not grow depth.
assert ok(Wire.decode<[((), [Nat8], ?Nat8)]>("\02\00\00\00\01\09")) ==
  [((), [], null), ((), [], ?9)];
