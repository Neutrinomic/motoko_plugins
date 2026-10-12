import Test "mo:test";
import Cases "../lib/BitcoinCryptoBip32Cases";

persistent actor {
  public func test_official_roundtrips() : async Test.Metrics {
    Test.test(Cases.officialRoundtrips)
  };
  public func test_official_derivation() : async Test.Metrics {
    Test.test(Cases.officialDerivation)
  };
  public func test_invalid_official_keys() : async Test.Metrics {
    Test.test(Cases.invalidOfficialKeys)
  };
  public func test_path_validation() : async Test.Metrics {
    Test.test(Cases.pathValidation)
  };
  public func test_metadata_validation() : async Test.Metrics {
    Test.test(Cases.metadataValidation)
  };
}
