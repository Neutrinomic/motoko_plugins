//MOC-FLAG --package fast ../../src --plugin ../../../../dist/bls12-381
import B "mo:fast/BLS12381";
func aggregate(key : B.PreparedEthereumPublicKey) : B.Result<Bool> {
  B.aggregateVerifyEthereumPrepared([key], [""], "")
};
