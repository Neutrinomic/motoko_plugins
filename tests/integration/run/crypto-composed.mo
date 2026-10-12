//MOC-FLAG --plugin ../../../dist/sha256 --plugin ../../../dist/blake3 --plugin ../../../dist/sha512 --plugin ../../../dist/ripemd160 --plugin ../../../dist/hmac-sha2 --plugin ../../../dist/base58 --plugin ../../../dist/bech32
//MOC-FLAG --package fast ../../../packages/fast/src --package core $MOTOKO_CORE --sanity-checks
import Prim "mo:⛔";
import SHA256 "mo:fast/SHA256";
import BLAKE3 "mo:fast/BLAKE3";
import SHA512 "mo:fast/SHA512";
import RIPEMD160 "mo:fast/RIPEMD160";
import HMAC "mo:fast/HMAC";
import Base58Check "mo:fast/Base58Check";
import Bech32 "mo:fast/Bech32";

func ok<T, E>(result : {#ok : T; #err : E}) : T {
  switch result { case (#ok value) value; case (#err _) Prim.trap("crypto composition failed") }
};

let input : Blob = "abc";
// Independent HASH160 answer generated with Python hashlib, rather than a round trip.
assert RIPEMD160.digest(SHA256.digest(input)) == "\bb\1b\e9\8c\14\24\44\d7\a5\6a\a3\98\1c\39\42\a9\78\e4\dc\33";
let key = BLAKE3.deriveKey("motoko-fast integration key v1", input);
let payload = HMAC.sha512(key, SHA512.digest(input));
assert payload.size() == 64;
let address = Base58Check.encode(payload);
assert ok(Base58Check.decode(address)) == payload;
let words = ok(Bech32.convertBits(payload, 8, 5, true));
// Bech32's 90-character limit applies even when the data is not a Bitcoin address.
let shortPayload = SHA256.digest(payload);
let shortWords = ok(Bech32.convertBits(shortPayload, 8, 5, true));
let encoded = ok(Bech32.encode("fast", shortWords, #bech32m));
let decoded = ok(Bech32.decode(encoded));
assert decoded.hrp == "fast" and decoded.encoding == #bech32m;
assert ok(Bech32.convertBits(decoded.data, 5, 8, false)) == shortPayload;
assert words.size() > shortWords.size();

// Contexts, streaming snapshots and reusable HMAC keys remain independent.
assert key != BLAKE3.deriveKey("motoko-fast integration key v2", input);
let initial = BLAKE3.new();
let first = ok(BLAKE3.update(initial, "a"));
let complete = ok(BLAKE3.update(first, "bc"));
assert ok(BLAKE3.finalize(initial)) == BLAKE3.digest("");
assert ok(BLAKE3.finalize(first)) == BLAKE3.digest("a");
assert ok(BLAKE3.finalize(complete)) == BLAKE3.digest(input);
let prepared = HMAC.prepareSha256(key);
let stream = prepared.stream();
stream.write("a"); stream.write("bc");
assert stream.sum() == HMAC.sha256(key, input);
assert prepared.digest(input) == stream.sum();
assert input == "abc";

// Failed decodes must not leave native state that affects later operations.
switch (Base58Check.decode("0")) { case (#err _) {}; case _ assert false };
switch (Bech32.decode("invalid")) { case (#err _) {}; case _ assert false };
assert ok(Base58Check.decode(address)) == payload;
assert ok(Bech32.decode(encoded)).data == shortWords;
