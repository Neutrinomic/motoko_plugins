//MOC-FLAG --package fast ../../src --plugin ../../../../dist/sha512
import SHA512 "mo:fast/SHA512";
let _ : Blob -> Blob = SHA512.digest;
