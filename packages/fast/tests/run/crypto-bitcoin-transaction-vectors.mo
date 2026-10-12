//MOC-FLAG --package fast ../../src --package core $MOTOKO_CORE --plugin ../../../../dist/sha256 --sanity-checks
import Cases "../lib/BitcoinCryptoTransactionVectors";

Cases.run();
