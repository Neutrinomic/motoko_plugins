//MOC-FLAG --package fast ../../src --package core $MOTOKO_CORE --plugin ../../../../dist/secp256k1 --sanity-checks
import Cases "../lib/Secp256k1Audit5Tests";

Cases.schnorrHashBoundaries();
Cases.malformedLengthsAndPrecedence();
