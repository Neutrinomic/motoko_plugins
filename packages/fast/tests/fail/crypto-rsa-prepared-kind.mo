//MOC-FLAG --package fast ../../src --plugin ../../../../dist/rsa
import RSA "mo:fast/RSA";
func wrong(key : RSA.PreparedSecretKey) : RSA.Result<Bool> {
  RSA.verifyPrepared(key, "", "")
};
