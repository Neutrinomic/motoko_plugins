// Bounded verifier primitives for the certified-relay cost experiment.
// Invalid input traps. This is deliberately not a production certificate API.
import Array "mo:core/Array";
import Blob "mo:core/Blob";
import Nat8 "mo:core/Nat8";
import Text "mo:core/Text";
import VarArray "mo:core/VarArray";
import SHA256 "mo:fast/SHA256";
import BLS "mo:fast/BLS12381";

module {
  public type Tree = {
    #empty;
    #fork : (Tree, Tree);
    #labeled : (Blob, Tree);
    #leaf : Blob;
    #pruned : Blob;
  };
  public type Delegation = { subnet_id : Blob; certificate : Blob };
  public type Cert = { tree : Tree; signature : Blob; delegation : ?Delegation };

  func require<T>(value : ?T) : T {
    switch value { case (?x) x; case null { assert false; loop {} } }
  };

  public func concat(parts : [Blob]) : Blob {
    var size = 0;
    for (part in parts.values()) size += part.size();
    let out = VarArray.repeat<Nat8>(0, size);
    var i = 0;
    for (part in parts.values()) {
      for (b in part.values()) { out[i] := b; i += 1 }
    };
    Blob.fromVarArray(out)
  };

  class Reader(input : Blob) {
    assert input.size() <= 65_536;
    let data = input.toArray();
    var position = 0;
    var nodes = 0;

    func byte() : Nat {
      assert position < data.size();
      let result = data[position].toNat();
      position += 1;
      result
    };

    func header() : (Nat, Nat) {
      let first = byte();
      let major = first / 32;
      let additional = first % 32;
      if (additional < 24) return (major, additional);
      let count = switch additional {
        case 24 1; case 25 2; case 26 4; case 27 8;
        case _ { assert false; 0 };
      };
      var value = 0;
      var i = 0;
      while (i < count) { value := value * 256 + byte(); i += 1 };
      (major, value)
    };

    func item(major : Nat) : Nat {
      let (actual, size) = header();
      assert actual == major;
      size
    };

    func slice(major : Nat) : Blob {
      let size = item(major);
      assert size + position <= data.size();
      let start = position;
      position += size;
      Blob.fromArray(Array.tabulate<Nat8>(size, func i { data[start + i] }))
    };

    func text() : Text { require(slice(3).decodeUtf8()) };

    func optionalTag() {
      assert position < data.size();
      if (data[position].toNat() / 32 == 6) {
        assert item(6) == 55_799;
      }
    };

    func tree(depth : Nat) : Tree {
      assert depth <= 64;
      nodes += 1;
      assert nodes <= 4_096;
      let count = item(4);
      let tag = item(0);
      switch tag {
        case 0 { assert count == 1; #empty };
        case 1 {
          assert count == 3;
          let left = tree(depth + 1);
          let right = tree(depth + 1);
          #fork(left, right)
        };
        case 2 {
          assert count == 3;
          let lbl = slice(2);
          #labeled(lbl, tree(depth + 1))
        };
        case 3 { assert count == 2; #leaf(slice(2)) };
        case 4 {
          assert count == 2;
          let hash = slice(2);
          assert hash.size() == 32;
          #pruned(hash)
        };
        case _ { assert false; #empty };
      }
    };

    func delegation() : Delegation {
      assert item(5) == 2;
      var subnet : ?Blob = null;
      var certificate : ?Blob = null;
      var i = 0;
      while (i < 2) {
        switch (text()) {
          case "subnet_id" {
            assert subnet == null;
            let value = slice(2);
            assert value.size() <= 29;
            subnet := ?value
          };
          case "certificate" { assert certificate == null; certificate := ?slice(2) };
          case _ { assert false };
        };
        i += 1
      };
      { subnet_id = require(subnet); certificate = require(certificate) }
    };

    public func certificate() : Cert {
      optionalTag();
      let count = item(5);
      assert count == 2 or count == 3;
      var certTree : ?Tree = null;
      var signature : ?Blob = null;
      var certDelegation : ?Delegation = null;
      var i = 0;
      while (i < count) {
        switch (text()) {
          case "tree" { assert certTree == null; certTree := ?tree(0) };
          case "signature" {
            assert signature == null;
            let value = slice(2);
            assert value.size() == 48;
            signature := ?value
          };
          case "delegation" {
            assert certDelegation == null;
            certDelegation := ?delegation()
          };
          case _ { assert false };
        };
        i += 1
      };
      assert position == data.size();
      { tree = require(certTree); signature = require(signature); delegation = certDelegation }
    };

    public func witness() : Tree {
      optionalTag();
      let result = tree(0);
      assert position == data.size();
      result
    };

    public func contains(canister : Blob) : Bool {
      assert canister.size() <= 29;
      optionalTag();
      let count = item(4);
      assert count <= 4_096;
      var found = false;
      var previousEnd : ?Blob = null;
      var i = 0;
      while (i < count) {
        assert item(4) == 2;
        let start = slice(2);
        let end = slice(2);
        assert start.size() <= 29 and end.size() <= 29;
        assert Blob.compare(start, end) != #greater;
        switch previousEnd {
          case (?previous) { assert Blob.compare(previous, start) == #less };
          case null {};
        };
        previousEnd := ?end;
        if (Blob.compare(start, canister) != #greater and Blob.compare(canister, end) != #greater) {
          found := true
        };
        i += 1
      };
      assert position == data.size();
      found
    };
  };

  public func parse(input : Blob) : Cert { Reader(input).certificate() };

  public func parseTree(input : Blob) : Tree { Reader(input).witness() };

  public func rangeContains(encoded : Blob, canister : Blob) : Bool {
    Reader(encoded).contains(canister)
  };

  public func digest(tree : Tree) : Blob {
    switch tree {
      case (#empty) SHA256.digest("\11ic-hashtree-empty");
      case (#fork(left, right)) {
        SHA256.digest(concat(["\10ic-hashtree-fork", digest(left), digest(right)]))
      };
      case (#labeled(lbl, child)) {
        SHA256.digest(concat(["\13ic-hashtree-labeled", lbl, digest(child)]))
      };
      case (#leaf(value)) SHA256.digest(concat(["\10ic-hashtree-leaf", value]));
      case (#pruned(hash)) { assert hash.size() == 32; hash };
    }
  };

  // Positive inclusion only: both missing and pruned/unknown return null.
  // It must never be used to prove that an entry does not exist.
  public func lookup(path : [Blob], tree : Tree) : ?Blob {
    func walk(node : Tree, depth : Nat) : ?Blob {
      switch node {
        case (#leaf(value)) { if (depth == path.size()) ?value else null };
        case (#labeled(lbl, child)) {
          if (depth < path.size() and lbl == path[depth]) walk(child, depth + 1) else null
        };
        case (#fork(left, right)) {
          let a = walk(left, depth);
          let b = walk(right, depth);
          switch (a, b) {
            case (?_, ?_) { assert false; null };
            case (?_, null) a;
            case (null, _) b;
          }
        };
        case _ null;
      }
    };
    walk(tree, 0)
  };

  // Exact IC SubjectPublicKeyInfo encoding for a compressed BLS G2 key.
  public func rawDER96(der : Blob) : Blob {
    let prefix : Blob = "\30\81\82\30\1d\06\0d\2b\06\01\04\01\82\dc\7c\05\03\01\02\01\06\0c\2b\06\01\04\01\82\dc\7c\05\03\02\01\03\61\00";
    assert der.size() == prefix.size() + 96;
    let bytes = der.toArray();
    var i = 0;
    for (b in prefix.values()) { assert bytes[i] == b; i += 1 };
    Blob.fromArray(Array.tabulate<Nat8>(96, func j { bytes[prefix.size() + j] }))
  };

  public func lebTime(encoded : Blob) : Nat {
    assert encoded.size() > 0 and encoded.size() <= 10;
    var value = 0;
    var factor = 1;
    var index = 0;
    var done = false;
    for (b in encoded.values()) {
      assert not done;
      let n = b.toNat();
      assert index < 9 or n <= 1;
      value += (n % 128) * factor;
      if (n < 128) {
        assert index == 0 or n != 0;
        done := true
      } else { factor *= 128 };
      index += 1
    };
    assert done;
    value
  };

  public func timestamp(cert : Cert) : Nat {
    lebTime(require(lookup(["time"], cert.tree)))
  };

  public func stateRootMessage(root : Blob) : Blob {
    assert root.size() == 32;
    concat(["\0dic-state-root", root])
  };

  public func verifySignature(key : Blob, cert : Cert) : Bool {
    switch (BLS.verifyIC(key, stateRootMessage(digest(cert.tree)), cert.signature)) {
      case (#ok(valid)) valid;
      case (#err(_)) false;
    }
  };

  public func verifyPreparedSignature(key : BLS.PreparedICPublicKey, cert : Cert) : Bool {
    switch (BLS.verifyICPrepared(key, stateRootMessage(digest(cert.tree)), cert.signature)) {
      case (#ok(valid)) valid;
      case (#err(_)) false;
    }
  };
}
