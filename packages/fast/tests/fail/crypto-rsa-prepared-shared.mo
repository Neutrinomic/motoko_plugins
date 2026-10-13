//MOC-FLAG --package fast ../../src --plugin ../../../../dist/rsa
import RSA "mo:fast/RSA";
persistent actor {
  public func verify(key : RSA.PreparedPublicKey) : async Bool { false };
};
