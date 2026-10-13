import Test "mo:test";
import Cases "../lib/Secp256k1Audit5Tests";

persistent actor {
  public func test_bip340_hash_padding_boundaries() : async Test.Metrics {
    Test.test(Cases.schnorrHashBoundaries)
  };
  public func test_malformed_lengths_and_error_precedence() : async Test.Metrics {
    Test.test(Cases.malformedLengthsAndPrecedence)
  };
}
