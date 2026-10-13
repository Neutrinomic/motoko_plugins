//MOC-FLAG --package fast ../../src --plugin ../../../../dist/p256
import P256 "mo:fast/P256";
func encode(key : P256.PreparedPublicKey) : Blob { to_candid(key) };
