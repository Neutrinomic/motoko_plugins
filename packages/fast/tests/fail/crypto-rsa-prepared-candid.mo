//MOC-FLAG --package fast ../../src --plugin ../../../../dist/rsa
import RSA "mo:fast/RSA";
func serialize(key : RSA.PreparedPublicKey) : Blob { to_candid(key) };
