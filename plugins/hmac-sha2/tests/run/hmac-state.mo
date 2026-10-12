//MOC-FLAG --plugin ../../../../dist/hmac-sha2 --sanity-checks
import Prim "mo:⛔";

let initial256 = Prim.hmac_sha256_init("Jefe");
let initial512 = Prim.hmac_sha512_init("Jefe");
assert initial256.size() == 136;
assert initial512.size() == 272;
let a = Prim.blobToArray(initial256);
let b = Prim.blobToArray(initial512);
assert a[71] == 64;
assert b[143] == 128;
for (i in [72, 80, 127, 135].values()) { assert a[i] == 0 };
for (i in [144, 180, 255, 271].values()) { assert b[i] == 0 };
let current256 = Prim.hmac_sha256_update(initial256, "what do ya want for nothing?");
let current512 = Prim.hmac_sha512_update(initial512, "what do ya want for nothing?");
assert Prim.hmac_sha256_sum(current256) == Prim.hmac_sha256("Jefe", "what do ya want for nothing?");
assert Prim.hmac_sha512_sum(current512) == Prim.hmac_sha512("Jefe", "what do ya want for nothing?");
assert Prim.hmac_sha256_update(current256, "") == current256;
assert Prim.hmac_sha512_update(current512, "") == current512;
assert initial256 == Prim.hmac_sha256_init("Jefe");
assert initial512 == Prim.hmac_sha512_init("Jefe");
assert Prim.blobToArray(current256)[71] == 92;
assert Prim.blobToArray(current512)[143] == 156;
assert Prim.blobToArray(current256)[72] == 119;
assert Prim.blobToArray(current512)[144] == 119;
