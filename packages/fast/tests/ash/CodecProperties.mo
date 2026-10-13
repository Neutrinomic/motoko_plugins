import Test "mo:test";
import Cases "../lib/CodecPropertiesCases";

persistent actor {
  public func test_all_width_padding_oracle() : async Test.Metrics {
    Test.test(Cases.conversionPadding)
  };
  public func test_bech32_single_character_substitutions() : async Test.Metrics {
    Test.test(Cases.bech32Substitutions)
  };
  public func test_base58_ascii_and_checksum_corruption() : async Test.Metrics {
    Test.test(Cases.base58BoundariesAndChecksum)
  };
}
