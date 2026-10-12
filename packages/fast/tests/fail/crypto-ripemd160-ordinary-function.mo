//MOC-FLAG --package fast ../../src --plugin ../../../../dist/ripemd160
import Hash "mo:fast/RIPEMD160";
let _hash : Blob -> Blob = Hash.digest;
