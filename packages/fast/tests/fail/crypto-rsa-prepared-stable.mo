//MOC-FLAG --package fast ../../src --plugin ../../../../dist/rsa
import RSA "mo:fast/RSA";
actor {
  var key : ?RSA.PreparedSecretKey = null;
};
