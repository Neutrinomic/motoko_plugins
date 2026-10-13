//MOC-FLAG --package core ../../.mops/core@2.5.0/src --package fast ../../src --plugin ../../../../dist/base58 --plugin ../../../../dist/sha256 --plugin ../../../../dist/bech32 --sanity-checks
import Cases "../lib/CodecPropertiesCases";

Cases.conversionPadding();
Cases.bech32Substitutions();
Cases.base58BoundariesAndChecksum();
