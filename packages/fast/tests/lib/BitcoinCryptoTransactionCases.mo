import Array "mo:core/Array";
import Prim "mo:⛔";
import Transaction "mo:fast/Bitcoin/Transaction";
import Script "mo:fast/Bitcoin/Script";

module {
  func get<T>(value : ?T) : T { switch value { case (?v) v; case null { assert false; loop {} } } };
  func isNone<T>(value : ?T) : Bool { switch value { case null true; case _ false } };
  func fill(n : Nat, b : Nat8) : Blob = Prim.arrayToBlob(Array.repeat<Nat8>(b, n));
  func replace(raw : Blob, start : Nat, count : Nat, replacement : Blob) : Blob {
    Prim.arrayToBlob(Array.tabulate<Nat8>(raw.size() - count + replacement.size(), func(i) {
      if (i < start) raw[i]
      else if (i < start + replacement.size()) replacement[i - start]
      else raw[i - replacement.size() + count]
    }))
  };

  public func run() {
    let input : Transaction.Input = {
      previousTxid = fill(32, 1); previousIndex = 7;
      scriptSig = ""; sequence = 0xffff_ffff; witness = [];
    };
    let output : Transaction.Output = { value = 42; scriptPubKey = "" };
    let tx : Transaction.Tx = { version = 2; inputs = [input]; outputs = [output]; lockTime = 0 };
    let raw = get(Transaction.serialize(tx, true));
    assert raw.size() == 60;
    assert Transaction.parse(raw) == ?tx;
    assert Transaction.serialize(tx, false) == ?raw;
    assert Transaction.txid(tx) == Transaction.wtxid(tx);
    var i = 0;
    while (i < raw.size()) {
      let prefix = Prim.arrayToBlob(Array.tabulate<Nat8>(i, func(j) { raw[j] }));
      assert Transaction.parse(prefix) == null;
      i += 1;
    };
    assert Transaction.parse(replace(raw, raw.size(), 0, "\00")) == null;
    // Every CompactSize field rejects nonminimal integer encodings.
    for (offset in [4, 46].values()) {
      assert Transaction.parse(replace(raw, offset, 1, "\fd\01\00")) == null;
      assert Transaction.parse(replace(raw, offset, 1, "\fe\01\00\00\00")) == null;
      assert Transaction.parse(replace(raw, offset, 1, "\ff\01\00\00\00\00\00\00\00")) == null;
    };
    for (offset in [41, 55].values()) {
      assert Transaction.parse(replace(raw, offset, 1, "\fd\00\00")) == null;
      assert Transaction.parse(replace(raw, offset, 1, "\ff\ff\ff\ff\ff\ff\ff\ff\ff")) == null;
    };
    assert Transaction.parse(replace(raw, 4, 1, "\fd\ff\ff")) == null;
    assert Transaction.parse(replace(raw, 46, 1, "\fd\ff\ff")) == null;
    assert Transaction.parse(replace(raw, 4, 1, "\00\02\01")) == null;
    assert Transaction.parse(replace(raw, 4, 1, "\00\01\00")) == null;
    assert Transaction.serialize({ tx with inputs = [] }, true) == null;
    assert Transaction.serialize({ tx with inputs = [{ input with previousTxid = "short" }] }, true) == null;
    assert isNone(Transaction.prepareTaproot(tx, []));
    assert isNone(Transaction.prepareTaproot(tx, [output, output]));

    // One empty witness element is a nonempty witness stack and must survive.
    let witnessed : Transaction.Tx = { tx with inputs = [{ input with witness = [""] }] };
    let witnessRaw = get(Transaction.serialize(witnessed, true));
    assert witnessRaw.size() == 64;
    assert Transaction.parse(witnessRaw) == ?witnessed;
    assert Transaction.serialize(witnessed, false) == ?raw;
    assert Transaction.txid(witnessed) == Transaction.txid(tx);
    assert Transaction.wtxid(witnessed) != Transaction.txid(tx);
    assert Transaction.parse(replace(witnessRaw, 58, 2, "\00")) == null;
    assert Transaction.parse(replace(witnessRaw, 58, 1, "\fd\01\00")) == null;
    assert Transaction.parse(replace(witnessRaw, 59, 1, "\fd\00\00")) == null;
    assert Transaction.parse(replace(witnessRaw, 58, 1, "\ff\ff\ff\ff\ff\ff\ff\ff\ff")) == null;

    // CompactSize boundaries in scripts and witness elements round-trip.
    for (length in [252, 253, 254, 65535, 65536].values()) {
      let payload = fill(length, 0xab);
      let large : Transaction.Tx = {
        tx with inputs = [{ input with scriptSig = payload; witness = [payload] }];
        outputs = [{ output with scriptPubKey = payload }];
      };
      assert Transaction.parse(get(Transaction.serialize(large, true))) == ?large;
    };
    let scripts : [Blob] = ["\01", "\4c", "\4c\02\ab", "\4d\01", "\4e\ff\ff\ff\ff"];
    for (malformed in scripts.values()) assert Transaction.signatureHashLegacy(tx, 0, malformed, 1) == null;
    let one : Blob = "\01\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
    assert Transaction.signatureHashLegacy(tx, 10, "", 1) == ?one;
    assert Transaction.signatureHashLegacy({ tx with outputs = [] }, 0, "", 3) == ?one;
    assert Transaction.signatureHashSegwitV0(tx, 10, "", 42, 1) == null;
    // BIP143 SINGLE lacks the historical legacy constant-one behavior.
    let noOutput = { tx with outputs = [] };
    assert Transaction.signatureHashSegwitV0(noOutput, 0, "", 42, 3) != null;
    assert Transaction.signatureHashSegwitV0(noOutput, 0, "", 42, 3) != ?one;
    assert Transaction.signatureHashTaproot(noOutput, 0, [output], 3, null, null) == null;
    let taproot = get(Transaction.prepareTaproot(tx, [output]));
    i := 0;
    while (i < 256) {
      let result = taproot.signatureHash(0, Prim.natToNat8(i), null, null);
      let allowed = i == 0 or i == 1 or i == 2 or i == 3 or i == 129 or i == 130 or i == 131;
      assert (result != null) == allowed;
      i += 1;
    };
    assert taproot.signatureHash(1, 0, null, null) == null;
    assert taproot.signatureHash(0, 0, ?"", null) == null;
    assert taproot.signatureHash(0, 0, ?"\51", null) == null;
    assert taproot.signatureHash(0, 0, ?"\50", null) != null;
    assert taproot.signatureHash(0, 0, null, ?{ tapLeafHash = ""; codeSeparatorPosition = 0 }) == null;
    // Prepared hashers retain their own transaction and prevouts across calls.
    let modified : Transaction.Tx = { tx with lockTime = 1 };
    let other = get(Transaction.prepareTaproot(modified, [output]));
    let cached = taproot.signatureHash(0, 0, null, null);
    assert cached != other.signatureHash(0, 0, null, null);
    assert cached == taproot.signatureHash(0, 0, null, null);
    assert cached == Transaction.signatureHashTaproot(tx, 0, [output], 0, null, null);

    assert Script.pushData("") == ?"\00";
    assert Script.pushData("\00") == ?"\01\00";
    assert Script.pushData("\01") == ?"\51";
    assert Script.pushData("\10") == ?"\60";
    assert Script.pushData("\81") == ?"\4f";
    assert Script.pushData("\11") == ?"\01\11";
    let pushes : [(Nat, Blob)] = [(75, "\4b"), (76, "\4c\4c"), (255, "\4c\ff"), (256, "\4d\00\01"), (65535, "\4d\ff\ff"), (65536, "\4e\00\00\01\00")];
    for ((length, prefix) in pushes.values()) {
      let encoded = get(Script.pushData(fill(length, 0xab)));
      assert encoded.size() == prefix.size() + length;
      var j = 0;
      while (j < prefix.size()) { assert encoded[j] == prefix[j]; j += 1 };
      while (j < encoded.size()) { assert encoded[j] == 0xab; j += 1 };
    };
    assert Script.p2pkh("short") == null;
    assert Script.p2sh("short") == null;
    assert get(Script.p2pkh(fill(20, 1))).size() == 25;
    assert get(Script.p2sh(fill(20, 1))).size() == 23;
    assert get(Script.p2wpkh(fill(20, 1))).size() == 22;
    assert get(Script.p2wsh(fill(32, 1))).size() == 34;
    assert get(Script.p2tr(fill(32, 1))).size() == 34;
    assert Script.p2wpkh(fill(32, 1)) == null;
    assert Script.p2wsh(fill(20, 1)) == null;
    assert Script.p2tr(fill(20, 1)) == null;
    assert Script.witnessProgram(17, fill(32, 1)) == null;
    assert Script.witnessProgram(0, fill(2, 1)) == null;
    assert Script.witnessProgram(1, fill(1, 1)) == null;
    assert Script.witnessProgram(16, fill(41, 1)) == null;
    assert Script.witnessProgram(16, fill(2, 1)) == ?"\60\02\01\01";
    assert Script.tapLeafHash("\51", 0xc1) == null;
    assert Script.tapBranchHash(fill(31, 1), fill(32, 2)) == null;
    assert Script.tapBranchHash(fill(32, 1), fill(33, 2)) == null;
    assert Script.tapBranchHash(fill(32, 1), fill(32, 2)) == Script.tapBranchHash(fill(32, 2), fill(32, 1));
  };
}
