//MOC-FLAG --package fast ../../src --plugin ../../../../dist/bech32
import Bech32 "mo:fast/Bech32";
Bech32.encode("bc", [1, 2, 3], #bech32);
