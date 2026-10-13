//MOC-FLAG --package fast ../../../../../packages/fast/src --plugin ../../../../../dist/ml-dsa
import MLDSA "mo:fast/MLDSA";
func expose(key : MLDSA.PreparedSecretKey) : Text { debug_show key };
