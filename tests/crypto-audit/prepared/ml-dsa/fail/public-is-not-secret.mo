//MOC-FLAG --package fast ../../../../../packages/fast/src --plugin ../../../../../dist/ml-dsa
import MLDSA "mo:fast/MLDSA";
func misuse(key : MLDSA.PreparedPublicKey) { ignore MLDSA.signPrepared(key, "", "") };
