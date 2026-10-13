import Test "mo:test";
import Cases "../lib/BitcoinPropertiesCases";

persistent actor {
  public func test_bip32_private_public_derivation_relations() : async Test.Metrics {
    Test.test(Cases.bip32Relations)
  };
  public func test_sighash_commitment_and_exclusion_matrix() : async Test.Metrics {
    Test.test(Cases.sighashCommitments)
  };
  public func test_compactsize_count_boundaries() : async Test.Metrics {
    Test.test(Cases.wireCounts)
  };
}
