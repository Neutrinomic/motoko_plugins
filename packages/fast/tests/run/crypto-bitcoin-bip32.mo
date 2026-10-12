//MOC-FLAG --package fast ../../src --package core $MOTOKO_CORE --plugin ../../../../dist/sha256 --plugin ../../../../dist/ripemd160 --plugin ../../../../dist/hmac-sha2 --plugin ../../../../dist/secp256k1 --plugin ../../../../dist/base58 --sanity-checks
import Cases "../lib/BitcoinCryptoBip32Cases";
Cases.officialRoundtrips();
Cases.officialDerivation();
Cases.invalidOfficialKeys();
Cases.pathValidation();
Cases.metadataValidation();
