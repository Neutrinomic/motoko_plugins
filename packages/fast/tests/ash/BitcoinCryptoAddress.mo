import Test "mo:test";
import Cases "../lib/BitcoinCryptoAddressCases";

persistent actor {
  public query func test_hashes() : async Test.Metrics { Test.test(Cases.hashes) };
  public query func test_legacy_and_witness_addresses() : async Test.Metrics { Test.test(Cases.legacyAndWitness) };
  public query func test_bip86_vectors() : async Test.Metrics { Test.test(Cases.bip86) };
  public query func test_bip341_output_vectors() : async Test.Metrics { Test.test(Cases.bip341Outputs) };
  public query func test_invalid_inputs_and_networks() : async Test.Metrics { Test.test(Cases.invalidInputs) };
  public func test_signed_taproot_spends() : async Test.Metrics { Test.test(Cases.signedTaprootSpends) };
  public query func test_signed_segwit_spend() : async Test.Metrics { Test.test(Cases.signedSegwitSpend) };
  public query func test_composed_watch_only_wallet() : async Test.Metrics { Test.test(Cases.composedWallet) };
}
