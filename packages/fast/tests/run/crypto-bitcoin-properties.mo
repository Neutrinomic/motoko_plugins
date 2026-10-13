//MOC-FLAG --package fast ../../src --package core $MOTOKO_CORE --plugin ../../../../dist/sha256 --plugin ../../../../dist/ripemd160 --plugin ../../../../dist/hmac-sha2 --plugin ../../../../dist/secp256k1 --plugin ../../../../dist/base58 --sanity-checks
import Cases "../lib/BitcoinPropertiesCases";
Cases.bip32Relations();
Cases.sighashCommitments();
Cases.wireCounts();
