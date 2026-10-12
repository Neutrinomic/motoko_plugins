//MOC-FLAG --plugin ../../../dist/sha256 --plugin ../../../dist/blake3 --plugin ../../../dist/sha512 --plugin ../../../dist/ripemd160 --plugin ../../../dist/hmac-sha2 --plugin ../../../dist/base58
//MOC-FLAG --package fast ../../../packages/fast/src --package core $MOTOKO_CORE --sanity-checks --force-gc
//SKIP run
//SKIP run-ir
//SKIP run-low
import Prim "mo:⛔";
import Array "mo:core/Array";
import BLAKE3 "mo:fast/BLAKE3";
import SHA512 "mo:fast/SHA512";
import RIPEMD160 "mo:fast/RIPEMD160";
import HMAC "mo:fast/HMAC";
import Base58Check "mo:fast/Base58Check";

actor {
  type Saved = {input : Blob; hash : Blob; digest : Blob; mac : Blob; encoded : Text};
  var saved : [Saved] = [];
  var state : Blob = "";
  var prefix : Blob = "";

  func ok<T, E>(result : {#ok : T; #err : E}) : T {
    switch result { case (#ok value) value; case (#err _) Prim.trap("crypto GC fixture failed") }
  };

  public func prepare() : async () {
    prefix := "stream state retained across collection";
    state := ok(BLAKE3.update(BLAKE3.new(), prefix));
    saved := Array.tabulate<Saved>(64, func(i) {
      let input = Prim.arrayToBlob(Array.tabulate<Nat8>(4096 + i, func(j) {
        Prim.natToNat8((i * 17 + j * 131) % 256)
      }));
      let hash = BLAKE3.digest(input);
      let digest = SHA512.digest(input);
      let mac = HMAC.sha256(hash, digest);
      {input; hash; digest; mac; encoded = Base58Check.encode(RIPEMD160.digest(mac))}
    });
  };

  func verify() {
    assert saved.size() == 64;
    for (entry in saved.values()) {
      assert BLAKE3.digest(entry.input) == entry.hash;
      assert SHA512.digest(entry.input) == entry.digest;
      assert HMAC.sha256(entry.hash, entry.digest) == entry.mac;
      assert ok(Base58Check.decode(entry.encoded)) == RIPEMD160.digest(entry.mac);
    };
    assert ok(BLAKE3.finalize(state)) == BLAKE3.digest(prefix);
    // Continue using a saved native streaming state after forwarding/collection.
    let next = ok(BLAKE3.update(state, " suffix"));
    assert ok(BLAKE3.finalize(next)) == BLAKE3.digest("stream state retained across collection suffix");
  };

  public func churn() : async () {
    var i = 0;
    while (i < 12) { ignore Prim.Array_init<Nat>(256 * 1024, i); i += 1 };
  };

  public func collectAndCheck() : async () {
    var i = 0;
    while (i < 4) { await async {}; verify(); i += 1 };
  };
};

//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress churn "DIDL\x00\x00"
//CALL ingress collectAndCheck "DIDL\x00\x00"
//CALL ingress prepare "DIDL\x00\x00"
//CALL ingress churn "DIDL\x00\x00"
//CALL ingress collectAndCheck "DIDL\x00\x00"
