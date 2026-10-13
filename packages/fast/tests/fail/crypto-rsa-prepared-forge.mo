//MOC-FLAG --package fast ../../src --plugin ../../../../dist/rsa
import RSA "mo:fast/RSA";
let bytes : Blob = "";
let forged : RSA.PreparedPublicKey = bytes;
ignore RSA.verifyPrepared(forged, "", "");
