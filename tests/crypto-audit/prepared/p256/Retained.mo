import Test "mo:test";
import P256 "mo:fast/P256";
import Cases "Cases";
import Prim "mo:⛔";

persistent actor Self {
  type Held = { prepared : P256.PreparedPublicKey; digest : Blob; signature : Blob; expected : Bool };
  transient var stored : ?Held = null;

  public func tick() : async () {};

  public func test_prepared_aliases_survive_actual_collection() : async Test.Metrics {
    let v = Cases.vectors[0];
    let reclaimedBefore = Prim.rts_reclaimed();
    ignore Prim.Array_init<Nat>(256 * 1024, 0);
    let prepared = Cases.ok(P256.preparePublicKey(Cases.copy(Cases.keys[v.key].compressed)));
    let held = { prepared; digest = Cases.copy(v.digest); signature = Cases.copy(v.signature); expected = v.expected };
    let nested = { entries = [?held]; read = func() : P256.PreparedPublicKey { prepared } };
    stored := ?held;
    func check() {
      let other = switch stored { case (?x) x; case null Prim.trap("missing retained prepared key") };
      assert P256.verifyPrehashPrepared(other.prepared, other.digest, other.signature) == #ok(other.expected);
      assert P256.verifyPrehashPrepared(nested.read(), held.digest, held.signature) == #ok(held.expected);
      switch (nested.entries[0]) {
        case (?x) assert P256.verifyPrehashPrepared(x.prepared, x.digest, x.signature) == #ok(x.expected);
        case null Prim.trap("missing nested prepared key");
      };
      assert P256.verifyPrehashPrepared(other.prepared, "", "") == #err(#invalidDigest);
    };
    check();
    // Force actual incremental collection across real message boundaries.
    var round = 0;
    while (round < 9) {
      var chunk = 0;
      while (chunk < 8) {
        ignore Prim.Array_init<Nat>(131_072, round + chunk);
        chunk += 1;
      };
      await Self.tick();
      check();
      round += 1;
    };
    var settle = 0;
    while (settle < 4) { await Self.tick(); check(); settle += 1 };
    assert Prim.rts_reclaimed() > reclaimedBefore + 4 * 1024 * 1024;
    stored := null;
    Test.test(func() {})
  };
}
