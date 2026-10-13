//MOC-FLAG --package fast ../../../../../packages/fast/src --plugin ../../../../../dist/ml-dsa
import MLDSA "mo:fast/MLDSA";
persistent actor { var key : ?MLDSA.PreparedSecretKey = null };
