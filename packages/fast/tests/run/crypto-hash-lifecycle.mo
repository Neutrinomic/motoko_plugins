//MOC-FLAG --package fast ../../src --plugin ../../../../dist/sha256 --plugin ../../../../dist/sha512 --plugin ../../../../dist/ripemd160 --plugin ../../../../dist/hmac-sha2 --plugin ../../../../dist/blake3 --sanity-checks
import Audit "../../../../tests/crypto-audit/round5/hashes/Public";
let suite = Audit.Suite();
suite.finish();
suite.replay();
