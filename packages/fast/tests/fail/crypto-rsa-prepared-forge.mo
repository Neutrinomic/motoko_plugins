//MOC-FLAG --package fast ../../src --plugin ../../../../dist/rsa
import RSA "mo:fast/RSA";
let forged : RSA.PreparedPublicKey = "";
ignore RSA.verifyPrepared(forged, "", "");
