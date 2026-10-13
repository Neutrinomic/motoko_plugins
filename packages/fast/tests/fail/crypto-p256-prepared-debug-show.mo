//MOC-FLAG --package fast ../../src --plugin ../../../../dist/p256
import P256 "mo:fast/P256";
func show(key : P256.PreparedPublicKey) : Text { debug_show(key) };
