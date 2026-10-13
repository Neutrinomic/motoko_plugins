// Shared assertions run on the interpreter/Wasm and in an Ash canister after GC.
import Prim "mo:⛔";
import SHA256 "mo:fast/SHA256";
import SHA512 "mo:fast/SHA512";
import RIPEMD160 "mo:fast/RIPEMD160";
import HMAC "mo:fast/HMAC";
import BLAKE3 "mo:fast/BLAKE3";
import V "Vectors";

module {
  func data(initial : Nat32, size : Nat) : Blob {
    var seed = initial;
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func(_) {
      seed ^= seed << 13; seed ^= seed >> 17; seed ^= seed << 5;
      Prim.natToNat8(Prim.nat32ToNat(seed & 255))
    }))
  };
  func cut(input : Blob, start : Nat, size : Nat) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func(i) { input[start + i] }))
  };
  func ok<T>(value : BLAKE3.Result<T>) : T {
    switch value { case (#ok v) v; case (#err e) Prim.trap(debug_show e) }
  };
  func some(value : ?Blob) : Blob {
    switch value { case (?v) v; case null Prim.trap("rejected hash state") }
  };
  func official(start : Nat, size : Nat) : Blob {
    Prim.arrayToBlob(Prim.Array_tabulate<Nat8>(size, func(i) { Prim.natToNat8((start + i) % 251) }))
  };
  func write(streams : [HMAC.Digest], input : Blob) {
    let schedule = [1, 127, 3, 64, 129, 7, 55, 128];
    var pos = 0; var step = 0;
    while (pos < input.size()) {
      let remaining : Nat = input.size() - pos;
      let count = if (remaining < schedule[step % schedule.size()]) remaining else schedule[step % schedule.size()];
      let chunk = cut(input, pos, count);
      for (stream in streams.values()) { stream.write(""); stream.write(chunk) };
      pos += count; step += 1;
    };
  };
  public type Entry = { finish : () -> (); replay : () -> () };
  class Case(v : V.Case) : Entry {
    let message : Blob = data(v.seed, v.length);
    let key : Blob = data(v.seed ^ 0xa5a55a5a, v.keyLength);
    let p256 : HMAC.PreparedKey = HMAC.prepareSha256(key);
    let p512 : HMAC.PreparedKey = HMAC.prepareSha512(key);
    let ripe : RIPEMD160.Digest = RIPEMD160.Digest();
    let streams : [HMAC.Digest] = [
      SHA512.Digest(), SHA512.Digest384(),
      { write = func(b : Blob) { assert ripe.write(b) }; sum = ripe.sum; reset = ripe.reset },
      p256.stream(), p512.stream(),
    ];
    let prefix : Blob = cut(message, 0, v.split);
    let suffix : Blob = cut(message, v.split, v.length - v.split);
    let ripeSnapshot : Blob = some(RIPEMD160.update(RIPEMD160.init(), prefix));
    do { write(streams, prefix) };
    // Retain detached sum outputs and bound methods as ordinary managed values.
    let saved : [Blob] = Prim.Array_tabulate<Blob>(5, func(i) { streams[i].sum() });
    let callback : Blob -> Blob = p512.digest;
    public func finish() {
      assert SHA256.digest(message) == v.full[0];
      assert SHA512.digest(message) == v.full[1];
      assert SHA512.digest384(message) == v.full[2];
      assert RIPEMD160.digest(message) == v.full[3];
      assert HMAC.sha256(key, message) == v.full[4];
      assert HMAC.sha512(key, message) == v.full[5];
      assert HMAC.sha256(message, message) == v.selfMac[0];
      assert HMAC.sha512(message, message) == v.selfMac[1];
      for (i in [0,1,2,3,4].values()) {
        assert saved[i] == v.prefix[i + 1];
        assert streams[i].sum() == saved[i];
      };
      assert callback(message) == v.full[5];
      // Creating and resetting siblings must not affect existing partial streams.
      let left = p512.stream(); let right = p512.stream();
      left.write(message); right.write(prefix); left.reset();
      assert left.sum() == v.emptyMac[1];
      assert right.sum() == v.prefix[5];
      right.write(suffix); assert right.sum() == v.full[5];
      write(streams, suffix);
      for (i in [0,1,2,3,4].values()) {
        assert streams[i].sum() == v.full[i + 1];
        assert streams[i].sum() == v.full[i + 1];
        assert saved[i] == v.prefix[i + 1];
      };
      assert RIPEMD160.finalize(ripeSnapshot) == ?v.prefix[3];
      assert RIPEMD160.finalize(some(RIPEMD160.update(ripeSnapshot, suffix))) == ?v.full[3];
      assert p256.digest(message) == v.full[4];
      assert p512.digest(message) == v.full[5];
      assert p256.digest("") == v.emptyMac[0];
      assert p512.digest("") == v.emptyMac[1];
    };
    public func replay() {
      for (i in [0,1,2,3,4].values()) { assert streams[i].sum() == v.full[i + 1] };
      for (stream in streams.values()) { stream.reset(); stream.reset() };
      assert streams[3].sum() == v.emptyMac[0];
      assert streams[4].sum() == v.emptyMac[1];
      write(streams, message);
      for (i in [0,1,2,3,4].values()) { assert streams[i].sum() == v.full[i + 1] };
      assert callback(message) == v.full[5];
      assert message == data(v.seed, v.length);
      assert key == data(v.seed ^ 0xa5a55a5a, v.keyLength);
    };
  };
  class Tree(mode : Nat) : { finish : () -> () } {
    let initial : Blob = if (mode == 0) BLAKE3.new() else if (mode == 1) ok(BLAKE3.newKeyed("whats the Elvish word for friend")) else BLAKE3.newDeriveKey("BLAKE3 2019-12-27 16:29:52 test vectors context");
    let snapshot : Blob = ok(BLAKE3.update(initial, official(0, 1025)));
    let left : Blob = ok(BLAKE3.update(snapshot, official(1025, 1023)));
    let right : Blob = ok(BLAKE3.update(snapshot, official(1025, 3071)));
    func check(state : Blob, index : Nat) {
      let expected = V.blake3[index].1[mode];
      assert ok(BLAKE3.finalize(state)) == cut(expected, 0, 32);
      assert ok(BLAKE3.finalizeXof(state, 63, 68)) == cut(expected, 63, 68);
      assert ok(BLAKE3.update(state, "")) == state;
    };
    public func finish() {
      check(snapshot, 1); check(left, 2); check(right, 4);
      check(ok(BLAKE3.update(left, official(2048, 1))), 3);
      check(ok(BLAKE3.update(right, official(4096, 1))), 5);
      check(snapshot, 1); check(left, 2); check(right, 4);
      let complete = official(0, 4097);
      let direct = if (mode == 0) BLAKE3.digest(complete) else if (mode == 1) ok(BLAKE3.keyedHash("whats the Elvish word for friend", complete)) else BLAKE3.deriveKey("BLAKE3 2019-12-27 16:29:52 test vectors context", complete);
      assert direct == cut(V.blake3[5].1[mode], 0, 32);
    };
  };
  public func contexts() {
    let input = official(0, 4097);
    for ((context, expected) in V.contexts.values()) {
      assert BLAKE3.deriveKey(context, input) == cut(expected, 0, 32);
      let prefix : Blob = ok(BLAKE3.update(BLAKE3.newDeriveKey(context), cut(input, 0, 1025)));
      let state = ok(BLAKE3.update(prefix, cut(input, 1025, 3072)));
      assert ok(BLAKE3.finalizeXof(state, 0, 131)) == expected;
      assert ok(BLAKE3.finalizeXof(state, 63, 68)) == cut(expected, 63, 68);
      assert ok(BLAKE3.update(state, "")) == state;
    };
  };
  public class Suite() : Entry {
    let cases : [Entry] = Prim.Array_tabulate<Case>(V.cases.size(), func(i) { Case(V.cases[i]) });
    let trees : [{ finish : () -> () }] = Prim.Array_tabulate<Tree>(3, func(i) { Tree(i) });
    public func finish() {
      for (entry in cases.values()) entry.finish();
      for (tree in trees.values()) tree.finish();
      contexts();
    };
    public func replay() {
      for (entry in cases.values()) entry.replay();
      for (tree in trees.values()) tree.finish();
    };
  };
}
