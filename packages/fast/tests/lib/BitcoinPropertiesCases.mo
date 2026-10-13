// Relations fixed by BIP32, BIP143 and BIP341, anchored by independently
// generated Bitcoin Core references in BitcoinPropertiesVectors.mo.
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";
import Nat32 "mo:core/Nat32";
import Nat64 "mo:core/Nat64";
import Runtime "mo:core/Runtime";
import Bip32 "mo:fast/Bitcoin/Bip32";
import T "mo:fast/Bitcoin/Transaction";
import V "BitcoinPropertiesVectors";

module {
  func get<A>(value : ?A) : A {
    switch value { case (?v) v; case null Runtime.trap("expected a Bitcoin result") }
  };
  func ok<A>(value : Bip32.Result<A>) : A {
    switch value { case (#ok(v)) v; case (#err(e)) Runtime.trap("BIP32: " # debug_show e) }
  };
  func fill(n : Nat, b : Nat8) : Blob = Blob.fromArray(Array.repeat<Nat8>(b, n));
  func changed(actual : ?Blob, before : Blob, expected : Bool, context : Text) {
    if ((get(actual) != before) != expected) Runtime.trap("sighash commitment: " # context);
  };
  func set<A>(items : [A], index : Nat, value : A) : [A] {
    Array.tabulate<A>(items.size(), func(i) { if (i == index) value else items[i] })
  };

  public func bip32Relations() {
    for ((pub, chain, index, childPub, childChain, grandPub, grandChain, fingerprint) in V.bip32.values()) {
      let root = ok(Bip32.fromPublicKey(pub, chain, #mainnet));
      let child = ok(Bip32.deriveChild(root, index));
      // The reference derives a private scalar then multiplies G; production
      // instead tweaks a public point. Check both key and HMAC right half.
      assert child.publicKey == childPub and child.chainCode == childChain;
      assert child.depth == 1 and child.childIndex == index;
      assert child.parentFingerprint == fingerprint;
      assert ok(Bip32.fingerprint(pub)) == fingerprint;
      let grand = ok(Bip32.derivePath(root, [index, 7]));
      assert grand.publicKey == grandPub and grand.chainCode == grandChain;
      assert grand == ok(Bip32.deriveChild(child, 7));
      assert grand == ok(Bip32.deriveTextPath(root, "m/" # index.toText() # "/0007"));
      assert grand == ok(Bip32.deriveTextPath(child, "0007"));
      assert ok(Bip32.parse(ok(Bip32.serialize(grand)))) == grand;
      // Serialized ancestry/network fields never enter CKDpub's HMAC. Imported
      // hardened ancestry is valid; deriving a hardened child remains forbidden.
      let imported : Bip32.ExtendedPublicKey = { root with network = #testnet; depth = 137; parentFingerprint = "\ff\00\ab\80"; childIndex = 0xffffffff };
      assert ok(Bip32.parse(ok(Bip32.serialize(imported)))) == imported;
      let derived = ok(Bip32.deriveChild(imported, index));
      assert derived == { child with network = #testnet; depth = 138 };
      assert Bip32.deriveChild(imported, 0x80000000) == #err(#hardenedChild);
      assert Bip32.deriveChild(imported, 0xffffffff) == #err(#hardenedChild);
      assert Bip32.deriveTextPath(imported, "M/0") == #err(#invalidPath);
      let almost : Bip32.ExtendedPublicKey = { imported with depth = 254 };
      let last = ok(Bip32.derivePath(almost, [index]));
      assert last.depth == 255;
      assert ok(Bip32.parse(ok(Bip32.serialize(last)))) == last;
      assert ok(Bip32.derivePath(last, [])) == last;
      assert Bip32.deriveChild(last, 0) == #err(#maximumDepth);
      assert Bip32.derivePath(almost, [index, 0]) == #err(#maximumDepth);
      // Even empty paths must validate caller-built records.
      let invalid : [(Bip32.ExtendedPublicKey, Bip32.Error)] = [
        ({ root with chainCode = fill(31, 0) }, #invalidChainCode),
        ({ root with chainCode = fill(33, 0) }, #invalidChainCode),
        ({ root with parentFingerprint = fill(3, 0) }, #invalidFingerprint),
        ({ root with parentFingerprint = fill(5, 0) }, #invalidFingerprint),
        ({ root with childIndex = 0x80000000 }, #invalidMaster),
        ({ root with parentFingerprint = "\00\00\00\01" }, #invalidMaster),
        ({ root with publicKey = fill(33, 0) }, #invalidPublicKey),
      ];
      for ((key, error) in invalid.values()) {
        assert Bip32.serialize(key) == #err(error);
        assert Bip32.deriveChild(key, 0) == #err(error);
        assert Bip32.derivePath(key, []) == #err(error);
        assert Bip32.deriveTextPath(key, "m") == #err(error);
      };
    };
    var path = "0";
    var count = 1;
    while (count < 255) { path #= "/0"; count += 1 };
    assert ok(Bip32.parsePath(path)).size() == 255;
    assert Bip32.parsePath(path # "/0") == #err(#maximumDepth);
    assert Bip32.parsePath("000000002147483647") == #ok([0x7fffffff]);
    assert Bip32.parsePath("000000002147483648") == #err(#hardenedChild);
    for (path in ["0\00", "0/\00", "0/é", "0/𝟙", "0/1\0a"].values()) {
      assert Bip32.parsePath(path) == #err(#invalidPath);
    };
  };

  func transaction() : T.Tx = {
    version = 2; lockTime = 0x12345678;
    inputs = Array.tabulate<T.Input>(3, func(i) {
      { previousTxid = fill(32, Nat8.fromNat(i + 1)); previousIndex = Nat32.fromNat(i + 7);
        scriptSig = Blob.fromArray([Nat8.fromNat(0x51 + i)]); sequence = Nat32.fromNat(0xfffffffd - i); witness = [] }
    });
    outputs = Array.tabulate<T.Output>(3, func(i) {
      { value = Nat64.fromNat(1000 + i); scriptPubKey = Blob.fromArray([Nat8.fromNat(0x51 + i)]) }
    });
  };
  func prevouts() : [T.Output] = Array.tabulate<T.Output>(3, func(i) {
    { value = Nat64.fromNat(2000 + i); scriptPubKey = Blob.fromArray(Array.tabulate<Nat8>(34, func(j) {
        if (j == 0) 0x51 else if (j == 1) 0x20 else Nat8.fromNat(0x61 + i)
      })) }
  });
  let script : Blob = "\01\ab\ab\51";

  public func sighashCommitments() {
    let tx = transaction();
    let spent = prevouts();
    let (_, _, allSegwit, allTaproot) = V.sighashes[0];
    // Exercise lazy caches while cold: NONE/SINGLE and ACP suppress different
    // common hashes. An initial invalid request must not affect later calls.
    for (slot in [1, 2, 3, 4, 5].values()) {
      let (kind, _, expectedSegwit, expectedTaproot) = V.sighashes[slot];
      let tapKind = Nat8.fromNat(kind.toNat());
      let freshV0 = get(T.prepareSegwitV0(tx));
      let freshTap = get(T.prepareTaproot(tx, spent));
      assert freshV0.signatureHash(3, script, spent[1].value, kind) == null;
      assert freshTap.signatureHash(1, 0x80, null, null) == null;
      assert freshV0.signatureHash(1, script, spent[1].value, kind) == ?expectedSegwit;
      assert freshTap.signatureHash(1, tapKind, null, null) == ?expectedTaproot;
      assert freshV0.signatureHash(1, script, spent[1].value, 1) == ?allSegwit;
      assert freshTap.signatureHash(1, 1, null, null) == ?allTaproot;
      assert freshV0.signatureHash(1, script, spent[1].value, kind) == ?expectedSegwit;
      assert freshTap.signatureHash(1, tapKind, null, null) == ?expectedTaproot;
    };
    let v0 = get(T.prepareSegwitV0(tx));
    let tap = get(T.prepareTaproot(tx, spent));
    for ((kind, legacy, segwit, taproot) in V.sighashes.values()) {
      let tapKind = Nat8.fromNat(kind.toNat());
      let anyone = kind & 0x80 != 0;
      // DEFAULT means ALL in Taproot; legacy and BIP143 also use their ALL
      // field rules for unknown base modes, retaining the supplied hash type.
      let mode : Nat32 = if (kind == 0) 1 else kind & 3;
      assert T.signatureHashLegacy(tx, 1, script, kind) == ?legacy;
      assert v0.signatureHash(1, script, spent[1].value, kind) == ?segwit;
      assert tap.signatureHash(1, tapKind, null, null) == ?taproot;
      func checkTx(other : T.Tx, l : Bool, s : Bool, t : Bool, context : Text) {
        changed(T.signatureHashLegacy(other, 1, script, kind), legacy, l, context # " legacy");
        changed(T.signatureHashSegwitV0(other, 1, script, spent[1].value, kind), segwit, s, context # " v0");
        changed(T.signatureHashTaproot(other, 1, spent, tapKind, null, null), taproot, t, context # " taproot");
      };
      checkTx({ tx with version = 3 }, true, true, true, "version");
      checkTx({ tx with lockTime = 0 }, true, true, true, "lockTime");
      for (i in [0, 1, 2].values()) {
        let self = i == 1;
        let input = tx.inputs[i];
        checkTx({ tx with inputs = set<T.Input>(tx.inputs, i, { input with previousTxid = fill(32, 4) }) },
          self or not anyone, self or not anyone, self or not anyone, "outpoint txid");
        checkTx({ tx with inputs = set<T.Input>(tx.inputs, i, { input with previousIndex = 42 }) },
          self or not anyone, self or not anyone, self or not anyone, "outpoint index");
        checkTx({ tx with inputs = set<T.Input>(tx.inputs, i, { input with sequence = 0 }) },
          self or (not anyone and mode == 1), self or (not anyone and mode == 1), self or not anyone, "sequence");
        checkTx({ tx with inputs = set<T.Input>(tx.inputs, i, { input with scriptSig = "\00\ff"; witness = ["", "\50"] }) },
          false, false, false, "scripts and witnesses");
        let commitsOutput = mode == 1 or (mode == 3 and self);
        checkTx({ tx with outputs = set<T.Output>(tx.outputs, i, { tx.outputs[i] with value = 99999 }) },
          commitsOutput, commitsOutput, commitsOutput, "output amount");
        checkTx({ tx with outputs = set<T.Output>(tx.outputs, i, { tx.outputs[i] with scriptPubKey = "\6a" }) },
          commitsOutput, commitsOutput, commitsOutput, "output script");
        for (replacement in ([{ spent[i] with value = 99999 }, { spent[i] with scriptPubKey = "\00" }] : [T.Output]).values()) {
          changed(T.signatureHashTaproot(tx, 1, set<T.Output>(spent, i, replacement), tapKind, null, null), taproot,
            self or not anyone, "spent output");
        };
      };
      changed(v0.signatureHash(1, script, spent[1].value + 1, kind), segwit, true, "v0 amount");
      changed(v0.signatureHash(1, "\01\ab\51", spent[1].value, kind), segwit, true, "v0 keeps CODESEPARATOR");
      assert T.signatureHashLegacy(tx, 1, "\01\ab\51", kind) == ?legacy;
      changed(T.signatureHashLegacy(tx, 1, "\01\ac\51", kind), legacy, true, "legacy pushed byte");
      changed(tap.signatureHash(1, tapKind, ?"\50", null), taproot, true, "annex present");
      let extension : T.TapscriptExtension = { tapLeafHash = fill(32, 0); codeSeparatorPosition = 0xffffffff };
      let scriptHash = get(tap.signatureHash(1, tapKind, null, ?extension));
      assert scriptHash != taproot;
      changed(tap.signatureHash(1, tapKind, null, ?{ extension with codeSeparatorPosition = 0 }), scriptHash, true, "codesep position");
      changed(tap.signatureHash(1, tapKind, null, ?{ extension with tapLeafHash = fill(32, 1) }), scriptHash, true, "tapleaf");
      // Failed requests and other cache modes must not poison reused closures.
      assert tap.signatureHash(1, 0x80, null, null) == null;
      assert tap.signatureHash(1, tapKind, ?"\51", null) == null;
      assert v0.signatureHash(3, script, spent[1].value, kind) == null;
      assert tap.signatureHash(1, tapKind, null, null) == ?taproot;
      assert v0.signatureHash(1, script, spent[1].value, kind) == ?segwit;
    };
    // ACP|SINGLE commits input/output pairs without the input index in BIP143
    // and BIP341. Legacy's preceding dummy outputs preserve that index.
    let reordered : T.Tx = { tx with inputs = [tx.inputs[1], tx.inputs[0], tx.inputs[2]];
      outputs = [tx.outputs[1], tx.outputs[0], tx.outputs[2]] };
    let reorderedSpent = [spent[1], spent[0], spent[2]];
    assert T.signatureHashSegwitV0(reordered, 0, script, spent[1].value, 0x83) == v0.signatureHash(1, script, spent[1].value, 0x83);
    assert T.signatureHashTaproot(reordered, 0, reorderedSpent, 0x83, null, null) == tap.signatureHash(1, 0x83, null, null);
    assert get(T.signatureHashLegacy(reordered, 0, script, 0x83)) != get(T.signatureHashLegacy(tx, 1, script, 0x83));
    assert get(T.signatureHashSegwitV0(reordered, 0, script, spent[1].value, 3)) != get(v0.signatureHash(1, script, spent[1].value, 3));
    assert get(T.signatureHashTaproot(reordered, 0, reorderedSpent, 3, null, null)) != get(tap.signatureHash(1, 3, null, null));
    assert get(tap.signatureHash(1, 0, null, null)) != get(tap.signatureHash(1, 1, null, null));
  };

  func replace(raw : Blob, start : Nat, count : Nat, replacement : Blob) : Blob {
    Blob.fromArray(Array.tabulate<Nat8>(raw.size() - count + replacement.size(), func(i) {
      if (i < start) raw[i]
      else if (i < start + replacement.size()) replacement[i - start]
      else raw[i - replacement.size() + count]
    }))
  };

  public func wireCounts() {
    let input : T.Input = { previousTxid = fill(32, 0xa5); previousIndex = 0xffffffff;
      scriptSig = ""; sequence = 0x80000000; witness = [] };
    let output : T.Output = { value = 0x0102030405060708; scriptPubKey = "" };
    for ((kind, count, size, txid, wtxid) in V.wire.values()) {
      let tx : T.Tx = {
        version = 0xffffffff; lockTime = 0x80000000;
        inputs = if (kind == 0) Array.repeat<T.Input>(input, count)
          else [{ input with witness = if (kind == 2) Array.repeat<Blob>("", count) else [] }];
        outputs = Array.repeat<T.Output>(output, if (kind == 1) count else 1);
      };
      let raw = get(T.serialize(tx, true));
      assert raw.size() == size;
      assert T.parse(raw) == ?tx;
      assert T.txid(tx) == ?txid and T.wtxid(tx) == ?wtxid;
      // Counts cross CompactSize's one-byte boundary independently, including
      // a witness stack whose entries are all empty but whose count is nonzero.
      let offset = if (kind == 0) 4 else if (kind == 1) 46 else 58;
      let width = if (count < 253) 1 else 3;
      assert raw[offset] == (if (width == 1) 252 else 253);
      if (width == 3) { assert raw[offset + 1] == Nat8.fromNat(count); assert raw[offset + 2] == 0 };
      let tooWide = Blob.fromArray([0xfe, Nat8.fromNat(count), 0, 0, 0]);
      assert T.parse(replace(raw, offset, width, tooWide)) == null;
      assert T.parse(replace(raw, offset, width, "\ff\ff\ff\ff\ff\ff\ff\ff\ff")) == null;
      assert T.parse(replace(raw, raw.size() - 1, 1, "")) == null;
      assert T.parse(replace(raw, raw.size(), 0, "\00")) == null;
    };
  };
}
