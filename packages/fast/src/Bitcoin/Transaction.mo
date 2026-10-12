/// Bitcoin transaction serialization and legacy, BIP143 and BIP341/342 sighashes.
/// Requires the `sha256` compiler plugin. No transaction field is mutated.
///
/// `Input.previousTxid` uses the 32-byte order found on the wire (reverse of
/// explorer/display order). `txid` and `wtxid` return display-order bytes;
/// signature hashes return raw 32-byte digest order for ECDSA or BIP340 signing.
/// Scripts are raw bytes without their CompactSize prefix. Amounts are satoshis.
///
/// These helpers encode transactions, not consensus or policy validation: they
/// do not check monetary ranges, duplicate inputs, script execution or UTXOs.
/// Specifications: https://github.com/bitcoin/bips/blob/master/bip-0143.mediawiki
/// and https://github.com/bitcoin/bips/blob/master/bip-0341.mediawiki; tapscript
/// extends the latter as https://github.com/bitcoin/bips/blob/master/bip-0342.mediawiki.
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";
import Nat32 "mo:core/Nat32";
import Nat64 "mo:core/Nat64";
import VarArray "mo:core/VarArray";
import SHA256 "../SHA256";

module {
  public type Input = {
    previousTxid : Blob;
    previousIndex : Nat32;
    scriptSig : Blob;
    sequence : Nat32;
    witness : [Blob];
  };
  public type Output = { value : Nat64; scriptPubKey : Blob };
  public type Tx = {
    version : Nat32;
    inputs : [Input];
    outputs : [Output];
    lockTime : Nat32;
  };
  /// BIP342 tapscript extension. Use 0xffffffff when no OP_CODESEPARATOR executed.
  /// The position counts opcodes, including parsed opcodes in unexecuted branches.
  public type TapscriptExtension = { tapLeafHash : Blob; codeSeparatorPosition : Nat32 };

  public let SIGHASH_DEFAULT : Nat8 = 0;
  public let SIGHASH_ALL : Nat32 = 1;
  public let SIGHASH_NONE : Nat32 = 2;
  public let SIGHASH_SINGLE : Nat32 = 3;
  public let SIGHASH_ANYONECANPAY : Nat32 = 0x80;

  let zero32 : Blob = "\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
  let one32 : Blob = "\01\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00\00";
  let max64 : Nat = 0xffff_ffff_ffff_ffff;

  func compactSize(n : Nat) : Nat {
    if (n < 253) 1 else if (n <= 0xffff) 3 else if (n <= 0xffff_ffff) 5 else 9
  };
  func fieldSize(bytes : Blob) : Nat = compactSize(bytes.size()) + bytes.size();
  func outputSize(output : Output) : Nat = 8 + fieldSize(output.scriptPubKey);

  // Every encoder computes its exact size up front, avoiding growing buffers and
  // intermediate arrays per input, output and witness item.
  class Writer(size : Nat) {
    let bytes = VarArray.repeat<Nat8>(0, size);
    var offset = 0;
    public func byte(b : Nat8) { bytes[offset] := b; offset += 1 };
    public func raw(b : Blob) {
      var i = 0;
      let n = b.size();
      while (i < n) { bytes[offset + i] := b[i]; i += 1 };
      offset += n;
    };
    public func le(n : Nat, width : Nat) {
      var rest = n;
      var i = 0;
      while (i < width) { byte(Nat8.fromNat(rest % 256)); rest /= 256; i += 1 };
    };
    public func le32(n : Nat32) {
      bytes[offset] := Nat8.fromNat32(n & 255);
      bytes[offset + 1] := Nat8.fromNat32((n >> 8) & 255);
      bytes[offset + 2] := Nat8.fromNat32((n >> 16) & 255);
      bytes[offset + 3] := Nat8.fromNat32(n >> 24);
      offset += 4;
    };
    public func le64(n : Nat64) {
      bytes[offset] := Nat8.fromNat64(n & 255);
      bytes[offset + 1] := Nat8.fromNat64((n >> 8) & 255);
      bytes[offset + 2] := Nat8.fromNat64((n >> 16) & 255);
      bytes[offset + 3] := Nat8.fromNat64((n >> 24) & 255);
      bytes[offset + 4] := Nat8.fromNat64((n >> 32) & 255);
      bytes[offset + 5] := Nat8.fromNat64((n >> 40) & 255);
      bytes[offset + 6] := Nat8.fromNat64((n >> 48) & 255);
      bytes[offset + 7] := Nat8.fromNat64(n >> 56);
      offset += 8;
    };
    public func compact(n : Nat) {
      if (n < 253) byte(Nat8.fromNat(n))
      else if (n <= 0xffff) { byte(0xfd); le(n, 2) }
      else if (n <= 0xffff_ffff) { byte(0xfe); le(n, 4) }
      else { byte(0xff); le(n, 8) }
    };
    public func field(b : Blob) { compact(b.size()); raw(b) };
    public func outpoint(input : Input) { raw(input.previousTxid); le32(input.previousIndex) };
    public func output(out : Output) { le64(out.value); field(out.scriptPubKey) };
    public func finish() : Blob { assert offset == size; Blob.fromVarArray(bytes) };
  };

  class Reader(raw : Blob) {
    let bytes = raw;
    var offset = 0;
    public func remaining() : Nat = bytes.size() - offset;
    public func le(width : Nat) : ?Nat {
      if (width > remaining()) return null;
      var n : Nat64 = 0;
      var shift : Nat64 = 0;
      var i = 0;
      while (i < width) { n |= Nat64.fromNat8(bytes[offset]) << shift; shift += 8; offset += 1; i += 1 };
      ?n.toNat()
    };
    public func take(n : Nat) : ?Blob {
      if (n > remaining()) return null;
      let start = offset;
      offset += n;
      ?Blob.fromArray(Array.tabulate<Nat8>(n, func(i) { bytes[start + i] }))
    };
    public func compact() : ?Nat {
      let tag = switch (le(1)) { case null return null; case (?v) v };
      if (tag < 253) return ?tag;
      let width = if (tag == 253) 2 else if (tag == 254) 4 else 8;
      let n = switch (le(width)) { case null return null; case (?v) v };
      if ((tag == 253 and n < 253) or (tag == 254 and n <= 0xffff) or (tag == 255 and n <= 0xffff_ffff)) return null;
      ?n
    };
    public func field() : ?Blob {
      switch (compact()) { case null null; case (?n) take(n) }
    };
  };

  func valid(tx : Tx) : Bool {
    if (tx.inputs.size() == 0 or tx.inputs.size() > 0xffff_ffff or tx.outputs.size() > max64) return false;
    for (input in tx.inputs.values()) {
      if (input.previousTxid.size() != 32 or input.scriptSig.size() > max64 or input.witness.size() > max64) return false;
      for (item in input.witness.values()) { if (item.size() > max64) return false };
    };
    for (output in tx.outputs.values()) { if (output.scriptPubKey.size() > max64) return false };
    true
  };

  /// Serialize a transaction, including marker/flag and witnesses only when
  /// requested and at least one witness stack is nonempty. Returns null for an
  /// empty input list, more than 2^32-1 inputs, a non-32-byte outpoint hash
  /// or unencodable field lengths.
  public func serialize(tx : Tx, includeWitness : Bool) : ?Blob {
    if (not valid(tx)) return null;
    var hasWitness = false;
    if (includeWitness) { for (input in tx.inputs.values()) { if (input.witness.size() != 0) hasWitness := true } };
    var size = 8 + compactSize(tx.inputs.size()) + compactSize(tx.outputs.size());
    for (input in tx.inputs.values()) { size += 40 + fieldSize(input.scriptSig) };
    for (output in tx.outputs.values()) { size += outputSize(output) };
    if (hasWitness) {
      size += 2;
      for (input in tx.inputs.values()) {
        size += compactSize(input.witness.size());
        for (item in input.witness.values()) { size += fieldSize(item) };
      };
    };
    let w = Writer(size);
    w.le32(tx.version);
    if (hasWitness) { w.byte(0); w.byte(1) };
    w.compact(tx.inputs.size());
    for (input in tx.inputs.values()) { w.outpoint(input); w.field(input.scriptSig); w.le32(input.sequence) };
    w.compact(tx.outputs.size());
    for (output in tx.outputs.values()) w.output(output);
    if (hasWitness) {
      for (input in tx.inputs.values()) {
        w.compact(input.witness.size());
        for (item in input.witness.values()) w.field(item);
      };
    };
    w.le32(tx.lockTime);
    ?w.finish()
  };

  /// Parse one complete transaction. Returns null for truncation, trailing bytes,
  /// noncanonical CompactSize integers, unknown witness flags, an empty input
  /// list, more than 2^32-1 inputs, or a superfluous witness marker with all
  /// witness stacks empty.
  /// Allocation and iteration bounds follow the remaining input bytes.
  public func parse(raw : Blob) : ?Tx {
    let r = Reader(raw);
    let version = switch (r.le(4)) { case null return null; case (?v) Nat32.fromNat(v) };
    var count = switch (r.compact()) { case null return null; case (?v) v };
    var witness = false;
    if (count == 0) {
      if (r.le(1) != ?1) return null;
      witness := true;
      count := switch (r.compact()) { case null return null; case (?v) v };
    };
    if (count == 0 or count > r.remaining() / 41 or count > 0xffff_ffff) return null;
    let inputs = VarArray.repeat<Input>({ previousTxid = ""; previousIndex = 0; scriptSig = ""; sequence = 0; witness = [] }, count);
    var i = 0;
    while (i < count) {
      let previousTxid = switch (r.take(32)) { case null return null; case (?v) v };
      let previousIndex = switch (r.le(4)) { case null return null; case (?v) Nat32.fromNat(v) };
      let scriptSig = switch (r.field()) { case null return null; case (?v) v };
      let sequence = switch (r.le(4)) { case null return null; case (?v) Nat32.fromNat(v) };
      inputs[i] := { previousTxid; previousIndex; scriptSig; sequence; witness = [] };
      i += 1;
    };
    let outputCount = switch (r.compact()) { case null return null; case (?v) v };
    if (outputCount > r.remaining() / 9) return null;
    let outputs = VarArray.repeat<Output>({ value = 0; scriptPubKey = "" }, outputCount);
    i := 0;
    while (i < outputCount) {
      let value = switch (r.le(8)) { case null return null; case (?v) Nat64.fromNat(v) };
      let scriptPubKey = switch (r.field()) { case null return null; case (?v) v };
      outputs[i] := { value; scriptPubKey };
      i += 1;
    };
    let inputArray = inputs;
    if (witness) {
      var anyWitness = false;
      i := 0;
      while (i < count) {
        let n = switch (r.compact()) { case null return null; case (?v) v };
        if (n > r.remaining()) return null;
        if (n != 0) anyWitness := true;
        let stack = VarArray.repeat<Blob>("", n);
        var j = 0;
        while (j < n) {
          let item = switch (r.field()) { case null return null; case (?v) v };
          stack[j] := item;
          j += 1;
        };
        let input = inputArray[i];
        inputArray[i] := { input with witness = stack.toArray() };
        i += 1;
      };
      if (not anyWitness) return null;
    };
    let lockTime = switch (r.le(4)) { case null return null; case (?v) Nat32.fromNat(v) };
    if (r.remaining() != 0) return null;
    ?{ version; inputs = inputArray.toArray(); outputs = outputs.toArray(); lockTime }
  };

  func doubleHash(bytes : Blob) : Blob = SHA256.digest(SHA256.digest(bytes));
  func reverse(bytes : Blob) : Blob {
    Blob.fromArray(Array.tabulate<Nat8>(bytes.size(), func(i) { bytes[bytes.size() - 1 - i] }))
  };
  /// Transaction ID in explorer/display byte order, excluding all witness data.
  public func txid(tx : Tx) : ?Blob {
    switch (serialize(tx, false)) { case null null; case (?b) ?reverse(doubleHash(b)) }
  };
  /// Witness transaction ID in explorer/display byte order. Equals txid when
  /// every input has an empty witness stack.
  public func wtxid(tx : Tx) : ?Blob {
    switch (serialize(tx, true)) { case null null; case (?b) ?reverse(doubleHash(b)) }
  };

  // Remove opcode 0xab only at opcode boundaries. Pushed 0xab bytes survive.
  // A malformed push rejects the script instead of interpreting payload bytes.
  func withoutCodeSeparators(script : Blob) : ?Blob {
    let bytes = script;
    var keep : ?[var Bool] = null;
    var removed = 0;
    var offset = 0;
    while (offset < bytes.size()) {
      let op = bytes[offset].toNat();
      if (op == 0xab) {
        let marks = switch keep {
          case (?marks) marks;
          case null { let marks = VarArray.repeat<Bool>(true, bytes.size()); keep := ?marks; marks };
        };
        marks[offset] := false;
        removed += 1;
      };
      offset += 1;
      if (op <= 0x4e) {
        var n = op;
        if (op >= 0x4c) {
          let width = if (op == 0x4c) 1 else if (op == 0x4d) 2 else 4;
          if (width + offset > bytes.size()) return null;
          n := 0;
          var factor = 1;
          var i = 0;
          while (i < width) { n += bytes[offset].toNat() * factor; factor *= 256; offset += 1; i += 1 };
        };
        if (n + offset > bytes.size()) return null;
        offset += n;
      };
    };
    if (removed == 0) return ?script;
    let ?marks = keep else return ?script;
    let w = Writer(bytes.size() - removed);
    offset := 0;
    while (offset < bytes.size()) { if (marks[offset]) w.byte(bytes[offset]); offset += 1 };
    ?w.finish()
  };

  /// Original signature hash, including ALL/NONE/SINGLE and ANYONECANPAY.
  /// Unknown base modes have Bitcoin's legacy ALL behavior. OP_CODESEPARATORs
  /// are removed at opcode boundaries; malformed pushes return null. The caller
  /// supplies the script after the last executed separator, and must remove the
  /// checked signature(s) via legacy FindAndDelete if verifying existing scripts.
  /// An out-of-range input or SINGLE without a corresponding output returns the
  /// historical little-endian uint256(1), not a normal transaction digest.
  public func signatureHashLegacy(tx : Tx, index : Nat, scriptCode : Blob, hashType : Nat32) : ?Blob {
    if (not valid(tx)) return null;
    let mode = hashType & 0x1f;
    if (index >= tx.inputs.size() or (mode == 3 and index >= tx.outputs.size())) return ?one32;
    let script = switch (withoutCodeSeparators(scriptCode)) { case null return null; case (?b) b };
    let anyone = hashType & 0x80 != 0;
    let inputCount = if (anyone) 1 else tx.inputs.size();
    let outputCount = if (mode == 2) 0 else if (mode == 3) index + 1 else tx.outputs.size();
    var size = 11 + compactSize(inputCount) + inputCount * 41 + fieldSize(script) + compactSize(outputCount);
    if (mode == 3) size += index * 9 + outputSize(tx.outputs[index])
    else if (mode != 2) { for (output in tx.outputs.values()) { size += outputSize(output) } };
    let w = Writer(size);
    w.le32(tx.version);
    w.compact(inputCount);
    var i = 0;
    while (i < inputCount) {
      let n = if (anyone) index else i;
      let input = tx.inputs[n];
      w.outpoint(input);
      w.field(if (n == index) script else "");
      w.le32(if (n != index and (mode == 2 or mode == 3)) 0 else input.sequence);
      i += 1;
    };
    w.compact(outputCount);
    i := 0;
    while (i < outputCount) {
      if (mode == 3 and i != index) { w.le64(0xffff_ffff_ffff_ffff); w.byte(0) }
      else w.output(tx.outputs[i]);
      i += 1;
    };
    w.le32(tx.lockTime);
    w.le32(hashType);
    ?doubleHash(w.finish())
  };

  func outpoints(tx : Tx) : Blob {
    let w = Writer(tx.inputs.size() * 36);
    for (input in tx.inputs.values()) w.outpoint(input);
    w.finish()
  };
  func sequences(tx : Tx) : Blob {
    let w = Writer(tx.inputs.size() * 4);
    for (input in tx.inputs.values()) w.le32(input.sequence);
    w.finish()
  };
  func outputsBytes(outputs : [Output]) : Blob {
    var size = 0;
    for (output in outputs.values()) { size += outputSize(output) };
    let w = Writer(size);
    for (output in outputs.values()) w.output(output);
    w.finish()
  };
  func outputBytes(output : Output) : Blob { let w = Writer(outputSize(output)); w.output(output); w.finish() };

  /// BIP143 signature hash. `scriptCode` has no CompactSize prefix and must
  /// already be sliced after the last executed OP_CODESEPARATOR. Separators
  /// after that point remain, and signatures are not removed. Returns null for
  /// an invalid transaction, an out-of-range index or an unencodable script.
  public func signatureHashSegwitV0(tx : Tx, index : Nat, scriptCode : Blob, value : Nat64, hashType : Nat32) : ?Blob {
    switch (prepareSegwitV0(tx)) {
      case null null;
      case (?prepared) prepared.signatureHash(index, scriptCode, value, hashType);
    }
  };

  public type SegwitV0Hasher = {
    signatureHash : (index : Nat, scriptCode : Blob, value : Nat64, hashType : Nat32) -> ?Blob;
  };

  /// Prepare a reusable BIP143 hasher tied to this immutable transaction.
  /// Common hashes are lazy and retained across inputs, removing repeated
  /// transaction-wide hashing when signing many inputs. The returned closure
  /// cannot accidentally be combined with a different transaction.
  public func prepareSegwitV0(tx : Tx) : ?SegwitV0Hasher {
    if (not valid(tx)) return null;
    var prevoutsHash : ?Blob = null;
    var sequencesHash : ?Blob = null;
    var outputsHash : ?Blob = null;
    func prevouts() : Blob {
      switch prevoutsHash { case (?v) v; case null { let v = doubleHash(outpoints(tx)); prevoutsHash := ?v; v } }
    };
    func sequenceHash() : Blob {
      switch sequencesHash { case (?v) v; case null { let v = doubleHash(sequences(tx)); sequencesHash := ?v; v } }
    };
    func outputHash() : Blob {
      switch outputsHash { case (?v) v; case null { let v = doubleHash(outputsBytes(tx.outputs)); outputsHash := ?v; v } }
    };
    ?(object {
      public func signatureHash(index : Nat, scriptCode : Blob, value : Nat64, hashType : Nat32) : ?Blob {
        if (index >= tx.inputs.size() or scriptCode.size() > max64) return null;
        let mode = hashType & 0x1f;
        let anyone = hashType & 0x80 != 0;
        let input = tx.inputs[index];
        let w = Writer(156 + fieldSize(scriptCode));
        w.le32(tx.version);
        w.raw(if (anyone) zero32 else prevouts());
        w.raw(if (anyone or mode == 2 or mode == 3) zero32 else sequenceHash());
        w.outpoint(input);
        w.field(scriptCode);
        w.le64(value);
        w.le32(input.sequence);
        w.raw(if (mode != 2 and mode != 3) outputHash() else if (mode == 3 and index < tx.outputs.size()) doubleHash(outputBytes(tx.outputs[index])) else zero32);
        w.le32(tx.lockTime);
        w.le32(hashType);
        ?doubleHash(w.finish())
      }
    })
  };

  /// BIP341/BIP342 signature hash. `prevouts` supplies the value and raw
  /// scriptPubKey for every input, in input order, even for ANYONECANPAY. An annex
  /// includes its 0x50 prefix. `extension = null` selects a key-path spend;
  /// an extension selects tapscript, using key version 0. Returns null for
  /// invalid parameters or SINGLE without a corresponding output.
  public func signatureHashTaproot(tx : Tx, index : Nat, prevouts : [Output], hashType : Nat8, annex : ?Blob, extension : ?TapscriptExtension) : ?Blob {
    switch (prepareTaproot(tx, prevouts)) {
      case null null;
      case (?prepared) prepared.signatureHash(index, hashType, annex, extension);
    }
  };

  public type TaprootHasher = {
    signatureHash : (index : Nat, hashType : Nat8, annex : ?Blob, extension : ?TapscriptExtension) -> ?Blob;
  };

  /// Prepare a reusable BIP341/342 hasher tied to this transaction and its spent
  /// outputs. Hashes are lazy, so ANYONECANPAY does not hash unrelated inputs.
  /// Every prevout must be supplied, in input order. No field is mutable.
  public func prepareTaproot(tx : Tx, prevouts : [Output]) : ?TaprootHasher {
    if (not valid(tx) or prevouts.size() != tx.inputs.size()) return null;
    for (output in prevouts.values()) { if (output.scriptPubKey.size() > max64) return null };
    var prevoutsHash : ?Blob = null;
    var amountsHash : ?Blob = null;
    var scriptsHash : ?Blob = null;
    var sequencesHash : ?Blob = null;
    var outputsHash : ?Blob = null;
    var tagHash : ?Blob = null;
    func points() : Blob {
      switch prevoutsHash { case (?v) v; case null { let v = SHA256.digest(outpoints(tx)); prevoutsHash := ?v; v } }
    };
    func amounts() : Blob {
      switch amountsHash {
        case (?v) v;
        case null {
          let w = Writer(prevouts.size() * 8);
          for (output in prevouts.values()) w.le64(output.value);
          let v = SHA256.digest(w.finish()); amountsHash := ?v; v
        };
      }
    };
    func scripts() : Blob {
      switch scriptsHash {
        case (?v) v;
        case null {
          var size = 0;
          for (output in prevouts.values()) { size += fieldSize(output.scriptPubKey) };
          let w = Writer(size);
          for (output in prevouts.values()) w.field(output.scriptPubKey);
          let v = SHA256.digest(w.finish()); scriptsHash := ?v; v
        };
      }
    };
    func sequenceHash() : Blob {
      switch sequencesHash { case (?v) v; case null { let v = SHA256.digest(sequences(tx)); sequencesHash := ?v; v } }
    };
    func outputHash() : Blob {
      switch outputsHash { case (?v) v; case null { let v = SHA256.digest(outputsBytes(tx.outputs)); outputsHash := ?v; v } }
    };
    func tag() : Blob {
      switch tagHash { case (?v) v; case null { let v = SHA256.digest("TapSighash"); tagHash := ?v; v } }
    };
    ?(object {
      public func signatureHash(index : Nat, hashType : Nat8, annex : ?Blob, extension : ?TapscriptExtension) : ?Blob {
        if (index >= tx.inputs.size()) return null;
        if (hashType != 0 and hashType != 1 and hashType != 2 and hashType != 3 and hashType != 0x81 and hashType != 0x82 and hashType != 0x83) return null;
        let mode = hashType & 3;
        if (mode == 3 and index >= tx.outputs.size()) return null;
        let anyone = hashType & 0x80 != 0;
        let input = tx.inputs[index];
        let prevout = prevouts[index];
        var spendType : Nat8 = 0;
        var size = 64 + 1 + 1 + 4 + 4 + 1;
        if (anyone) size += 48 + fieldSize(prevout.scriptPubKey) else size += 128 + 4;
        if (mode != 2 and mode != 3) size += 32;
        if (mode == 3) size += 32;
        switch annex {
          case null {};
          case (?a) {
            if (a.size() == 0 or a.size() > max64 or a.values().next() != ?0x50) return null;
            spendType += 1;
            size += 32;
          };
        };
        switch extension {
          case null {};
          case (?ext) {
            if (ext.tapLeafHash.size() != 32) return null;
            spendType += 2;
            size += 37;
          };
        };
        // Include the tagged-hash prefix in the same allocation as SigMsg.
        let w = Writer(size);
        let t = tag(); w.raw(t); w.raw(t);
        w.byte(0); // sighash epoch
        w.byte(hashType);
        w.le32(tx.version);
        w.le32(tx.lockTime);
        if (not anyone) { w.raw(points()); w.raw(amounts()); w.raw(scripts()); w.raw(sequenceHash()) };
        if (mode != 2 and mode != 3) w.raw(outputHash());
        w.byte(spendType);
        if (anyone) {
          w.outpoint(input);
          w.le64(prevout.value);
          w.field(prevout.scriptPubKey);
          w.le32(input.sequence);
        } else w.le(index, 4);
        switch annex {
          case null {};
          case (?a) { let aw = Writer(fieldSize(a)); aw.field(a); w.raw(SHA256.digest(aw.finish())) };
        };
        if (mode == 3) w.raw(SHA256.digest(outputBytes(tx.outputs[index])));
        switch extension {
          case null {};
          case (?ext) { w.raw(ext.tapLeafHash); w.byte(0); w.le32(ext.codeSeparatorPosition) };
        };
        ?SHA256.digest(w.finish())
      }
    })
  };
}
