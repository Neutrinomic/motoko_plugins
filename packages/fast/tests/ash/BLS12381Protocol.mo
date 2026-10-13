import Test "mo:test";
import Suite "../bls/ProtocolSuite";
persistent actor {
  public func test_ic_domains_and_independent_prepared_handles() : async Test.Metrics {
    Test.test(Suite.icDomains)
  };
  public func test_ethereum_domains_and_independent_prepared_handles() : async Test.Metrics {
    Test.test(Suite.ethereumDomains)
  };
  public func test_proof_and_signature_domains() : async Test.Metrics {
    Test.test(Suite.proofDomains)
  };
  public func test_dst_normalization_boundary() : async Test.Metrics {
    Test.test(Suite.dstBoundaries)
  };
}
