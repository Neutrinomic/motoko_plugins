//MOC-FLAG --package fast ../../src --plugin ../../../../dist/sha256
import SHA256 "mo:fast/SHA256";
let _ : Blob -> Blob = SHA256.digest;
