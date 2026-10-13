//MOC-FLAG --plugin ../../../dist/candidx --plugin ../../../dist/p256
import Prim "mo:⛔";
func estimate(key : Prim.P256PreparedPublicKey) {
  ignore Prim.candid_estimate_size([key]);
};
