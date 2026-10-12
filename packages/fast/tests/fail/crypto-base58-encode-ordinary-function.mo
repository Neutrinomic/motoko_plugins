//MOC-FLAG --package fast ../../src --plugin ../../../../dist/base58
import Base58 "mo:fast/Base58";
let _ : Blob -> Text = Base58.encode;
