//MOC-FLAG --package fast ../../../../../packages/fast/src --plugin ../../../../../dist/ml-dsa
import MLDSA "mo:fast/MLDSA";
persistent actor { public shared func consume(_key : MLDSA.PreparedPublicKey) : async () {} };
