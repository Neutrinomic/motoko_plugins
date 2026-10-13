import Test "mo:test";
import Suite "../../../../tests/crypto-audit/round5/ed25519/Suite";

persistent actor {
  public func test_prefix_boundaries() : async Test.Metrics { Test.test(Suite.prefixBoundaries) };
  public func test_mixed_order_and_domains() : async Test.Metrics { Test.test(Suite.mixedOrderAndDomains) };
}
