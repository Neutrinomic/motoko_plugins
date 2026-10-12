//MOC-FLAG --package fast ../../src --plugin ../../../../dist/base58
import Base58 "mo:fast/Base58";
let _ : Text -> { #ok : Blob; #err : { #tooLarge; #invalidCharacter : Nat64 } } = Base58.decode;
