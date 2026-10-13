//MOC-FLAG --package fast ../../src --plugin ../../../../dist/rsa
import RSA "mo:fast/RSA";
func expose(key : RSA.PreparedPublicKey) : Blob { key };
