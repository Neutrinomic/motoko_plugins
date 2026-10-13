//MOC-FLAG --plugin ../../../dist/ed25519 --plugin ../../../dist/p256
import Prim "mo:⛔";
func verify(key : Prim.P256PreparedPublicKey) {
  ignore Prim.ed25519_verify_prepared(key, "", "");
};
