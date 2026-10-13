//MOC-FLAG --plugin ../../../../dist/ed25519
import Prim "mo:⛔";
let forged : Blob = "forged blob";
ignore Prim.ed25519_sign_prepared(forged, "message");
