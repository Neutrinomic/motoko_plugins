//MOC-FLAG --package fast ../../src --package core ../../.mops/core@2.5.0/src --plugin ../../../../dist/sha256 --plugin ../../../../dist/ripemd160 --plugin ../../../../dist/base58 --plugin ../../../../dist/bech32 --plugin ../../../../dist/secp256k1 --plugin ../../../../dist/hmac-sha2 --sanity-checks
import Cases "../lib/BitcoinCryptoAddressCases";
Cases.hashes();
Cases.legacyAndWitness();
Cases.bip86();
Cases.bip341Outputs();
Cases.invalidInputs();
Cases.composedWallet();
Cases.signedSegwitSpend();
Cases.signedTaprootSpends();
