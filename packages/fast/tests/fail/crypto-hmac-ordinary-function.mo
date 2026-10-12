//MOC-FLAG --package fast ../../src --plugin ../../../../dist/hmac-sha2
import HMAC "mo:fast/HMAC";
let _ : (Blob, Blob) -> Blob = HMAC.sha256;
