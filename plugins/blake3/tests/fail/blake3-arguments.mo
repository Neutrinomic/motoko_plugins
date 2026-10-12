//MOC-FLAG --plugin ../../../../dist/blake3
import Prim "mo:⛔";
ignore Prim.blake3_digest(42);
ignore Prim.blake3_keyed_hash("not bytes" : Text, "" : Blob);
ignore Prim.blake3_derive_key("" : Blob, "" : Blob);
ignore Prim.blake3_xof("" : Blob, 0 : Nat32, 32 : Nat64);
