// Independently reviewed boundary and rejection checks complement Core oracle vectors.
import T "mo:fast/Bitcoin/Transaction";
import S "mo:fast/Bitcoin/Script";
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";
import Prim "mo:⛔";
func get<A>(x : ?A) : A { switch x { case (?v) v; case null { assert false; loop {} } } };
func fill(n : Nat, b : Nat8) : Blob = Blob.fromArray(Array.repeat<Nat8>(b, n));
func cat(parts : [Blob]) : Blob {
  var n = 0; for (b in parts.values()) { n += b.size() };
  let a = Prim.Array_init<Nat8>(n, 0); var i = 0;
  for (b in parts.values()) for (v in b.values()) { a[i] := v; i += 1 };
  Prim.arrayMutToBlob(a)
};
let input : T.Input = { previousTxid = fill(32, 0xff); previousIndex = 0xffffffff; scriptSig = ""; sequence = 0xffffffff; witness = [] };
let output : T.Output = { value = 0xffffffffffffffff; scriptPubKey = "" };
let tx : T.Tx = { version = 0xffffffff; inputs = [input, input]; outputs = [output]; lockTime = 0xffffffff };
let raw = get(T.serialize(tx, false));
assert T.parse(raw) == ?tx;
let empty : T.Tx = { tx with outputs = [] };
assert T.parse(get(T.serialize(empty, true))) == ?empty;
// Witness presence means a nonempty stack, even if all its elements are empty.
for (stack in ([[], [""], ["", ""], ["\00", ""], ["", "\50"]] : [[Blob]]).values()) {
  let witnessed = { tx with inputs = [input, { input with witness = stack }] };
  let bytes = get(T.serialize(witnessed, true));
  assert T.parse(bytes) == ?witnessed;
  assert T.serialize(witnessed, false) == ?raw;
  if (stack.size() == 0) assert bytes == raw else assert bytes != raw;
};
// Input/field count guards reject unbounded loop requests before allocation.
for (count in (["\fd\00\fd", "\fe\00\00\01\00", "\ff\00\00\00\00\01\00\00\00", "\ff\ff\ff\ff\ff\ff\ff\ff\ff"] : [Blob]).values()) {
  assert T.parse(cat(["\02\00\00\00", count, "\00\00\00\00\00"])) == null;
};
// All non-1 witness flags are unsupported, with no partial transaction result.
for (flag in [0, 2, 3, 0x7f, 0x80, 0xff].values()) {
  assert T.parse(cat(["\02\00\00\00\00", Blob.fromArray([Nat8.fromNat(flag)]), "\01", fill(32,0), "\00\00\00\00\00\ff\ff\ff\ff\00\00\00\00\00"])) == null;
};
for (broken in (["\01", "\02\ab", "\4c", "\4c\ff", "\4d\ff", "\4e\00\00\00"] : [Blob]).values()) {
  assert T.signatureHashLegacy(tx, 0, broken, 1) == null;
};
// Tapscript positions are opcode indices, serialized as raw uint32 values.
let ext : T.TapscriptExtension = { tapLeafHash = fill(32, 4); codeSeparatorPosition = 0xffffffff };
let spent = [output, output];
assert T.signatureHashTaproot(tx, 0, spent, 0, ?"\50", ?ext) != null;
assert T.signatureHashTaproot(tx, 0, spent, 0, ?"\51", ?ext) == null;
assert T.signatureHashTaproot(tx, 0, spent, 0, ?"", ?ext) == null;
assert T.signatureHashTaproot(tx, 0, spent, 0, null, ?{ ext with tapLeafHash = fill(31, 4) }) == null;
assert T.signatureHashTaproot(tx, 0, spent, 0, null, ?{ ext with tapLeafHash = fill(33, 4) }) == null;
assert T.signatureHashTaproot(tx, 1, spent, 3, null, null) == null;
assert T.signatureHashTaproot(tx, 1, spent, 0x83, null, null) == null;
assert T.signatureHashTaproot(tx, 0, [output], 0x81, null, null) == null;
assert T.signatureHashTaproot(tx, 0, [output, output, output], 0, null, null) == null;
// Minimal script pushes preserve byte payloads: OP_0 would not represent [00].
assert S.pushData("") == ?"\00";
assert S.pushData("\00") == ?"\01\00";
assert S.pushData("\81") == ?"\4f";
for (n in [1, 2, 15, 16].values()) {
  assert S.pushData(Blob.fromArray([Nat8.fromNat(n)])) == ?Blob.fromArray([Nat8.fromNat(0x50 + n)]);
};
assert S.pushData("\11") == ?"\01\11";
assert S.pushData("\80") == ?"\01\80";
assert S.pushData("\ff") == ?"\01\ff";
for ((size, prefix) in ([(75, "\4b"), (76, "\4c\4c"), (255,"\4c\ff"), (256,"\4d\00\01"), (65535,"\4d\ff\ff"), (65536,"\4e\00\00\01\00")] : [(Nat,Blob)]).values()) {
  let data = fill(size, 0x42);
  assert S.pushData(data) == ?cat([prefix, data]);
};
for (version in [0, 1, 2, 15, 16, 17, 255].values()) {
  for (length in [0,1,2,19,20,21,31,32,33,40,41].values()) {
    let program = fill(length, 0xab);
    let result = S.witnessProgram(Nat8.fromNat(version), program);
    let valid = version <= 16 and length >= 2 and length <= 40 and (version != 0 or length == 20 or length == 32);
    assert (result != null) == valid;
    if (valid) {
      let opcode = Nat8.fromNat(if (version == 0) 0 else version + 0x50);
      assert result == ?cat([Blob.fromArray([opcode, Nat8.fromNat(length)]), program]);
    };
  };
};
for (version in [1, 0x51, 0xc1, 0xff].values()) assert S.tapLeafHash("\51", Nat8.fromNat(version)) == null;
assert S.tapBranchHash(fill(31, 0), fill(32, 0)) == null;
assert S.tapBranchHash(fill(32, 0), fill(33, 0)) == null;
