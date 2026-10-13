import Test "mo:test";
import Checks "../queue/Checks";

persistent actor {
  public query func test_chunk_boundaries_and_reuse() : async Test.Metrics {
    Test.test(Checks.boundaries)
  };
  public query func test_randomized_core_oracle() : async Test.Metrics {
    Test.test(Checks.model)
  };
  public query func test_public_surface_matches_core() : async Test.Metrics {
    Test.test(Checks.publicSurface)
  };
  public query func test_generic_payloads_and_aliases() : async Test.Metrics {
    Test.test(Checks.genericValues)
  };
  public query func test_native_bulk_exports_preserve_generic_values() : async Test.Metrics {
    Test.test(Checks.bulkExports)
  };
}
