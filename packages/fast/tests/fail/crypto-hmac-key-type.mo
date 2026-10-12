//MOC-FLAG --package fast ../../src --plugin ../../../../dist/hmac-sha2
import HMAC "mo:fast/HMAC";
ignore HMAC.sha512(42, "message");
