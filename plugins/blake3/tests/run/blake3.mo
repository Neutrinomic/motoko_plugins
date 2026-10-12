//MOC-FLAG --plugin ../../../../dist/blake3 --sanity-checks
import Prim "mo:⛔";
assert Prim.blake3_digest("") == "\af\13\49\b9\f5\f9\a1\a6\a0\40\4d\ea\36\dc\c9\49\9b\cb\25\c9\ad\c1\12\b7\cc\9a\93\ca\e4\1f\32\62";
assert Prim.blake3_keyed_hash("", "") == #err(#invalidKey);
assert Prim.blake3_finalize_xof(Prim.blake3_new(), 0, 32) == #ok(Prim.blake3_digest(""));
assert Prim.blake3_derive_key("BLAKE3 2019-12-27 16:29:52 test vectors context", "") == "\2c\c3\97\83\c2\23\15\4f\ea\8d\fb\7c\1b\16\60\f2\ac\2d\cb\d1\c1\de\82\77\b0\b0\dd\39\b7\e5\0d\7d";
