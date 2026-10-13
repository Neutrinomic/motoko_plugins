//MOC-FLAG --plugin ../../../dist/ed25519 --plugin ../../../dist/p256
import Prim "mo:⛔";
func verify(key : Prim.Ed25519PreparedPublicKey) {
  ignore Prim.p256_verify_prehash_prepared(key, "", "");
};
