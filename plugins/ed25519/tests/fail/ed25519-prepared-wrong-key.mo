//MOC-FLAG --plugin ../../../../dist/ed25519
import Prim "mo:⛔";
func wrong(key : Prim.Ed25519PreparedPublicKey) : Blob {
  Prim.ed25519_sign_prepared(key, "message")
};
