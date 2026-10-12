//MOC-FLAG --package fast ../../src --plugin ../../../../dist/blake3
import BLAKE3 "mo:fast/BLAKE3";
ignore BLAKE3.digest(42);
ignore BLAKE3.deriveKey("" : Blob, "" : Blob);
ignore BLAKE3.xof("" : Blob, 0 : Nat32, 32 : Nat64);
