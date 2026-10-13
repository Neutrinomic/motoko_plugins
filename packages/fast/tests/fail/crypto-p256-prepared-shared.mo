//MOC-FLAG --package fast ../../src --plugin ../../../../dist/p256
import P256 "mo:fast/P256";
persistent actor { public func accept(key : P256.PreparedPublicKey) : async () {} };
