//MOC-FLAG --package fast ../../src --plugin ../../../../dist/p256
import P256 "mo:fast/P256";
func expose(key : P256.PreparedPublicKey) : Blob { key };
