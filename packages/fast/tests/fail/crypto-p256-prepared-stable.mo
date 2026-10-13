//MOC-FLAG --package fast ../../src --plugin ../../../../dist/p256
import P256 "mo:fast/P256";
persistent actor { stable var key : ?P256.PreparedPublicKey = null };
