//MOC-FLAG --package fast ../../../../../packages/fast/src --plugin ../../../../../dist/ml-dsa
import MLDSA "mo:fast/MLDSA";
let key = (from_candid ("" : Blob) : ?MLDSA.PreparedSecretKey);
