//MOC-FLAG --package fast ../../src --plugin ../../../../dist/bech32
import Bech32 "mo:fast/Bech32";
let width : Nat = 8;
Bech32.convertBits("", width, 5, true);
