import Test "mo:test";
import Cases "../lib/BitcoinCryptoTransactionCases";
import Vectors "../lib/BitcoinCryptoTransactionVectors";

persistent actor {
  public func test_bitcoin_core_bip143_bip341_vectors() : async Test.Metrics {
    Test.test(Vectors.run)
  };

  public func test_serialization_sighash_and_script_edges() : async Test.Metrics {
    Test.test(Cases.run)
  };
}
