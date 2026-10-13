//MOC-FLAG --plugin ../../../dist/candidx --plugin ../../../dist/p256
import Prim "mo:⛔";
func encode(key : Prim.P256PreparedPublicKey) {
  ignore Prim.to_candid_canonical({ key });
};
